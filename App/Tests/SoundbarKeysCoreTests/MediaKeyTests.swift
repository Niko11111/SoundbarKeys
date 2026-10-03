import Testing
@testable import SoundbarKeysCore

struct MediaKeyTests {
    /// data1 layout: key code << 16 | key state << 8 | repeat bit
    private func data1(code: Int, down: Bool, isRepeat: Bool = false) -> Int {
        (code << 16) | ((down ? 0x0A : 0x0B) << 8) | (isRepeat ? 1 : 0)
    }

    @Test func decodesVolumeUpDown() throws {
        let e = try #require(MediaKeyEvent(data1: data1(code: 0, down: true)))
        #expect(e.key == .volumeUp && e.isDown && !e.isRepeat && e.code == 0)
    }

    @Test func decodesKeyUpAndRepeat() throws {
        let up = try #require(MediaKeyEvent(data1: data1(code: 1, down: false)))
        #expect(up.key == .volumeDown && !up.isDown)
        let rep = try #require(MediaKeyEvent(data1: data1(code: 1, down: true, isRepeat: true)))
        #expect(rep.isRepeat)
    }

    @Test func decodesMute() {
        #expect(MediaKeyEvent(data1: data1(code: 7, down: true))?.key == .mute)
    }

    /// Brightness (2/3), play/pause (16) etc. must pass through untouched.
    @Test func ignoresOtherMediaKeys() {
        for code in [2, 3, 16, 17, 19, 20] {
            #expect(MediaKeyEvent(data1: data1(code: code, down: true)) == nil)
        }
    }
}
