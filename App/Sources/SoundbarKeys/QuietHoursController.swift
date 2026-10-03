import Foundation
import SoundbarKeysCore

/// Applies the quiet hours: provides the current maximum and lowers the soundbar once
/// when quiet hours begin (rules in `QuietHours`).
@MainActor
final class QuietHoursController {
    private let settings: Settings
    private var timer: Timer?
    private var wasActive = false
    /// Set when quiet hours begin; cleared once the soundbar was checked (it may not be reachable
    /// at that moment, or the Mac may not be using HDMI yet) or when quiet hours end.
    private var lowerPending = false

    /// The effective maximum may have changed (start/end of quiet hours, settings).
    var onChange: (() -> Void)?
    /// Lowers the soundbar to the given value if it is louder. Returns false if that is not
    /// possible right now (not connected, output not HDMI); it is retried later.
    var lowerSoundbar: ((Int) -> Bool)?

    init(settings: Settings) {
        self.settings = settings
    }

    var isActive: Bool { settings.quietHours.isActive(atMinute: Self.currentMinute()) }

    /// Maximum for keys and slider right now.
    var userMax: Int {
        settings.quietHours.userMax(normal: settings.maxVolume, atMinute: Self.currentMinute())
    }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: Config.quietHoursCheckSeconds, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.evaluate() }
        }
        evaluate()
    }

    /// Re-evaluates the window. Starting the app during quiet hours counts as their beginning.
    func evaluate() {
        let active = isActive
        if active && !wasActive {
            DiagLog.write("Quiet hours began (max \(settings.quietMaxVolume))")
            lowerPending = true
        }
        if !active { lowerPending = false }
        wasActive = active
        onChange?()
        applyPendingLowering()
    }

    /// Call when the connection or the output changed: a pending lowering may be possible now.
    func applyPendingLowering() {
        guard lowerPending, lowerSoundbar?(settings.quietMaxVolume) == true else { return }
        lowerPending = false
    }

    private static func currentMinute() -> Int {
        let now = Calendar.current.dateComponents([.hour, .minute], from: Date())
        return (now.hour ?? 0) * 60 + (now.minute ?? 0)
    }
}
