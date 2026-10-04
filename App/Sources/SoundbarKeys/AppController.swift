import AppKit
import Combine
import SoundbarKeysCore

@MainActor
final class AppController: NSObject, NSApplicationDelegate {
    private let tokens = TokenStore()
    private lazy var client = SoundbarClient(tokens: tokens)
    private lazy var login = BoseLogin(tokens: tokens)
    /// The sign-in window opens by itself once per launch when there are no tokens.
    private var didOfferSignIn = false
    private let output = OutputWatcher()
    private let keyTap = KeyTap()
    private let hud = HUD()
    private let model = AppModel()
    private let settings = Settings.shared
    private lazy var quietHours = QuietHoursController(settings: settings)
    private var statusItem: NSStatusItem!
    private var panel: StatusPanelController!
    private var settingsWindow: SettingsWindowController!
    private var trustTimer: Timer?
    private var tokenTimer: Timer?
    private var cancellables: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        DiagLog.write("App started (\(Bundle.main.bundlePath))")
        settings.refreshLoginItemIfMoved()
        EditMenu.install()
        setUpWindows()
        setUpStatusItem()
        bindStateChanges()
        startKeyTapWhenTrusted()
        client.select(guid: settings.selectedSoundbarGUID) // connects
        quietHours.start()
        startTokenTimer()
        updateUI()
    }

    private func setUpWindows() {
        let actions = PanelActions(
            setVolume: { [weak self] in self?.client.setVolume($0) },
            toggleMute: { [weak self] in self?.client.toggleMute() },
            setAudioMode: { [weak self] in self?.client.setAudioMode($0) },
            openSettings: { [weak self] in self?.closePanel(); self?.settingsWindow.show() },
            openAccessibility: { [weak self] in self?.openAccessibility() },
            reconnect: { [weak self] in self?.client.connect() },
            searchSoundbars: { [weak self] in self?.searchSoundbars() },
            refreshOutputDevices: { [weak self] in self?.model.outputDevices = OutputWatcher.allOutputDevices() },
            reportCompatibility: { [weak self] in self?.reportCompatibility() },
            openSignIn: { [weak self] in self?.openSignIn() },
            signOut: { [weak self] in self?.signOut() },
            quit: { NSApp.terminate(nil) }
        )
        panel = StatusPanelController(model: model, actions: actions)
        panel.onRequestClose = { [weak self] in self?.closePanel() }
        settingsWindow = SettingsWindowController(model: model, actions: actions)
    }

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if #available(macOS 27.0, *) {
            // New in macOS 27: the system manages showing/hiding the panel
            // (including keyboard navigation in the menu bar).
            statusItem.expandedInterfaceDelegate = self
        } else {
            statusItem.button?.target = self
            statusItem.button?.action = #selector(togglePanel)
        }
    }

    private func bindStateChanges() {
        quietHours.onChange = { [weak self] in
            guard let self else { return }
            self.client.userMax = self.quietHours.userMax
            self.updateUI()
        }
        quietHours.lowerSoundbar = { [weak self] maximum in
            guard let self, self.output.isActive else { return false }
            return self.client.lowerVolume(to: maximum)
        }
        settings.$keysOutputUID
            .sink { [weak self] uid in self?.output.selectedUID = uid }
            .store(in: &cancellables)
        settings.$selectedSoundbarGUID
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] guid in self?.client.select(guid: guid) }
            .store(in: &cancellables)
        // objectWillChange fires before the new value is stored → evaluate on the next run loop pass.
        settings.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.quietHours.evaluate() }
            .store(in: &cancellables)

        client.onChange = { [weak self] in
            self?.updateUI()
            self?.quietHours.applyPendingLowering()
            self?.offerSignInIfNeeded()
        }
        output.onChange = { [weak self] in self?.updateUI(); self?.quietHours.applyPendingLowering() }
        keyTap.shouldHandle = { [weak self] in self?.shouldHandleKeys() ?? false }
        keyTap.handler = { [weak self] key, isRepeat in self?.handle(key: key, isRepeat: isRepeat) }
    }

    /// Refresh the token ahead of time regularly so it stays valid after long idle periods
    /// and the Azure refresh token keeps being used.
    private func startTokenTimer() {
        tokenTimer = Timer.scheduledTimer(withTimeInterval: Config.tokenCheckIntervalSeconds, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                Task { await self.checkToken() }
            }
        }
    }

    // MARK: - Account

    private func openSignIn() {
        closePanel()
        settingsWindow.show()
        guard !model.isSigningIn else { return }
        model.isSigningIn = true
        model.signInError = nil
        Task {
            await signIn()
            model.isSigningIn = false
        }
    }

    private func offerSignInIfNeeded() {
        guard !didOfferSignIn, case .needsLogin = client.state, !tokens.isSignedIn else { return }
        didOfferSignIn = true
        openSignIn()
    }

    private func signIn() async {
        do {
            guard try await login.signIn() else { return } // window closed
            client.connect()
        } catch {
            DiagLog.write("Sign-in failed: \(error.localizedDescription)")
            model.signInError = error.localizedDescription
        }
        updateUI()
    }

    private func signOut() {
        do {
            try tokens.signOut()
        } catch {
            DiagLog.write("Sign-out failed: \(error.localizedDescription)")
        }
        client.connect() // ends in "sign-in required"
        updateUI()
    }

    private func reportCompatibility() {
        model.reportError = nil
        Task {
            if await !CompatibilityReporter.report(client: client, output: output) {
                model.reportError = String(localized: "The soundbar did not answer. Is it connected?")
            }
        }
    }

    private func searchSoundbars() {
        guard !model.isSearching else { return }
        model.isSearching = true
        Task {
            model.availableSoundbars = await client.searchAll()
            model.isSearching = false
        }
    }

    private func checkToken() async {
        do {
            _ = try await tokens.validAccessToken()
        } catch {
            DiagLog.write("Scheduled token check failed: \(error.localizedDescription)")
        }
        updateUI()
    }

    // MARK: - Keys

    /// Called directly inside the event tap: only read state, nothing expensive.
    private func shouldHandleKeys() -> Bool {
        guard output.isActive else { return false }
        guard client.isReady else {
            if case .disconnected = client.state {
                DispatchQueue.main.async { [weak self] in
                    MainActor.assumeIsolated { self?.client.connect() }
                }
            }
            return false
        }
        return true
    }

    private func handle(key: KeyTap.Key, isRepeat: Bool) {
        switch key {
        case .volumeUp: client.adjust(by: settings.step)
        case .volumeDown: client.adjust(by: -settings.step)
        case .mute: if !isRepeat { client.toggleMute() }
        }
        showHUD()
    }

    private func showHUD() {
        guard let v = client.volume, let value = client.displayValue else { return }
        hud.show(value: value, ceiling: client.limits.ceiling, muted: v.muted, position: settings.hudPosition)
    }

    private func startKeyTapWhenTrusted() {
        if KeyTap.isTrusted {
            keyTap.start()
            updateUI()
            return
        }
        KeyTap.requestTrust()
        trustTimer?.invalidate()
        trustTimer = Timer.scheduledTimer(withTimeInterval: Config.accessibilityPollSeconds, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self, KeyTap.isTrusted else { return }
                timer.invalidate()
                self.keyTap.start()
                self.updateUI()
            }
        }
    }

    private func openAccessibility() {
        KeyTap.requestTrust()
        NSWorkspace.shared.open(URL(string:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    // MARK: - State → UI

    private func updateUI() {
        let v = client.volume
        model.connected = client.isReady
        model.value = client.displayValue ?? 0
        model.muted = v?.muted ?? false
        model.audioMode = client.audioMode
        model.deviceMax = v?.max ?? 100
        model.ceiling = client.limits.ceiling
        model.keysActive = output.isActive
        model.outputName = output.deviceName
        model.accessibilityTrusted = KeyTap.isTrusted
        model.tokenExpiry = tokens.accessTokenExpiry
        model.signedIn = tokens.isSignedIn
        model.quietHoursActive = quietHours.isActive
        model.soundbarName = client.soundbar?.name
        switch client.state {
        case .ready: model.statusText = String(localized: "connected"); model.loginProblem = nil
        case .searching: model.statusText = String(localized: "searching …")
        case .connecting: model.statusText = String(localized: "connecting …")
        case .disconnected(let why): model.statusText = String(localized: "not connected (\(why))")
        case .needsLogin(let why): model.statusText = String(localized: "sign-in required"); model.loginProblem = why
        }

        let symbol: String
        if !KeyTap.isTrusted || !client.isReady {
            symbol = "hifispeaker.badge.exclamationmark"
        } else if v?.muted == true {
            symbol = "speaker.slash"
        } else {
            symbol = "hifispeaker"
        }
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Soundbar")
            ?? NSImage(systemSymbolName: "hifispeaker", accessibilityDescription: "Soundbar")
        image?.isTemplate = true
        statusItem.button?.image = image
        statusItem.button?.appearsDisabled = !output.isActive
    }

    // MARK: - Panel

    @objc private func togglePanel() {
        guard let button = statusItem.button else { return }
        if panel.isVisible { panel.hide() } else { updateUI(); panel.show(below: button) }
    }

    private func closePanel() {
        if #available(macOS 27.0, *), let session = statusItem.expandedInterfaceSession {
            session.cancel() // → statusItemDidEndExpandedInterfaceSession → panel.hide()
        } else {
            panel.hide()
        }
    }
}

@available(macOS 27.0, *)
extension AppController: @preconcurrency NSStatusItemExpandedInterfaceDelegate {
    func statusItem(_ statusItem: NSStatusItem, didBegin session: NSStatusItemExpandedInterfaceSession) {
        guard let button = statusItem.button else { return }
        updateUI()
        panel.show(below: button)
    }

    func statusItemDidEndExpandedInterfaceSession(_ statusItem: NSStatusItem, animated: Bool) {
        panel.hide()
    }
}
