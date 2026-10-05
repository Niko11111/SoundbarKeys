import Foundation
import SoundbarKeysCore

struct BoseTokens: Codable {
    var access_token: String
    var refresh_token: String
    var azure_refresh_token: String
    var bose_person_id: String
}

enum TokenError: LocalizedError {
    case missing
    case requestFailed(String)
    case keychainFailed(Int32)

    var errorDescription: String? {
        switch self {
        case .missing: return String(localized: "Not signed in to your Bose account.")
        case .requestFailed(let why): return String(localized: "Request to the Bose account service failed: \(why)")
        case .keychainFailed(let status): return String(localized: "Keychain access failed (security exit code \(status)).")
        }
    }
}

/// Reads/writes the tokens in the Keychain in the same format as `tools/tokenstore.py`:
/// service `Config.keychainService`, accounts "tokens.count" + "tokens.0…n" (base64 JSON in chunks).
/// Access goes through /usr/bin/security so the Python login tool and the app share the
/// same items without Keychain prompts.
@MainActor
final class TokenStore {
    static let service = Config.keychainService

    private(set) var tokens: BoseTokens?

    private var refreshTask: Task<String, Error>?

    func load() throws -> BoseTokens {
        guard let countString = Self.read(account: "tokens.count"), let count = Int(countString) else {
            throw TokenError.missing
        }
        var blob = ""
        for i in 0..<count {
            guard let part = Self.read(account: "tokens.\(i)") else { throw TokenError.missing }
            blob += part
        }
        guard let data = Data(base64Encoded: blob) else { throw TokenError.missing }
        let t = try JSONDecoder().decode(BoseTokens.self, from: data)
        tokens = t
        return t
    }

    func save(_ t: BoseTokens) throws {
        let blob = try JSONEncoder().encode(t).base64EncodedString()
        let parts = TokenFormat.chunks(of: blob, size: Config.keychainChunkCharacters)
        // No `-T`: `security` trusts itself when it creates an item, and `-T` on an update (-U)
        // changes the access list, which makes macOS ask for the login password per item.
        let add = "add-generic-password -U -s \(Self.service)"
        var lines = parts.enumerated().map { "\(add) -a tokens.\($0.offset) -w \($0.element)" }
        lines.append("\(add) -a tokens.count -w \(parts.count)")
        try Self.runSecurity(args: ["-i"], stdin: lines.joined(separator: "\n") + "\n")
        tokens = t
    }

    /// Expiry of the current access token (from the JWT `exp` claim).
    var accessTokenExpiry: Date? {
        tokens.flatMap { TokenFormat.expiry(ofJWT: $0.access_token) }
    }

    /// Returns an access token that is valid for at least `Config.tokenRefreshMarginSeconds`.
    func validAccessToken() async throws -> String {
        if tokens == nil { _ = try load() }
        if let exp = accessTokenExpiry, exp.timeIntervalSinceNow > Config.tokenRefreshMarginSeconds, let t = tokens {
            return t.access_token
        }
        return try await refresh()
    }

    /// Refreshes the token. Concurrent callers share the same refresh.
    func refresh() async throws -> String {
        if let running = refreshTask { return try await running.value }
        let task = Task<String, Error> { try await self.performRefresh() }
        refreshTask = task
        defer { refreshTask = nil }
        return try await task.value
    }

    private func performRefresh() async throws -> String {
        let current = try tokens ?? load()
        // Azure AD B2C refresh → new id_token (+ possibly a new Azure refresh token)
        var request = URLRequest(url: BoseAPI.refreshTokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formEncode([
            "refresh_token": current.azure_refresh_token,
            "client_id": BoseAPI.clientID,
            "grant_type": "refresh_token",
        ])
        let azure = try await Self.postJSON(request, step: "Azure refresh")
        let updated = try await completeSignIn(azure: azure, previous: current)
        DiagLog.write("Token refreshed, valid until \(accessTokenExpiry.map { "\($0)" } ?? "?")")
        return updated.access_token
    }

    /// Exchanges the Azure id_token for Bose control tokens and stores them.
    /// Shared by the token refresh and the sign-in (`BoseLogin`).
    @discardableResult
    func completeSignIn(azure: [String: Any], previous: BoseTokens?) async throws -> BoseTokens {
        guard let idToken = azure["id_token"] as? String else {
            throw TokenError.requestFailed("Azure response without id_token")
        }
        let bose = try await Self.postJSON(try Self.boseExchangeRequest(idToken: idToken), step: "Bose token")
        guard let access = bose["access_token"] as? String,
              let azureRefresh = azure["refresh_token"] as? String ?? previous?.azure_refresh_token else {
            throw TokenError.requestFailed("Bose response without access_token")
        }
        let updated = BoseTokens(
            access_token: access,
            refresh_token: bose["refresh_token"] as? String ?? previous?.refresh_token ?? "",
            azure_refresh_token: azureRefresh,
            bose_person_id: bose["bosePersonID"] as? String ?? previous?.bose_person_id ?? ""
        )
        try save(updated)
        return updated
    }

    /// Deletes the tokens from the Keychain.
    func signOut() throws {
        let count = Self.read(account: "tokens.count").flatMap(Int.init) ?? 0
        let accounts = ["tokens.count"] + (0..<count).map { "tokens.\($0)" }
        let lines = accounts.map { "delete-generic-password -s \(Self.service) -a \($0)" }
        try Self.runSecurity(args: ["-i"], stdin: lines.joined(separator: "\n") + "\n")
        tokens = nil
        DiagLog.write("Signed out")
    }

    var isSignedIn: Bool { tokens != nil }

    private static func boseExchangeRequest(idToken: String) throws -> URLRequest {
        var request = URLRequest(url: BoseAPI.boseTokenURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(BoseAPI.apiKey, forHTTPHeaderField: "X-ApiKey")
        for header in ["X-Api-Version", "X-Software-Version", "X-Library-Version"] {
            request.setValue("1", forHTTPHeaderField: header)
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "grant_type": "id_token",
            "id_token": idToken,
            "client_id": BoseAPI.clientID,
            "scope": BoseAPI.scope,
        ])
        return request
    }

    // MARK: - Helpers

    private static func postJSON(_ req: URLRequest, step: String) async throws -> [String: Any] {
        let (data, resp) = try await URLSession.shared.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...201).contains(status),
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            let text = String(data: data, encoding: .utf8)?.prefix(200) ?? ""
            throw TokenError.requestFailed("\(step) HTTP \(status) \(text)")
        }
        return json
    }

    static func formEncode(_ params: [String: String]) -> Data {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return params.map { k, v in
            "\(k)=\(v.addingPercentEncoding(withAllowedCharacters: allowed) ?? v)"
        }.joined(separator: "&").data(using: .utf8)!
    }

    private static func read(account: String) -> String? {
        // A missing item makes `security` fail; for reading that simply means "not there".
        try? runSecurity(args: ["find-generic-password", "-s", service, "-a", account, "-w"])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @discardableResult
    private static func runSecurity(args: [String], stdin: String? = nil) throws -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        p.arguments = args
        let out = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()
        let inPipe = Pipe()
        if stdin != nil { p.standardInput = inPipe }
        try p.run()
        if let stdin {
            inPipe.fileHandleForWriting.write(stdin.data(using: .utf8)!)
            try inPipe.fileHandleForWriting.close()
        }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else {
            throw TokenError.keychainFailed(p.terminationStatus)
        }
        return String(data: data, encoding: .utf8) ?? ""
    }
}
