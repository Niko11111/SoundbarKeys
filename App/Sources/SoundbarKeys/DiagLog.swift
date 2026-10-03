import AppKit

/// Simple diagnostic log at ~/Library/Logs/SoundbarKeys.log.
enum DiagLog {
    static let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/SoundbarKeys.log")

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    static func write(_ text: String) {
        let line = "\(formatter.string(from: Date())) \(text)\n"
        guard let data = line.data(using: .utf8) else { return }
        if let h = try? FileHandle(forWritingTo: url) {
            h.seekToEndOfFile()
            h.write(data)
            try? h.close()
        } else {
            try? data.write(to: url)
        }
    }

    /// Human-readable modifier flags (modifier keys only, never characters).
    static func describe(_ flags: CGEventFlags) -> String {
        var parts: [String] = []
        if flags.contains(.maskCommand) { parts.append("cmd") }
        if flags.contains(.maskControl) { parts.append("ctrl") }
        if flags.contains(.maskAlternate) { parts.append("opt") }
        if flags.contains(.maskShift) { parts.append("shift") }
        if flags.contains(.maskSecondaryFn) { parts.append("fn") }
        if flags.contains(.maskAlphaShift) { parts.append("caps") }
        return parts.isEmpty ? "-" : parts.joined(separator: "+")
    }

    static func appName(pid: pid_t) -> String {
        NSRunningApplication(processIdentifier: pid)?.localizedName ?? "pid \(pid)"
    }
}
