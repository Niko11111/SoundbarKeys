/// Which discovered device to try, in which order (pure logic).
public enum DeviceChoice {
    /// - Parameters:
    ///   - found: GUIDs in discovery order
    ///   - selected: device chosen in the settings; if set, only this one is acceptable
    ///     (never fall back to another device, e.g. the kitchen speaker)
    ///   - lastUsed: device used last time; tried first in automatic mode
    public static func order(found: [String], selected: String?, lastUsed: String?) -> [String] {
        if let selected { return found.filter { $0 == selected } }
        return found.filter { $0 == lastUsed } + found.filter { $0 != lastUsed }
    }
}
