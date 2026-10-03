import Testing
@testable import SoundbarKeysCore

struct DeviceChoiceTests {
    private let found = ["kitchen", "livingroom", "office"]

    @Test func automaticTriesLastUsedFirst() {
        #expect(DeviceChoice.order(found: found, selected: nil, lastUsed: "livingroom")
                == ["livingroom", "kitchen", "office"])
    }

    @Test func automaticWithoutHistoryKeepsDiscoveryOrder() {
        #expect(DeviceChoice.order(found: found, selected: nil, lastUsed: nil) == found)
    }

    @Test func selectedDeviceIsTheOnlyCandidate() {
        #expect(DeviceChoice.order(found: found, selected: "office", lastUsed: "kitchen") == ["office"])
    }

    /// The selected soundbar is offline: do not fall back to another device.
    @Test func selectedButMissingGivesNothing() {
        #expect(DeviceChoice.order(found: found, selected: "garage", lastUsed: "kitchen").isEmpty)
    }
}
