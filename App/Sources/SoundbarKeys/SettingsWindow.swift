import AppKit
import SoundbarKeysCore
import SwiftUI

@MainActor
final class SettingsWindowController {
    private var window: NSWindow?
    private let model: AppModel
    private let actions: PanelActions

    init(model: AppModel, actions: PanelActions) {
        self.model = model
        self.actions = actions
    }

    func show() {
        if window == nil {
            let host = NSHostingController(rootView: SettingsView(model: model, settings: .shared, actions: actions))
            let w = NSWindow(contentViewController: host)
            w.title = "SoundbarKeys"
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: Settings
    let actions: PanelActions

    var body: some View {
        Form {
            AccountSection(model: model, actions: actions)
            SoundbarSection(model: model, settings: settings, search: actions.searchSoundbars)
            VolumeSection(model: model, settings: settings)
            QuietHoursSection(settings: settings)
            Section("General") {
                Picker("Volume indicator", selection: $settings.hudPosition) {
                    Text("Top right").tag(HUDPosition.topRight)
                    Text("Bottom center").tag(HUDPosition.bottomCenter)
                    Text("Off").tag(HUDPosition.off)
                }
                Toggle("Launch at login", isOn: Binding(
                    get: { settings.launchAtLogin },
                    set: { settings.launchAtLogin = $0 }
                ))
            }
            StatusSection(model: model, actions: actions)
            AboutSection()
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct VolumeSection: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: Settings

    var body: some View {
        Section {
            LabeledContent("Maximum volume") {
                HStack {
                    Slider(value: maxBinding, in: range, step: 1)
                        .frame(width: 180)
                    Text(verbatim: "\(settings.maxVolume)")
                        .font(.body.monospacedDigit())
                        .frame(width: 30, alignment: .trailing)
                }
            }
            Picker("Step per key press", selection: $settings.step) {
                ForEach(Config.stepChoices, id: \.self) { Text(verbatim: "\($0)").tag($0) }
            }
        } header: {
            Text("Volume")
        } footer: {
            Text("Keys and slider never go above this maximum. The soundbar itself allows at most \(model.deviceMax). If it is turned up another way (e.g. with the TV remote), the limit does not apply.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    /// From `Config.minimumMaxVolume` up to the soundbar's own limit.
    private var range: ClosedRange<Double> {
        Double(Config.minimumMaxVolume)...Double(max(Config.minimumMaxVolume + 1, model.deviceMax))
    }

    private var maxBinding: Binding<Double> {
        Binding(get: { Double(settings.maxVolume) }, set: { settings.maxVolume = Int($0.rounded()) })
    }
}

/// Choose the soundbar when there are several Bose devices on the network.
private struct SoundbarSection: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: Settings
    let search: () -> Void

    var body: some View {
        Section {
            Picker("Soundbar", selection: $settings.selectedSoundbarGUID) {
                Text("Automatic").tag(String?.none)
                ForEach(model.availableSoundbars) { bar in
                    Text(verbatim: Self.title(of: bar)).tag(String?.some(bar.guid))
                }
                if let selected = settings.selectedSoundbarGUID,
                   !model.availableSoundbars.contains(where: { $0.guid == selected }) {
                    Text("Selected soundbar (not found)").tag(String?.some(selected))
                }
            }
            HStack {
                Button("Search again", action: search)
                    .disabled(model.isSearching)
                if model.isSearching { ProgressView().controlSize(.small) }
            }
        } footer: {
            Text("Automatic uses the soundbar found first. With a fixed choice, SoundbarKeys never switches to another device.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .onAppear { if model.availableSoundbars.isEmpty { search() } }
    }

    private static func title(of bar: Soundbar) -> String {
        guard let model = bar.model, model != bar.name else { return bar.name }
        return "\(bar.name) – \(model)"
    }
}

private struct QuietHoursSection: View {
    @ObservedObject var settings: Settings

    var body: some View {
        Section {
            Toggle("Quiet hours", isOn: $settings.quietEnabled)
            if settings.quietEnabled {
                DatePicker("From", selection: timeBinding(\.quietStartMinute), displayedComponents: .hourAndMinute)
                DatePicker("Until", selection: timeBinding(\.quietEndMinute), displayedComponents: .hourAndMinute)
                LabeledContent("Maximum volume") {
                    HStack {
                        Slider(value: maxBinding, in: 1...Double(max(2, settings.maxVolume)), step: 1)
                            .frame(width: 180)
                        Text(verbatim: "\(settings.quietMaxVolume)")
                            .font(.body.monospacedDigit())
                            .frame(width: 30, alignment: .trailing)
                    }
                }
            }
        } header: {
            Text("Quiet hours")
        } footer: {
            Text("During quiet hours this lower maximum applies. When they begin, a louder soundbar is turned down automatically (only while the Mac outputs via HDMI).")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    /// Minutes since midnight <-> a Date today, for the time pickers.
    private func timeBinding(_ keyPath: ReferenceWritableKeyPath<Settings, Int>) -> Binding<Date> {
        let midnight = Calendar.current.startOfDay(for: Date())
        return Binding(
            get: { midnight.addingTimeInterval(TimeInterval(settings[keyPath: keyPath] * 60)) },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                settings[keyPath: keyPath] = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            }
        )
    }

    private var maxBinding: Binding<Double> {
        Binding(get: { Double(settings.quietMaxVolume) }, set: { settings.quietMaxVolume = Int($0.rounded()) })
    }
}

private struct StatusSection: View {
    @ObservedObject var model: AppModel
    let actions: PanelActions

    var body: some View {
        Section("Status") {
            LabeledContent("Connection", value: model.statusText)
            LabeledContent("Keys") {
                // Two Text values (not a String ternary) so both variants get localized.
                model.keysActive ? Text("active (\(model.outputName))") : Text("inactive (\(model.outputName))")
            }
            if let exp = model.tokenExpiry {
                LabeledContent("Token valid until") {
                    Text(exp, format: .dateTime.day().month().hour().minute())
                }
            }
            HStack {
                Button("Reconnect", action: actions.reconnect)
                Button("Open diagnostic log") {
                    if !FileManager.default.fileExists(atPath: DiagLog.url.path) { DiagLog.write("Log created") }
                    NSWorkspace.shared.open(DiagLog.url)
                }
            }
        }
    }
}

private struct AboutSection: View {
    var body: some View {
        Section {
            LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–")
            HStack {
                Link(destination: Config.githubURL) {
                    Label("GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                }
                Link(destination: Config.kofiURL) {
                    Label("Support on Ko-fi", systemImage: "cup.and.saucer.fill")
                }
            }
        } header: {
            Text("About")
        } footer: {
            Text("SoundbarKeys is not affiliated with or endorsed by Bose Corporation. Bose is a trademark of Bose Corporation.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
