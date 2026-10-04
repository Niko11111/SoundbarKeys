/// When the volume keys control the soundbar (pure logic).
public enum KeyActivation {
    /// - Parameters:
    ///   - currentUID: unique ID of the Mac's current output device
    ///   - currentIsHDMI: whether that device is connected via HDMI
    ///   - selectedUID: device chosen in the settings; nil = automatic (any HDMI device)
    public static func isActive(currentUID: String?, currentIsHDMI: Bool, selectedUID: String?) -> Bool {
        guard let selectedUID else { return currentIsHDMI }
        return currentUID == selectedUID
    }
}
