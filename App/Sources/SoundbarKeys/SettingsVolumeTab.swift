import AppKit
import SoundbarKeysCore
import SwiftUI

/// Tab "Volume": maximum, step size, quiet hours.
struct SettingsVolumeTab: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: Settings

    var body: some View {
        SettingsPage {
            VolumeSection(model: model, settings: settings)
            QuietHoursSection(settings: settings)
        }
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
