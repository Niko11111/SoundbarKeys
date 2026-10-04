import AppKit
import Foundation
import SoundbarKeysCore

/// Persistent WebSocket connection to the soundbar (local, unofficial Bose API, subprotocol "eco2").
///
/// Per connection the soundbar sends VersionInfo, /connectionReady and FrontDoorReady.
/// Requests are only processed after FrontDoorReady (PUTs sent earlier are acknowledged but ignored).
/// After that: subscribe to /audio/volume (push on changes, e.g. via the TV remote) + GET /audio/volume.
@MainActor
final class SoundbarClient: NSObject {
    enum State: Equatable {
        case disconnected(String)
        case searching
        case connecting
        case ready
        case needsLogin(String)
    }

    private(set) var state: State = .disconnected(String(localized: "not connected yet")) { didSet { onChange?() } }
    private(set) var volume: VolumeState? { didSet { onChange?() } }
    /// Sound mode (e.g. NORMAL/DIALOG); nil if the soundbar has none.
    private(set) var audioMode: AudioModeState? { didSet { onChange?() } }
    private(set) var soundbar: Soundbar?
    var onChange: (() -> Void)?

    private let tokens: TokenStore
    private let discovery = SoundbarDiscovery()
    private var session: URLSession!
    private var task: URLSessionWebSocketTask?
    private var connectionID = 0
    private var reqID = 0
    private var reconnectDelay: TimeInterval = 1
    private var reconnectWork: DispatchWorkItem?
    private var pingTimer: Timer?
    /// Set after a failed connection: the next attempt rediscovers instead of using the cache.
    private var needsDiscovery = false
    /// Soundbar chosen in the settings (GUID); nil = automatic.
    private(set) var selectedGUID: String?
    /// Host the TLS delegate accepts the self-signed certificate for.
    private let trustedHost = LockedValue<String?>(nil)

    /// Target value for fast key sequences: at most one PUT is in flight,
    /// further key presses only move the target.
    private(set) var pendingTarget: Int?
    private var putInFlight = false
    /// Callbacks for one-off queries, by request id (see `query`).
    private var responseHandlers: [Int: ([String: Any]?) -> Void] = [:]

