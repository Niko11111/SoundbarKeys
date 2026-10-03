import AppKit
import SoundbarKeysCore

enum LoginError: LocalizedError {
    /// Bose ended the sign-in with an error in the callback (e.g. access denied).
    case rejected(String)
    /// The callback came back without an authorization code.
    case noCode
    case tokenExchange(Int)

    var errorDescription: String? {
        switch self {
        case .rejected(let message): return String(localized: "Bose rejected the sign-in: \(message)")
        case .noCode: return String(localized: "The sign-in did not return an authorization code.")
        case .tokenExchange(let status): return String(localized: "Exchanging the sign-in code failed (HTTP \(status)).")
        }
    }
}

/// Signs in to the Bose account with Bose's own sign-in page (OAuth code flow with PKCE).
/// Whatever the page asks for (password, codes, captchas, password reset) is handled there;
/// SoundbarKeys does not read the form. The page redirects to `bosemusic://auth/callback?code=…`,
/// which `WebSignInWindow` intercepts.
///
/// Not ASWebAuthenticationSession: its window opened far too large for this page (which scales
/// with the width), and in a first test the callback never arrived, without any way to see why.
@MainActor
final class BoseLogin {
    private let tokens: TokenStore
    /// Kept alive while the window is open.
    private var window: WebSignInWindow?

    init(tokens: TokenStore) {
        self.tokens = tokens
    }

    /// Shows the sign-in window. Returns false if the user closed it.
    func signIn() async throws -> Bool {
        let pkce = PKCE(randomBytes: Self.randomBytes(count: 32))
        let window = WebSignInWindow(callbackScheme: Self.callbackScheme)
        self.window = window
        defer { self.window = nil }
        guard let callback = await window.run(url: Self.authorizeURL(pkce: pkce),
                                              title: String(localized: "Bose account")) else { return false }
        if let message = LoginParsing.callbackError(fromRedirect: callback.absoluteString) {
            throw LoginError.rejected(message)
        }
        guard let code = LoginParsing.authorizationCode(fromRedirect: callback.absoluteString) else {
            throw LoginError.noCode
        }
        let azure = try await exchange(code: code, pkce: pkce)
        try await tokens.completeSignIn(azure: azure, previous: nil)
        DiagLog.write("Signed in to the Bose account")
        return true
    }

    private func exchange(code: String, pkce: PKCE) async throws -> [String: Any] {
        var components = URLComponents(url: BoseAPI.codeTokenURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [.init(name: "p", value: BoseAPI.policy)]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.httpBody = TokenStore.formEncode([
            "client_id": BoseAPI.clientID, "code_verifier": pkce.verifier,
            "grant_type": "authorization_code", "scope": BoseAPI.scope,
            "redirect_uri": BoseAPI.redirectURI, "code": code,
        ])
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue(BoseAPI.webOrigin, forHTTPHeaderField: "Origin")
        request.setValue(BoseAPI.webOrigin + "/", forHTTPHeaderField: "Referer")
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200, let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LoginError.tokenExchange(status)
        }
        return json
    }

    // MARK: - Helpers

    private static var callbackScheme: String {
        URL(string: BoseAPI.redirectURI)?.scheme ?? "bosemusic"
    }

    private static func authorizeURL(pkce: PKCE) -> URL {
        var components = URLComponents(url: BoseAPI.authorizeURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            .init(name: "p", value: BoseAPI.policy),
            .init(name: "response_type", value: "code"),
            .init(name: "client_id", value: BoseAPI.clientID),
            .init(name: "scope", value: BoseAPI.scope),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "code_challenge", value: pkce.challenge),
            .init(name: "redirect_uri", value: BoseAPI.redirectURI),
            .init(name: "ui_locales", value: Locale.preferredLanguages.first ?? BoseAPI.loginLocale),
        ]
        return components.url!
    }

    private static func randomBytes(count: Int) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: count)
        let status = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        precondition(status == errSecSuccess, "SecRandomCopyBytes failed")
        return bytes
    }
}
