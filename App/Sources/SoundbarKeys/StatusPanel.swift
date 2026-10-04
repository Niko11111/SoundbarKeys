import AppKit
import SoundbarKeysCore
import SwiftUI

/// Actions the SwiftUI views can trigger.
struct PanelActions {
    var setVolume: (Int) -> Void
    var toggleMute: () -> Void
    var setAudioMode: (String) -> Void
    var openSettings: () -> Void
    var openAccessibility: () -> Void
    var reconnect: () -> Void
    var searchSoundbars: () -> Void
    var refreshOutputDevices: () -> Void
    var reportCompatibility: () -> Void
    /// Opens the settings and Bose's sign-in page.
    var openSignIn: () -> Void
    var signOut: () -> Void
    var quit: () -> Void
}

/// Liquid Glass panel below the menu bar icon (like a Control Center module).
@MainActor
final class StatusPanelController {
    private let panel: KeyablePanel
    private let hosting: NSHostingView<PanelView>
    private var outsideClickMonitor: Any?
    /// Called when the panel should close by itself (click outside, Esc).
    var onRequestClose: (() -> Void)?

    var isVisible: Bool { panel.isVisible }

    private static let screenEdgeInset: CGFloat = 8
    private static let gapBelowMenuBar: CGFloat = 6

    init(model: AppModel, actions: PanelActions) {
        hosting = NSHostingView(rootView: PanelView(model: model, actions: actions))
        let size = hosting.fittingSize
        panel = KeyablePanel(contentRect: NSRect(origin: .zero, size: GlassShadow.windowSize(for: size)),
                             styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // No window shadow: it is rectangular and shows as dark corners around the rounded glass.
        // NSGlassEffectView draws its own edge and shadow (see GlassShadow).
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.onCancel = { [weak self] in self?.onRequestClose?() }

        let glass = NSGlassEffectView(frame: NSRect(origin: .zero, size: size))
        glass.cornerRadius = 24
        if #available(macOS 27.0, *) {
            // New in macOS 27: the glass visibly reacts to interaction with the contained controls.
            glass.effectIsInteractive = true
        }
        glass.contentView = hosting
        panel.contentView = GlassShadow.container(for: glass)
    }

    func show(below button: NSStatusBarButton) {
        guard let buttonWindow = button.window else { return }
        let size = hosting.fittingSize
        panel.setContentSize(GlassShadow.windowSize(for: size))
        let buttonFrame = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let screen = buttonWindow.screen ?? NSScreen.main
        var x = buttonFrame.midX - size.width / 2
        if let s = screen?.visibleFrame {
            x = min(max(x, s.minX + Self.screenEdgeInset), s.maxX - size.width - Self.screenEdgeInset)
        }
        let glassOrigin = NSPoint(x: x, y: buttonFrame.minY - size.height - Self.gapBelowMenuBar)
        panel.setFrameOrigin(GlassShadow.windowOrigin(forGlassAt: glassOrigin))
        panel.makeKeyAndOrderFront(nil)

        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) {
            [weak self] _ in
            MainActor.assumeIsolated { self?.onRequestClose?() }
        }
    }

    func hide() {
        if let m = outsideClickMonitor { NSEvent.removeMonitor(m) }
        outsideClickMonitor = nil
        panel.orderOut(nil)
    }
}

/// Panel that may become key (for Esc/slider) without activating the app.
/// Focus is given back immediately when it is ordered out.
private final class KeyablePanel: NSPanel {
    var onCancel: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { onCancel?() }
}

struct PanelView: View {
    @ObservedObject var model: AppModel
    let actions: PanelActions

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            PanelHeader(model: model)
            VolumeRow(model: model, actions: actions)
            if let mode = model.audioMode, mode.isSwitchable {
                SoundModeRow(mode: mode, setMode: actions.setAudioMode)
                    .disabled(!model.connected)
            }
            PanelNotices(model: model, actions: actions)
            Divider()
            HStack {
                Button("Settings …", action: actions.openSettings)
                if !model.connected {
                    Button("Reconnect", action: actions.reconnect)
                }
                Spacer()
                Button("Quit", action: actions.quit)
            }
            .buttonStyle(.glass)
            .controlSize(.small)
        }
        .padding(16)
        .frame(width: 320)
    }
}

/// Soundbar name and connection state.
private struct PanelHeader: View {
    @ObservedObject var model: AppModel

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "hifispeaker.fill")
                .font(.title2)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 1) {
                Group {
                    if let name = model.soundbarName { Text(verbatim: name) } else { Text("Soundbar") }
                }
                .font(.headline)
                Text(model.statusText).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}

/// Mute button, slider (0 … ceiling) and current value.
private struct VolumeRow: View {
    @ObservedObject var model: AppModel
    let actions: PanelActions

    var body: some View {
        HStack(spacing: 10) {
            Button(action: actions.toggleMute) {
                Image(systemName: model.muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.glass)
            .help(model.muted ? Text("Unmute") : Text("Mute"))

            Slider(value: volumeBinding, in: 0...Double(max(1, model.ceiling)), step: 1)
                .controlSize(.small)

            Text(model.muted ? "–" : "\(model.value)")
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 28, alignment: .trailing)
        }
        .disabled(!model.connected)
    }

    private var volumeBinding: Binding<Double> {
        Binding(
            get: { Double(min(model.value, model.ceiling)) },
            set: { actions.setVolume(Int($0.rounded())) }
        )
    }
}

/// Segmented switch for the soundbar's sound modes (only the ones the model supports).
private struct SoundModeRow: View {
    let mode: AudioModeState
    let setMode: (String) -> Void

    var body: some View {
        Picker("Sound", selection: Binding(get: { mode.value }, set: setMode)) {
            ForEach(mode.orderedModes, id: \.self) { value in
                Self.label(for: value).tag(value)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .help(Text("Dialogue mode makes voices clearer"))
    }

    /// Known modes get a translated name, unknown ones (other models) are shown as they come.
    private static func label(for value: String) -> Text {
        switch value {
        case "NORMAL": return Text("Normal")
        case "DIALOG": return Text("Dialogue")
        case "NIGHT": return Text("Night")
        default: return Text(verbatim: value.capitalized)
        }
    }
}

/// Warnings and things the user has to do (permissions, sign-in).
private struct PanelNotices: View {
    @ObservedObject var model: AppModel
    let actions: PanelActions

    var body: some View {
        if model.quietHoursActive {
            Label("Quiet hours: at most \(model.ceiling)", systemImage: "moon.fill")
                .font(.caption).foregroundStyle(.secondary)
        }
        if model.value > model.ceiling {
            Label("Currently above your maximum (\(model.ceiling))", systemImage: "exclamationmark.triangle")
                .font(.caption).foregroundStyle(.orange)
        }
        if !model.keysActive {
            Label("Keys inactive – output: \(model.outputName)", systemImage: "keyboard")
                .font(.caption).foregroundStyle(.secondary)
        }
        if !model.accessibilityTrusted {
            Button("Allow Accessibility access …", action: actions.openAccessibility)
                .buttonStyle(.glassProminent)
        }
        if let problem = model.loginProblem {
            VStack(alignment: .leading, spacing: 4) {
                Label("Sign-in required", systemImage: "person.crop.circle.badge.exclamationmark")
                    .font(.caption.bold()).foregroundStyle(.orange)
                Text(problem).font(.caption2).foregroundStyle(.secondary)
                Button("Sign in …", action: actions.openSignIn)
                    .buttonStyle(.glassProminent)
            }
        }
    }
}
