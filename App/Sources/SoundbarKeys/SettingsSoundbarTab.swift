import AppKit
import SoundbarKeysCore
import SwiftUI

/// Tab "Soundbar": device selection, connection status, diagnostics.
struct SettingsSoundbarTab: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: Settings
    let actions: PanelActions

    var body: some View {
        SettingsPage {
            SoundbarSection(model: model, settings: settings, search: actions.searchSoundbars)
            StatusSection(model: model, actions: actions)
        }
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
            HStack {
                Button("Reconnect", action: actions.reconnect)
                Button("Open diagnostic log") {
                    if !FileManager.default.fileExists(atPath: DiagLog.url.path) { DiagLog.write("Log created") }
                    NSWorkspace.shared.open(DiagLog.url)
                }
            }
            Button("Report compatibility …", action: actions.reportCompatibility)
                .disabled(!model.connected)
                .help(Text("Opens a GitHub issue with technical details of your soundbar: model, firmware and supported functions. No names or serial numbers."))
            if let error = model.reportError {
                Text(error).font(.callout).foregroundStyle(.red)
            }
        }
    }
}
