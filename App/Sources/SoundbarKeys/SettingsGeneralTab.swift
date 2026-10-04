import AppKit
import SoundbarKeysCore
import SwiftUI

/// Tab "General": indicator, volume keys, launch at login.
struct SettingsGeneralTab: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: Settings
    let actions: PanelActions

    var body: some View {
        SettingsPage {
            Section {
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
            KeysSection(model: model, settings: settings, refresh: actions.refreshOutputDevices)
        }
    }
}

/// Which output device makes the volume keys control the soundbar.
private struct KeysSection: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: Settings
    let refresh: () -> Void

    var body: some View {
        Section {
            Picker("Active with output", selection: $settings.keysOutputUID) {
                Text("Any HDMI device").tag(String?.none)
                ForEach(model.outputDevices) { device in
                    Text(verbatim: device.name).tag(String?.some(device.uid))
                }
                if let selected = settings.keysOutputUID,
                   !model.outputDevices.contains(where: { $0.uid == selected }) {
                    Text("Selected device (not connected)").tag(String?.some(selected))
                }
            }
        } header: {
            Text("Volume keys")
        } footer: {
            Text("With any other output the keys control the Mac as usual. Choose your TV here if you also use an HDMI monitor with speakers.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .onAppear(perform: refresh)
    }
}
