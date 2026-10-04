import AppKit
import ServiceManagement
import SoundbarKeysCore

/// User settings (UserDefaults).
@MainActor
final class Settings: ObservableObject {
    static let shared = Settings()

    /// Highest volume the keys and the slider may set.
    @Published var maxVolume: Int {
        didSet { UserDefaults.standard.set(maxVolume, forKey: "maxVolume") }
    }

    @Published var step: Int {
        didSet { UserDefaults.standard.set(step, forKey: "step") }
    }

    @Published var hudPosition: HUDPosition {
        didSet { UserDefaults.standard.set(hudPosition.rawValue, forKey: "hudPosition") }
    }

    /// GUID of the soundbar chosen in the settings; nil = automatic.
    @Published var selectedSoundbarGUID: String? {
        didSet { UserDefaults.standard.set(selectedSoundbarGUID, forKey: "selectedSoundbar") }
    }

    /// UID of the output device that activates the volume keys; nil = any HDMI device.
    @Published var keysOutputUID: String? {
        didSet { UserDefaults.standard.set(keysOutputUID, forKey: "keysOutputUID") }
    }

    @Published var quietEnabled: Bool { didSet { UserDefaults.standard.set(quietEnabled, forKey: "quietEnabled") } }
    /// Minutes since midnight.
    @Published var quietStartMinute: Int { didSet { UserDefaults.standard.set(quietStartMinute, forKey: "quietStart") } }
    @Published var quietEndMinute: Int { didSet { UserDefaults.standard.set(quietEndMinute, forKey: "quietEnd") } }
    @Published var quietMaxVolume: Int { didSet { UserDefaults.standard.set(quietMaxVolume, forKey: "quietMax") } }

    var quietHours: QuietHours {
        QuietHours(isEnabled: quietEnabled, startMinute: quietStartMinute,
                   endMinute: quietEndMinute, maxVolume: quietMaxVolume)
    }

    private init() {
        let d = UserDefaults.standard
        let m = d.integer(forKey: "maxVolume")
        maxVolume = m > 0 ? m : Config.defaultMaxVolume
        let s = d.integer(forKey: "step")
        step = Config.stepChoices.contains(s) ? s : Config.defaultStep
        hudPosition = d.string(forKey: "hudPosition").flatMap(HUDPosition.init(rawValue:)) ?? .topRight
        selectedSoundbarGUID = d.string(forKey: "selectedSoundbar")
        keysOutputUID = d.string(forKey: "keysOutputUID")
        quietEnabled = d.bool(forKey: "quietEnabled")
        quietStartMinute = d.object(forKey: "quietStart") as? Int ?? Config.defaultQuietStartMinute
        quietEndMinute = d.object(forKey: "quietEnd") as? Int ?? Config.defaultQuietEndMinute
        quietMaxVolume = d.object(forKey: "quietMax") as? Int ?? Config.defaultQuietMaxVolume
    }

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            objectWillChange.send()
            do {
                if newValue {
                    try SMAppService.mainApp.register()
                    UserDefaults.standard.set(Bundle.main.bundlePath, forKey: "loginItemPath")
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                DiagLog.write("Changing the login item failed: \(error.localizedDescription)")
                let alert = NSAlert()
                alert.messageText = String(localized: "Changing “Launch at login” failed")
                alert.informativeText = error.localizedDescription
                alert.runModal()
            }
        }
    }

    /// If the app was moved (e.g. from ~/Applications to /Applications), an existing login item
    /// still points to the old location → register it once more.
    func refreshLoginItemIfMoved() {
        guard SMAppService.mainApp.status == .enabled else { return }
        let current = Bundle.main.bundlePath
        guard UserDefaults.standard.string(forKey: "loginItemPath") != current else { return }
        do {
            try SMAppService.mainApp.unregister()
            try SMAppService.mainApp.register()
            UserDefaults.standard.set(current, forKey: "loginItemPath")
            DiagLog.write("Login item updated to \(current)")
        } catch {
            DiagLog.write("Updating the login item failed: \(error.localizedDescription)")
        }
    }
}

/// State for the SwiftUI views (panel, settings), fed by the AppController.
@MainActor
final class AppModel: ObservableObject {
    @Published var connected = false
    @Published var statusText = ""
    @Published var soundbarName: String?
    @Published var value = 0
    @Published var muted = false
    @Published var audioMode: AudioModeState?
    /// The soundbar's own upper limit (`max` from /audio/volume).
    @Published var deviceMax = 100
    /// Effective upper limit for keys and slider (computed by `VolumeLimits` in the client).
    @Published var ceiling = Config.defaultMaxVolume
    @Published var keysActive = false
    @Published var outputName = "?"
    @Published var loginProblem: String?
    @Published var tokenExpiry: Date?
    @Published var accessibilityTrusted = true
    @Published var quietHoursActive = false
    /// Result of the last search for the soundbar selection.
    @Published var availableSoundbars: [Soundbar] = []
    @Published var isSearching = false
    /// Output devices for the key activation picker (refreshed when the settings open).
    @Published var outputDevices: [OutputDevice] = []
    @Published var signedIn = false
    @Published var isSigningIn = false
    /// Message of the last failed sign-in, shown in the account section.
    @Published var signInError: String?
}
