import CryptoKit
import Foundation

/// Pure helpers for the Bose account sign-in (OAuth code flow). No network here.
public enum LoginParsing {
    /// Authorization code from the final redirect (`bosemusic://auth/callback?code=…`).
    public static func authorizationCode(fromRedirect location: String) -> String? {
        queryValue("code", in: location)
    }

    /// Error text from a failed redirect (`…?error=access_denied&error_description=…`):
    /// the description if present, otherwise the error code. Nil if the redirect has no error.
    public static func callbackError(fromRedirect location: String) -> String? {
        guard let error = queryValue("error", in: location) else { return nil }
        return queryValue("error_description", in: location) ?? error
    }

    /// Query value with form decoding: OAuth servers encode spaces as "+", which
    /// URLComponents.queryItems leaves untouched.
    private static func queryValue(_ name: String, in location: String) -> String? {
        let raw = URLComponents(string: location)?.percentEncodedQueryItems?.first(where: { $0.name == name })?.value
        return raw?.replacingOccurrences(of: "+", with: " ").removingPercentEncoding
    }
}

/// PKCE (RFC 7636) for the OAuth code flow.
public struct PKCE: Sendable {
    public let verifier: String
    public let challenge: String

    /// - Parameter randomBytes: 32 random bytes (injected so the result is testable).
    public init(randomBytes: [UInt8]) {
        verifier = Self.base64URL(Data(randomBytes))
        challenge = Self.base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
