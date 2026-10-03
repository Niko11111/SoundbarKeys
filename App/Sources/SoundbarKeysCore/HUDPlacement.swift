import CoreGraphics

/// Where the volume indicator appears (pure logic, no AppKit).
public enum HUDPosition: String, CaseIterable, Sendable {
    /// Below the menu bar at the right, like the macOS 26 indicator.
    case topRight
    /// Centered near the bottom, like the classic macOS indicator.
    case bottomCenter
    /// No indicator.
    case off

    /// Distance from the screen edges (points).
    static let topRightEdgeInset: CGFloat = 12
    static let topRightGapBelowMenuBar: CGFloat = 8
    static let bottomCenterGapAboveDock: CGFloat = 100

    /// Origin (bottom-left, AppKit coordinates) of an indicator of `size` on a screen whose usable
    /// area (without menu bar and Dock) is `visibleFrame`. Nil for `.off`.
    public func origin(for size: CGSize, in visibleFrame: CGRect) -> CGPoint? {
        switch self {
        case .topRight:
            return CGPoint(x: visibleFrame.maxX - size.width - Self.topRightEdgeInset,
                           y: visibleFrame.maxY - size.height - Self.topRightGapBelowMenuBar)
        case .bottomCenter:
            return CGPoint(x: visibleFrame.midX - size.width / 2,
                           y: visibleFrame.minY + Self.bottomCenterGapAboveDock)
        case .off:
            return nil
        }
    }
}
