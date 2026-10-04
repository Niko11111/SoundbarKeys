import Testing
@testable import SoundbarKeysCore

struct KeyActivationTests {
    @Test func automaticMeansAnyHDMIDevice() {
        #expect(KeyActivation.isActive(currentUID: "tv", currentIsHDMI: true, selectedUID: nil))
        #expect(!KeyActivation.isActive(currentUID: "speakers", currentIsHDMI: false, selectedUID: nil))
    }

    /// An HDMI monitor with speakers must not control the soundbar once the TV is selected.
    @Test func selectedDeviceOnly() {
        #expect(KeyActivation.isActive(currentUID: "tv", currentIsHDMI: true, selectedUID: "tv"))
        #expect(!KeyActivation.isActive(currentUID: "monitor", currentIsHDMI: true, selectedUID: "tv"))
    }

    /// A non-HDMI device (e.g. optical output to the soundbar) can be selected too.
    @Test func selectedNonHDMIDevice() {
        #expect(KeyActivation.isActive(currentUID: "optical", currentIsHDMI: false, selectedUID: "optical"))
    }

    @Test func unknownCurrentDeviceIsInactiveWhenOneIsSelected() {
        #expect(!KeyActivation.isActive(currentUID: nil, currentIsHDMI: true, selectedUID: "tv"))
    }
}
