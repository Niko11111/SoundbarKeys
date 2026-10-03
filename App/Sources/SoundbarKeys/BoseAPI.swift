import Foundation

/// Public identifiers and endpoints of the Bose app's account sign-in (as used by pybose; not secret).
enum BoseAPI {
    static let clientID = "e284648d-3009-47eb-8e74-670c5330ae54"
    static let apiKey = "67616C617061676F732D70726F642D6D61647269642D696F73"

    // Azure AD B2C tenant behind "myBose ID"
    static let loginBase = "https://myboseid.bose.com"
    static let tenant = "boseprodb2c.onmicrosoft.com"
    static let policy = "B2C_1A_MBI_SUSI"
    static let redirectURI = "bosemusic://auth/callback"
    static let scope = "openid email profile offline_access \(clientID)"
    static let loginLocale = "de-de"

    static let authorizeURL = URL(string: "\(loginBase)/\(tenant)/oauth2/v2.0/authorize")!
    /// Code exchange during sign-in (policy as query parameter, like the Bose app).
    static let codeTokenURL = URL(string: "\(loginBase)/\(tenant)/oauth2/v2.0/token")!
    /// Refresh (policy in the path, like the Bose app).
    static let refreshTokenURL = URL(string: "\(loginBase)/\(tenant)/\(policy)/oauth2/v2.0/token")!
    /// Exchange of the Azure id_token for the Bose control token.
    static let boseTokenURL = URL(string: "https://id.api.bose.io/id-jwt-core/idps/aad/\(policy)/token")!

    static func loginStepURL(_ path: String) -> URL {
        URL(string: "\(loginBase)/\(tenant)/\(policy)/\(path)")!
    }

    /// Origin/Referer the token endpoint expects for the code exchange.
    static let webOrigin = "https://www.bose.de"
}
