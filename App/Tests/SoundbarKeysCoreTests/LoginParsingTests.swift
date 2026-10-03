import Foundation
import Testing
@testable import SoundbarKeysCore

struct LoginParsingTests {
    @Test func readsCodeFromRedirect() {
        #expect(LoginParsing.authorizationCode(fromRedirect: "bosemusic://auth/callback?code=abc123&state=x") == "abc123")
        #expect(LoginParsing.authorizationCode(fromRedirect: "bosemusic://auth/callback?error=access_denied") == nil)
    }

    @Test func readsErrorFromRedirect() {
        let failed = "bosemusic://auth/callback?error=access_denied&error_description=AADB2C90118%3A+forgot+password"
        #expect(LoginParsing.callbackError(fromRedirect: failed) == "AADB2C90118: forgot password")
        #expect(LoginParsing.callbackError(fromRedirect: "bosemusic://auth/callback?error=server_error") == "server_error")
        #expect(LoginParsing.callbackError(fromRedirect: "bosemusic://auth/callback?code=abc") == nil)
    }
}

struct PKCETests {
    /// RFC 7636, Appendix B test vector.
    @Test func matchesRFC7636TestVector() {
        let bytes: [UInt8] = [116, 24, 223, 180, 151, 153, 224, 37, 79, 250, 96, 125, 216, 173,
                              187, 186, 22, 212, 37, 77, 105, 214, 191, 240, 91, 88, 5, 88, 83,
                              132, 141, 121]
        let pkce = PKCE(randomBytes: bytes)
        #expect(pkce.verifier == "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
        #expect(pkce.challenge == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }
}
