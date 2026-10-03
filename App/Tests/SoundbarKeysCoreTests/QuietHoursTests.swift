import Testing
@testable import SoundbarKeysCore

struct QuietHoursTests {
    private func minute(_ hour: Int, _ minute: Int = 0) -> Int { hour * 60 + minute }

    private let night = QuietHours(isEnabled: true, startMinute: 22 * 60, endMinute: 7 * 60, maxVolume: 20)

    @Test func windowAcrossMidnight() {
        #expect(!night.isActive(atMinute: minute(21, 59)))
        #expect(night.isActive(atMinute: minute(22)))
        #expect(night.isActive(atMinute: minute(23, 59)))
        #expect(night.isActive(atMinute: minute(0)))
        #expect(night.isActive(atMinute: minute(6, 59)))
        #expect(!night.isActive(atMinute: minute(7)))  // end is exclusive
        #expect(!night.isActive(atMinute: minute(12)))
    }

    @Test func windowWithinOneDay() {
        let afternoon = QuietHours(isEnabled: true, startMinute: minute(13), endMinute: minute(15), maxVolume: 10)
        #expect(!afternoon.isActive(atMinute: minute(12, 59)))
        #expect(afternoon.isActive(atMinute: minute(14)))
        #expect(!afternoon.isActive(atMinute: minute(15)))
    }

    @Test func disabledOrEmptyWindowIsNeverActive() {
        var off = night
        off.isEnabled = false
        #expect(!off.isActive(atMinute: minute(23)))
        let empty = QuietHours(isEnabled: true, startMinute: minute(8), endMinute: minute(8), maxVolume: 10)
        #expect(!empty.isActive(atMinute: minute(8)))
    }

    @Test func quietMaximumOnlyLowersNeverRaises() {
        #expect(night.userMax(normal: 40, atMinute: minute(23)) == 20)
        #expect(night.userMax(normal: 15, atMinute: minute(23)) == 15)
        #expect(night.userMax(normal: 40, atMinute: minute(12)) == 40)
    }
}