    init(tokens: TokenStore) {
        self.tokens = tokens
        super.init()
        session = URLSession(configuration: .default, delegate: self, delegateQueue: .main)
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reconnect(after: Config.wakeReconnectDelaySeconds) }
        }
    }

    var isReady: Bool { state == .ready && volume != nil }

    /// Value to display: the target during key sequences, otherwise the confirmed value.
    var displayValue: Int? { pendingTarget ?? volume?.value }

    // MARK: - Connection

    func connect() {
        reconnectWork?.cancel()
        disconnectSocket()
        connectionID += 1
        let id = connectionID
        Task {
            do {
                _ = try await tokens.validAccessToken()
            } catch {
                guard id == connectionID else { return }
                state = .needsLogin(error.localizedDescription)
                reconnect(after: Config.loginRetryDelaySeconds) // e.g. the internet was down
                return
            }
            guard id == connectionID else { return }

            var bar = needsDiscovery ? nil : (soundbar ?? discovery.cached)
            if let selectedGUID, bar?.guid != selectedGUID { bar = nil }
            if bar == nil {
                state = .searching
                bar = await discovery.find(selected: selectedGUID)
                guard id == connectionID else { return }
            }
            guard let bar else {
                connectionLost(String(localized: "soundbar not found on the network"), id: id)
                return
            }
            soundbar = bar
            needsDiscovery = false
            state = .connecting
            trustedHost.value = bar.host
            let url = URL(string: "wss://\(bar.host):\(Config.apiPort)/?\(Config.productQuery)")!
            let t = session.webSocketTask(with: url, protocols: ["eco2"])
            task = t
            t.resume()
            receive(on: t, id: id)
        }
    }

    /// Switches to another soundbar (nil = automatic) and reconnects.
    func select(guid: String?) {
        guard guid != selectedGUID || soundbar == nil else { return }
        selectedGUID = guid
        soundbar = nil
        volume = nil
        audioMode = nil
        needsDiscovery = true
        connect()
    }

    /// All Bose devices on the network, for the selection in the settings.
    func searchAll() async -> [Soundbar] {
        await discovery.findAll()
    }

    func reconnect(after delay: TimeInterval) {
        reconnectWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.connect() }
        }
        reconnectWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func disconnectSocket() {
        pingTimer?.invalidate()
        pingTimer = nil
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        putInFlight = false
        pendingTarget = nil
        let handlers = responseHandlers.values
        responseHandlers.removeAll()
        handlers.forEach { $0(nil) }
    }

    private func connectionLost(_ reason: String, id: Int) {
        guard id == connectionID else { return }
        disconnectSocket()
        if case .needsLogin = state { return }
        DiagLog.write("Connection lost: \(reason)")
        state = .disconnected(reason)
        needsDiscovery = true // the IP may have changed (DHCP)
        reconnect(after: reconnectDelay)
        reconnectDelay = min(reconnectDelay * 2, Config.maxReconnectDelaySeconds)
    }

    private func receive(on t: URLSessionWebSocketTask, id: Int) {
        t.receive { [weak self] result in
            MainActor.assumeIsolated {
                guard let self, id == self.connectionID else { return }
                switch result {
                case .failure(let error):
                    self.connectionLost(error.localizedDescription, id: id)
                case .success(let message):
                    if case .string(let text) = message { self.handle(text) }
                    self.receive(on: t, id: id)
                }
            }
        }
    }

    // MARK: - Messages

    private func handle(_ text: String) {
        guard let data = text.data(using: .utf8),
              let msg = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let header = msg["header"] as? [String: Any] else { return }
        let resource = header["resource"] as? String ?? ""
        let status = header["status"] as? Int ?? 200
        let isResponse = (header["msgtype"] as? String) == "RESPONSE"

        if resource == "FrontDoorReady" {
            onFrontDoorReady()
            return
        }
        if isResponse, let id = header["reqID"] as? Int, let handler = responseHandlers.removeValue(forKey: id) {
            handler(status == 200 ? msg["body"] as? [String: Any] : nil)
        }

        if isResponse && status != 200 {
            handleError(msg, resource: resource, status: status)
            return
        }

        guard let body = msg["body"] as? [String: Any] else { return }
        switch resource {
        case "/audio/volume":
            applyVolume(body)
            if isResponse && (header["method"] as? String) == "PUT" {
                putInFlight = false
                sendPendingIfNeeded()
            }
        case "/audio/mode":
            audioMode = (audioMode ?? AudioModeState(value: AudioModeState.normal, supported: [])).updated(with: body)
        default:
            break
        }
    }

    private func handleError(_ msg: [String: Any], resource: String, status: Int) {
        let header = msg["header"] as? [String: Any]
        let error = (msg["error"] as? [String: Any])?["message"] as? String ?? "status \(status)"
        DiagLog.write("API: \(header?["method"] as? String ?? "") \(resource) -> \(status) \(APIErrorText.sanitized(error))")
        if resource == "/audio/volume" { putInFlight = false; pendingTarget = nil }
        guard status == 401 else { return }
        // Token rejected → refresh and reconnect
        Task {
            do { _ = try await tokens.refresh(); connect() }
            catch { state = .needsLogin(error.localizedDescription) }
        }
    }

    private func onFrontDoorReady() {
        reconnectDelay = 1
        Task {
            let resources = ["/audio/volume", "/audio/mode"]
            await send("PUT", "/subscription",
                       body: ["notifications": resources.map { ["resource": $0, "version": 1] }],
                       version: 2)
            for resource in resources { await send("GET", resource) }
        }
        pingTimer?.invalidate()
        let id = connectionID
        pingTimer = Timer.scheduledTimer(withTimeInterval: Config.pingIntervalSeconds, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, id == self.connectionID else { return }
                self.task?.sendPing { error in
                    guard let error else { return }
                    DispatchQueue.main.async {
                        MainActor.assumeIsolated { self.connectionLost("ping: \(error.localizedDescription)", id: id) }
                    }
                }
            }
        }
    }

    private func applyVolume(_ body: [String: Any]) {
        let v = (volume ?? VolumeState()).updated(with: body)
        volume = v
        if pendingTarget == v.value && !putInFlight { pendingTarget = nil }
        if state != .ready { state = .ready }
    }

    private func send(_ method: String, _ resource: String, body: [String: Any] = [:], version: Int = 1,
                      onResponse: (([String: Any]?) -> Void)? = nil) async {
        guard let t = task, let guid = soundbar?.guid else { onResponse?(nil); return }
        let token: String
        do { token = try await tokens.validAccessToken() } catch {
            state = .needsLogin(error.localizedDescription)
            onResponse?(nil)
            return
        }
        reqID += 1
        if let onResponse { responseHandlers[reqID] = onResponse }
        let msg: [String: Any] = [
            "header": [
                "device": guid, "method": method, "msgtype": "REQUEST",
                "reqID": reqID, "resource": resource, "status": 200,
                "token": token, "version": version,
            ],
            "body": body,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: msg),
              let text = String(data: data, encoding: .utf8) else { return }
        do { try await t.send(.string(text)) } catch {
            connectionLost("send: \(error.localizedDescription)", id: connectionID)
        }
    }

    /// One-off GET; returns the body, or nil when not connected, on an error or after a timeout.
    func query(_ resource: String) async -> [String: Any]? {
        guard isReady else { return nil }
        return await withCheckedContinuation { continuation in
            let once = OnceBox<[String: Any]?>(continuation) {}
            Task { await send("GET", resource) { body in once.finish(body) } }
            DispatchQueue.main.asyncAfter(deadline: .now() + Config.queryTimeoutSeconds) {
                MainActor.assumeIsolated { once.finish(nil) }
            }
        }
    }

    // MARK: - Volume

    /// Maximum volume from the settings.
    var userMax = Config.defaultMaxVolume

    /// Limits for keys and slider (see `VolumeLimits`).
    var limits: VolumeLimits {
        VolumeLimits(floor: volume?.floor ?? 0, userMax: userMax, deviceMax: volume?.max ?? userMax)
    }

    /// Change the volume by `delta` (key press). Unmutes.
    func adjust(by delta: Int) {
        guard let v = volume,
              let target = limits.target(from: pendingTarget ?? v.value, delta: delta) else { return }
        moveTo(target)
    }

    /// Set the volume directly (slider). Unmutes.
    func setVolume(_ value: Int) {
        guard volume != nil else { return }
        moveTo(limits.clamp(value))
    }

    /// Lowers the volume to `maximum` if it is louder (quiet hours). Unlike `setVolume`
    /// it keeps a muted soundbar muted. Returns false if not connected.
    @discardableResult
    func lowerVolume(to maximum: Int) -> Bool {
        guard isReady, let v = volume else { return false }
        guard (pendingTarget ?? v.value) > maximum else { return true }
        DiagLog.write("Lowering volume to \(maximum)")
        pendingTarget = maximum
        onChange?()
        sendPendingIfNeeded()
        return true
    }

    private func moveTo(_ target: Int) {
        if volume?.muted == true { setMuted(false) }
        pendingTarget = target
        onChange?()
        sendPendingIfNeeded()
    }

    /// Switches the sound mode (one of `audioMode.supported`).
    func setAudioMode(_ value: String) {
        guard let mode = audioMode, mode.supported.contains(value) else { return }
        audioMode?.value = value // immediate feedback, the response confirms it
        Task { await send("PUT", "/audio/mode", body: ["value": value]) }
    }

    func toggleMute() {
        guard let v = volume else { return }
        setMuted(!v.muted)
    }

    func setMuted(_ muted: Bool) {
        volume?.muted = muted // immediate feedback, the response confirms it
        Task { await send("PUT", "/audio/volume", body: ["muted": muted]) }
    }

    private func sendPendingIfNeeded() {
        guard !putInFlight, let target = pendingTarget else { return }
        if target == volume?.value { pendingTarget = nil; onChange?(); return }
        putInFlight = true
        Task { await send("PUT", "/audio/volume", body: ["value": target]) }
    }
}

// MARK: - TLS: the soundbar uses a self-signed certificate.

extension SoundbarClient: URLSessionDelegate {
    nonisolated func urlSession(
        _ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        // Only accept the self-signed certificate of the discovered soundbar, nothing else.
        // Host names are case-insensitive (URL lowercases them: "Bose-…" arrives as "bose-…").
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           challenge.protectionSpace.host.lowercased() == trustedHost.value?.lowercased(),
           let trust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}

/// Minimal thread-safe box (the URLSession delegate runs outside the main actor).
final class LockedValue<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: T
    init(_ value: T) { _value = value }
    var value: T {
        get { lock.withLock { _value } }
        set { lock.withLock { _value = newValue } }
    }
}
