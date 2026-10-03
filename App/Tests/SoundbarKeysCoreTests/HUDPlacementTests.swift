import CoreGraphics
import Testing
@testable import SoundbarKeysCore

struct HUDPlacementTests {
    /// 1440 x 900 screen, menu bar 30 pt at the top, Dock 70 pt at the bottom.
    private let visible = CGRect(x: 0, y: 70, width: 1440, height: 800)
    private let size = CGSize(width: 320, height: 56)

    @Test func topRightSitsBelowTheMenuBarAtTheRightEdge() {
        let origin = HUDPosition.topRight.origin(for: size, in: visible)
        #expect(origin == CGPoint(x: 1440 - 320 - 12, y: 870 - 56 - 8))
    }

    @Test func bottomCenterIsCenteredAboveTheDock() {
        let origin = HUDPosition.bottomCenter.origin(for: size, in: visible)
        #expect(origin == CGPoint(x: 720 - 160, y: 70 + 100))
    }

    /// Secondary screen left of the main screen has negative x coordinates.
    @Test func worksOnScreensWithNegativeCoordinates() {
        let left = CGRect(x: -1920, y: 0, width: 1920, height: 1050)
        let expectedX: CGFloat = -1920 + 1920 / 2 - 320 / 2  // screen center minus half the indicator
        #expect(HUDPosition.bottomCenter.origin(for: size, in: left)?.x == expectedX)
    }

    @Test func offHasNoOrigin() {
        #expect(HUDPosition.off.origin(for: size, in: visible) == nil)
    }

    /// The stored setting must survive renames of the Swift cases.
    @Test func rawValuesAreStable() {
        #expect(HUDPosition.allCases.map(\.rawValue) == ["topRight", "bottomCenter", "off"])
    }
}
