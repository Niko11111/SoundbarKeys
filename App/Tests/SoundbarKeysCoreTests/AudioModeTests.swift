import Testing
@testable import SoundbarKeysCore

struct AudioModeTests {
    /// Body as returned by a Soundbar 700.
    private let soundbar700: [String: Any] = [
        "persistence": "CONTENT_ITEM",
        "properties": ["supportedPersistence": ["SESSION", "GLOBAL", "CONTENT_ITEM"],
                       "supportedValues": ["DIALOG", "NORMAL"]],
        "value": "NORMAL",
    ]

    @Test func parsesSoundbar700Body() {
        let mode = AudioModeState(value: "", supported: []).updated(with: soundbar700)
        #expect(mode == AudioModeState(value: "NORMAL", supported: ["DIALOG", "NORMAL"]))
        #expect(mode.isSwitchable)
    }

    @Test func normalComesFirst() {
        let mode = AudioModeState(value: "NORMAL", supported: ["DIALOG", "NIGHT", "NORMAL"])
        #expect(mode.orderedModes == ["NORMAL", "DIALOG", "NIGHT"])
    }

    /// A notification may only carry the new value.
    @Test func notificationWithOnlyAValueKeepsSupportedModes() {
        let before = AudioModeState(value: "NORMAL", supported: ["DIALOG", "NORMAL"])
        #expect(before.updated(with: ["value": "DIALOG"]).supported == ["DIALOG", "NORMAL"])
        #expect(before.updated(with: ["value": "DIALOG"]).value == "DIALOG")
    }

    @Test func singleModeIsNotSwitchable() {
        #expect(!AudioModeState(value: "NORMAL", supported: ["NORMAL"]).isSwitchable)
    }
}
