import Testing
@testable import SoundbarKeysCore

struct VolumeLimitsTests {
    @Test func ceilingIsUserMaxButNeverAboveDeviceMax() {
        #expect(VolumeLimits(floor: 0, userMax: 40, deviceMax: 70).ceiling == 40)
        #expect(VolumeLimits(floor: 0, userMax: 90, deviceMax: 70).ceiling == 70)
    }

    @Test func ceilingNeverBelowFloor() {
        #expect(VolumeLimits(floor: 10, userMax: 5, deviceMax: 70).ceiling == 10)
    }

    @Test func keyPressMovesByDeltaWithinLimits() {
        let limits = VolumeLimits(floor: 0, userMax: 40, deviceMax: 70)
        #expect(limits.target(from: 20, delta: 4) == 24)
        #expect(limits.target(from: 20, delta: -4) == 16)
    }

    @Test func keyPressStopsAtCeilingAndFloor() {
        let limits = VolumeLimits(floor: 0, userMax: 40, deviceMax: 70)
        #expect(limits.target(from: 38, delta: 4) == 40)
        #expect(limits.target(from: 2, delta: -4) == 0)
    }

    /// The soft device minimum (10) must not stop quiet settings.
    @Test func softDeviceMinimumIsIgnored() {
        let limits = VolumeLimits(floor: 0, userMax: 40, deviceMax: 70)
        #expect(limits.target(from: 10, delta: -2) == 8)
    }

    /// Above the ceiling (turned up with the TV remote): "louder" does nothing,
    /// "quieter" brings it back into range.
    @Test func louderAboveCeilingDoesNothing() {
        let limits = VolumeLimits(floor: 0, userMax: 40, deviceMax: 70)
        #expect(limits.target(from: 50, delta: 4) == nil)
        #expect(limits.target(from: 40, delta: 4) == nil)
        #expect(limits.target(from: 50, delta: -4) == 40)
    }

    @Test func sliderValueIsClamped() {
        let limits = VolumeLimits(floor: 0, userMax: 40, deviceMax: 70)
        #expect(limits.clamp(55) == 40)
        #expect(limits.clamp(-3) == 0)
    }
}

struct VolumeStateTests {
    @Test func appliesAllFieldsOfAVolumeBody() {
        let body: [String: Any] = [
            "value": 23, "muted": true, "max": 70, "min": 10,
            "properties": ["minLimit": 0, "maxLimit": 100],
        ]
        let v = VolumeState().updated(with: body)
        #expect(v == VolumeState(value: 23, muted: true, floor: 0, max: 70))
    }

    @Test func missingFieldsKeepTheirValue() {
        let before = VolumeState(value: 23, muted: false, floor: 0, max: 70)
        #expect(before.updated(with: ["muted": true]) == VolumeState(value: 23, muted: true, floor: 0, max: 70))
    }

    @Test func wrongTypesAreIgnored() {
        let before = VolumeState(value: 23)
        #expect(before.updated(with: ["value": "loud"]).value == 23)
    }
}
