import AppKit

/// Transparent window content that leaves room for the shadow of an `NSGlassEffectView`.
///
/// The glass draws a soft shadow outside its own bounds, mostly downwards. If the window ends
/// where the shadow is still visible, the window edge clips it into a faint rectangular edge.
/// So the window is larger than the glass (most of all at the bottom) and the glass sits inside.
enum GlassShadow {
    /// Room around the glass. 24 pt at the bottom was visibly too little (clipped shadow edge).
    static let insets = NSEdgeInsets(top: 24, left: 32, bottom: 72, right: 32)

    /// Container sized glass + insets; the glass resizes with it.
    static func container(for glass: NSGlassEffectView) -> NSView {
        let size = glass.frame.size
        let container = NSView(frame: NSRect(origin: .zero, size: windowSize(for: size)))
        glass.frame = NSRect(origin: NSPoint(x: insets.left, y: insets.bottom), size: size)
        glass.autoresizingMask = [.width, .height]
        container.addSubview(glass)
        return container
    }

    /// Window content size needed for glass of `size`.
    static func windowSize(for size: NSSize) -> NSSize {
        NSSize(width: size.width + insets.left + insets.right,
               height: size.height + insets.top + insets.bottom)
    }

    /// Window origin that places the *glass* (not the window) at `glassOrigin`.
    static func windowOrigin(forGlassAt glassOrigin: NSPoint) -> NSPoint {
        NSPoint(x: glassOrigin.x - insets.left, y: glassOrigin.y - insets.bottom)
    }
}
