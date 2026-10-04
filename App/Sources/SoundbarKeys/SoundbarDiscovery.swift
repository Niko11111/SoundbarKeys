import Foundation
import Network
import SoundbarKeysCore
import dnssd

/// A Bose soundbar found on the local network.
struct Soundbar: Codable, Equatable, Identifiable {
    /// Device GUID from the Bonjour TXT record; required in every API request header.
    var guid: String
    /// User-visible name (Bonjour service name, e.g. "Living Room").
    var name: String
    /// mDNS host name (e.g. "Bose-<GUID>.local") used for the WebSocket connection;
    /// stays valid when the soundbar gets a new IP address.
    var host: String
    /// Model from the TXT record, e.g. "Bose Soundbar 700" (optional: older caches lack it).
    var model: String?

    var id: String { guid }
}

/// Finds Bose ECO2 devices via Bonjour (`_bose-passport._tcp`) and resolves their host name.
@MainActor
final class SoundbarDiscovery {
    private static let cacheKey = "soundbar"

    /// Last soundbar that worked; reused first so startup does not wait for Bonjour.
    var cached: Soundbar? {
        get {
            guard let data = UserDefaults.standard.data(forKey: Self.cacheKey) else { return nil }
            return try? JSONDecoder().decode(Soundbar.self, from: data)
        }
        set {
            UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: Self.cacheKey)
        }
    }

    /// The soundbar to connect to. With `selected` set only that device is acceptable,
    /// otherwise the previously used one is preferred (rules in `DeviceChoice`).
    func find(selected: String?, timeout: TimeInterval = Config.discoveryTimeoutSeconds) async -> Soundbar? {
        let lastUsed = cached?.guid
        let candidates = await browse(timeout: timeout, stopEarlyFor: selected ?? lastUsed)
        let order = DeviceChoice.order(found: candidates.map(\.guid), selected: selected, lastUsed: lastUsed)
        for guid in order {
            guard let candidate = candidates.first(where: { $0.guid == guid }),
                  let bar = await soundbar(from: candidate) else { continue }
            cached = bar
            DiagLog.write("Discovery: found \(bar.name) at \(bar.host)")
            return bar
        }
        DiagLog.write("Discovery: no soundbar found\(selected == nil ? "" : " (selected device)")")
        return nil
    }

    /// All devices on the network (for the selection in the settings). Waits the full timeout.
    func findAll(timeout: TimeInterval = Config.discoveryTimeoutSeconds) async -> [Soundbar] {
        var result: [Soundbar] = []
        for candidate in await browse(timeout: timeout, stopEarlyFor: nil) {
            if let bar = await soundbar(from: candidate) { result.append(bar) }
        }
        return result
    }

    private func soundbar(from candidate: Candidate) async -> Soundbar? {
        guard let host = await resolve(candidate.endpoint) else { return nil }
        return Soundbar(guid: candidate.guid, name: candidate.name, host: host, model: candidate.model)
    }

    // MARK: - Bonjour

    private struct Candidate {
        var guid: String
        var name: String
        var model: String?
        var endpoint: NWEndpoint
    }

    /// Candidates in discovery order (one per GUID).
    private func browse(timeout: TimeInterval, stopEarlyFor preferred: String?) async -> [Candidate] {
        await withCheckedContinuation { continuation in
            let browser = NWBrowser(for: .bonjourWithTXTRecord(type: Config.bonjourType, domain: nil), using: .tcp)
            let once = OnceBox<[Candidate]>(continuation) { browser.cancel() }
            var found: [Candidate] = [] // only touched on the main queue

            browser.browseResultsChangedHandler = { results, _ in
                MainActor.assumeIsolated {
                    for result in results {
                        guard let candidate = Self.candidate(from: result),
                              !found.contains(where: { $0.guid == candidate.guid }) else { continue }
                        found.append(candidate)
                        // Stop early once the wanted device shows up.
                        if candidate.guid == preferred { once.finish(found) }
                    }
                }
            }
            browser.stateUpdateHandler = { state in
                MainActor.assumeIsolated {
                    if case .failed(let error) = state {
                        DiagLog.write("Discovery: browser failed: \(error)")
                        once.finish(found)
                    }
                }
            }
            browser.start(queue: .main)
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) {
                MainActor.assumeIsolated { once.finish(found) }
            }
        }
    }

    /// Bose ECO2 devices only; others (e.g. SoundTouch) speak a different API.
    private static func candidate(from result: NWBrowser.Result) -> Candidate? {
        guard case .bonjour(let txt) = result.metadata,
              let guid = txt["GUID"], !guid.isEmpty,
              txt["ECOSYS"].map({ $0 == "ECO2" }) ?? true else { return nil }
        var name = guid
        if case .service(let serviceName, _, _, _) = result.endpoint { name = serviceName }
        return Candidate(guid: guid, name: name, model: txt["PNAME"], endpoint: result.endpoint)
    }

    /// Resolves a Bonjour service to its host name with DNS-SD, without connecting:
    /// the port the soundbar advertises (8090) is closed, the API runs on `Config.apiPort`.
    private func resolve(_ endpoint: NWEndpoint) async -> String? {
        guard case .service(let name, let type, let domain, _) = endpoint else { return nil }
        return await withCheckedContinuation { continuation in
            let request = ResolveRequest(continuation)
            request.start(name: name, type: type, domain: domain)
            DispatchQueue.main.asyncAfter(deadline: .now() + Config.resolveTimeoutSeconds) {
                MainActor.assumeIsolated { request.finish(nil) }
            }
        }
    }
}

/// One `DNSServiceResolve` call; keeps itself alive until it finished (result or timeout).
@MainActor
private final class ResolveRequest {
    private var continuation: CheckedContinuation<String?, Never>?
    private var serviceRef: DNSServiceRef?
    private var keepAlive: Unmanaged<ResolveRequest>?

    init(_ continuation: CheckedContinuation<String?, Never>) {
        self.continuation = continuation
    }

    func start(name: String, type: String, domain: String) {
        let retained = Unmanaged.passRetained(self)
        keepAlive = retained
        let callback: DNSServiceResolveReply = { _, _, _, errorCode, _, hostTarget, _, _, _, context in
            guard let context else { return }
            let request = Unmanaged<ResolveRequest>.fromOpaque(context).takeUnretainedValue()
            let host = errorCode == kDNSServiceErr_NoError ? hostTarget.map { String(cString: $0) } : nil
            // DNSServiceSetDispatchQueue(.main) delivers this callback on the main queue.
            MainActor.assumeIsolated { request.finish(host.map(ResolveRequest.withoutTrailingDot)) }
        }
        let error = DNSServiceResolve(&serviceRef, 0, 0, name, type, domain, callback, retained.toOpaque())
        guard error == kDNSServiceErr_NoError, let serviceRef else {
            DiagLog.write("Discovery: DNSServiceResolve failed (\(error))")
            finish(nil)
            return
        }
        DNSServiceSetDispatchQueue(serviceRef, .main)
    }

    func finish(_ host: String?) {
        guard let continuation else { return }
        self.continuation = nil
        if let serviceRef { DNSServiceRefDeallocate(serviceRef) }
        serviceRef = nil
        continuation.resume(returning: host)
        keepAlive?.release()
        keepAlive = nil
    }

    private nonisolated static func withoutTrailingDot(_ host: String) -> String {
        host.hasSuffix(".") ? String(host.dropLast()) : host
    }
}
