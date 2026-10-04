import Foundation

/// Anonymous compatibility report for a GitHub issue (pure logic).
///
/// Only technical facts: no device name, GUID, serial number, MAC address, country or account data.
/// `soundbarFields(fromSystemInfo:)` picks the allowed fields from `/system/info` on purpose
/// (allow list), so new fields in a firmware update never leak into a report by accident.
public struct CompatibilityReport: Equatable, Sendable {
    public var appVersion = "?"
    public var macOSVersion = "?"
    public var architecture = "?"
    public var outputIsHDMI = false
    public var productName = "?"
    public var productType = "?"
    public var firmware = "?"
    public var volumeRange = "?"
    public var soundModes: [String] = []
    public var endpoints: [String] = []

    /// Fields are set one by one (keeps the parameter list short).
    public init() {}

    /// The only `/system/info` fields a report may contain.
    public static func soundbarFields(fromSystemInfo info: [String: Any]) -> (name: String, type: String, firmware: String) {
        (info["productName"] as? String ?? "?", info["productType"] as? String ?? "?",
         info["softwareVersion"] as? String ?? "?")
    }

    /// Endpoint names from `/system/capabilities`, sorted.
    public static func endpoints(fromCapabilities caps: [String: Any]) -> [String] {
        let groups = caps["group"] as? [[String: Any]] ?? []
        let names = groups.flatMap { ($0["endpoints"] as? [[String: Any]] ?? []).compactMap { $0["endpoint"] as? String } }
        return Array(Set(names)).sorted()
    }

    public var markdown: String {
        """
        | | |
        |---|---|
        | SoundbarKeys | \(appVersion) |
        | macOS | \(macOSVersion) (\(architecture)) |
        | Output | \(outputIsHDMI ? "HDMI" : "not HDMI") |
        | Soundbar | \(productName) (`\(productType)`) |
        | Firmware | \(firmware) |
        | Volume range | \(volumeRange) |
        | Sound modes | \(soundModes.isEmpty ? "–" : soundModes.joined(separator: ", ")) |
        | API endpoints | \(endpoints.count) |

        <details><summary>Endpoints</summary>

        \(endpoints.map { "`\($0)`" }.joined(separator: " "))

        </details>
        """
    }

    /// New-issue URL that pre-fills the issue form `compatibility.yml` (field ids: model, firmware, report).
    public func issueURL(repository: URL) -> URL? {
        var components = URLComponents(url: repository.appendingPathComponent("issues/new"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "template", value: "compatibility.yml"),
            URLQueryItem(name: "title", value: "Compatibility: \(productName)"),
            URLQueryItem(name: "model", value: productName),
            URLQueryItem(name: "firmware", value: firmware),
            URLQueryItem(name: "report", value: markdown),
        ]
        return components?.url
    }
}
