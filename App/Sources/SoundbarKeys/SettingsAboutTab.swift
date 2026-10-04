import AppKit
import SoundbarKeysCore
import SwiftUI

/// Tab "About": version, links, trademark note.
struct SettingsAboutTab: View {
    var body: some View {
        SettingsPage {
            AboutSection()
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
