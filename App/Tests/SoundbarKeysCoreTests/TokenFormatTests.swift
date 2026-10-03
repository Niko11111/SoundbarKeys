import Foundation
import Testing
@testable import SoundbarKeysCore

struct TokenFormatTests {
    private func jwt(payload: String) -> String {
        let b64 = Data(payload.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return "eyJhbGciOiJub25lIn0.\(b64).signature"
    }

    @Test func readsExpiryFromJWT() {
        let date = TokenFormat.expiry(ofJWT: jwt(payload: #"{"exp":1790000000,"sub":"x"}"#))
        #expect(date == Date(timeIntervalSince1970: 1_790_000_000))
    }

    @Test func invalidTokensHaveNoExpiry() {
        #expect(TokenFormat.expiry(ofJWT: "not-a-jwt") == nil)
        #expect(TokenFormat.expiry(ofJWT: jwt(payload: #"{"sub":"x"}"#)) == nil)
        #expect(TokenFormat.expiry(ofJWT: "a.%%%.c") == nil)
    }

    @Test func chunksRoundTrip() {
        let text = String(repeating: "abcdefghij", count: 701) // 7010 characters
        let parts = TokenFormat.chunks(of: text, size: 3000)
        #expect(parts.map(\.count) == [3000, 3000, 1010])
        #expect(parts.joined() == text)
    }

    @Test func emptyTextHasNoChunks() {
        #expect(TokenFormat.chunks(of: "", size: 3000).isEmpty)
    }
}

struct VolumeSymbolTests {
    @Test func symbolFollowsLevelRelativeToCeiling() {
        #expect(VolumeSymbol.name(value: 0, ceiling: 40, muted: false) == "speaker.fill")
        #expect(VolumeSymbol.name(value: 10, ceiling: 40, muted: false) == "speaker.wave.1.fill")
        #expect(VolumeSymbol.name(value: 20, ceiling: 40, muted: false) == "speaker.wave.2.fill")
        #expect(VolumeSymbol.name(value: 40, ceiling: 40, muted: false) == "speaker.wave.3.fill")
    }

    @Test func mutedWins() {
        #expect(VolumeSymbol.name(value: 40, ceiling: 40, muted: true) == "speaker.slash.fill")
    }

    @Test func fractionIsBoundedAndSafeForZeroCeiling() {
        #expect(VolumeSymbol.fractionOf(value: 50, ceiling: 40) == 1)
        #expect(VolumeSymbol.fractionOf(value: 5, ceiling: 0) == 0)
    }
}
