import Testing
@testable import SoundbarKeysCore

struct APIErrorTextTests {
    /// Shape of a real error from a Soundbar 700 (token and GUID made up).
    @Test func dropsTheEchoedRequestWithToken() {
        let message = #"WEBSOCKET_API_NOT_REGISTERED "/x" - {"header":{"device":"abcd-1234","token":"eyJsecret"}}"#
        let safe = APIErrorText.sanitized(message)
        #expect(safe == #"WEBSOCKET_API_NOT_REGISTERED "/x""#)
        #expect(!safe.contains("eyJ") && !safe.contains("abcd-1234"))
    }

    @Test func keepsPlainMessagesAndLimitsLength() {
        #expect(APIErrorText.sanitized("Invalid value") == "Invalid value")
        #expect(APIErrorText.sanitized(String(repeating: "x", count: 500)).count == 200)
    }
}
