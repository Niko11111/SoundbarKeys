import AppKit
import SoundbarKeysCore

/// Volume overlay in the style of the macOS 26 indicator: a Liquid Glass capsule at the top right below
/// the menu bar, or centered at the bottom (setting). (Apple's own indicator can no longer be triggered by other apps since macOS 26 –
/// OSDUIHelper is no longer used by the system.)
@MainActor
final class HUD {
    private let panel: NSPanel
    private let icon = NSImageView()
    private let title = NSTextField(labelWithString: String(localized: "Soundbar"))
    private let number = NSTextField(labelWithString: "")
    private let bar = LevelBar()
    private var hideWork: DispatchWorkItem?

    private static let size = NSSize(width: 320, height: 56)

    init() {
        let size = Self.size
        panel = HUDPanel(contentRect: NSRect(origin: .zero, size: GlassShadow.windowSize(for: size)),
                         styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.overlayWindow)))
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false // the glass brings its own edge/shadow
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]

        let glass = NSGlassEffectView(frame: NSRect(origin: .zero, size: size))
        glass.cornerRadius = size.height / 2
        glass.style = .regular

        let content = NSView(frame: glass.bounds)
        glass.contentView = content
        panel.contentView = GlassShadow.container(for: glass)

        icon.symbolConfiguration = .init(pointSize: 17, weight: .semibold)
        icon.contentTintColor = .labelColor
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        number.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        number.alignment = .right
        number.textColor = .secondaryLabelColor

        for v in [icon, title, number, bar] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(v)
        }
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 18),
            icon.centerYAnchor.constraint(equalTo: content.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 24),
            title.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 10),
            title.centerYAnchor.constraint(equalTo: content.centerYAnchor),
            bar.leadingAnchor.constraint(equalTo: title.trailingAnchor, constant: 12),
            bar.centerYAnchor.constraint(equalTo: content.centerYAnchor),
            bar.heightAnchor.constraint(equalToConstant: 6),
            number.leadingAnchor.constraint(equalTo: bar.trailingAnchor, constant: 10),
            number.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            number.centerYAnchor.constraint(equalTo: content.centerYAnchor),
            number.widthAnchor.constraint(equalToConstant: 40),
        ])
    }

    /// Shows the level at `position`; the bar shows `value` as a fraction of the effective `ceiling`.
    func show(value: Int, ceiling: Int, muted: Bool, position: HUDPosition) {
        guard let screen = NSScreen.main,
              let glassOrigin = position.origin(for: Self.size, in: screen.visibleFrame) else { return }
        let symbol = VolumeSymbol.name(value: value, ceiling: ceiling, muted: muted)
        icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        number.stringValue = muted ? String(localized: "muted") : "\(value)"
        bar.fraction = muted ? 0 : VolumeSymbol.fractionOf(value: value, ceiling: ceiling)

        panel.setFrameOrigin(GlassShadow.windowOrigin(forGlassAt: glassOrigin))
        hideWork?.cancel()
        if !panel.isVisible || panel.alphaValue < 1 {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.15
                panel.animator().alphaValue = 1
            }
        }

        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                NSAnimationContext.runAnimationGroup({ ctx in
                    ctx.duration = 0.35
                    self.panel.animator().alphaValue = 0
                }, completionHandler: {
                    MainActor.assumeIsolated {
                        if self.panel.alphaValue == 0 { self.panel.orderOut(nil) }
                    }
                })
            }
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Config.hudVisibleSeconds, execute: work)
    }
}

/// Display-only window: must never receive keyboard focus.
private final class HUDPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class LevelBar: NSView {
    var fraction: Double = 0 { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        let r = bounds.height / 2
        NSColor.labelColor.withAlphaComponent(0.15).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: r, yRadius: r).fill()
        var filled = bounds
        filled.size.width = Swift.max(bounds.height, bounds.width * CGFloat(Swift.min(1, Swift.max(0, fraction))))
        if fraction <= 0 { return }
        NSColor.labelColor.setFill()
        NSBezierPath(roundedRect: filled, xRadius: r, yRadius: r).fill()
    }
}
