import AppKit
import SoundbarKeysCore

/// Collects the anonymous compatibility report and opens a pre-filled GitHub issue.
@MainActor
enum CompatibilityReporter {
    /// Returns false if the soundbar is not connected or did not answer.
    static func report(client: SoundbarClient, output: OutputWatcher) async -> Bool {
        guard let info = await client.query("/system/info"),
              let capabilities = await client.query("/system/capabilities") else { return false }
        var report = CompatibilityReport()
        report.appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let os = ProcessInfo.processInfo.operatingSystemVersion
        report.macOSVersion = "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
        report.architecture = architecture
        report.outputIsHDMI = output.current?.isHDMI ?? false
        (report.productName, report.productType, report.firmware) = CompatibilityReport.soundbarFields(fromSystemInfo: info)
        if let volume = client.volume { report.volumeRange = "\(volume.floor)–\(volume.max)" }
        report.soundModes = client.audioMode?.supported ?? []
        report.endpoints = CompatibilityReport.endpoints(fromCapabilities: capabilities)

        // Also on the clipboard, in case the browser drops a long pre-filled URL.
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report.markdown, forType: .string)
        if let url = report.issueURL(repository: Config.githubURL) { NSWorkspace.shared.open(url) }
        DiagLog.write("Compatibility report created for \(report.productName)")
        return true
    }

    private static var architecture: String {
        #if arch(arm64)
        return "Apple Silicon"
        #else
        return "Intel"
        #endif
    }
}
