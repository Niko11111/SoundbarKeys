/// A decoded media key event (NX_SYSDEFINED, subtype 8). Pure logic, no I/O.
public struct MediaKeyEvent: Equatable, Sendable {
    public enum Key: Equatable, Sendable { case volumeUp, volumeDown, mute }

    public var key: Key
    /// Raw key code (NX_KEYTYPE_*), used to pair key-down and key-up.
    public var code: Int
    public var isDown: Bool
    public var isRepeat: Bool

    // From IOKit/hidsystem/ev_keymap.h
    static let soundUpCode = 0    // NX_KEYTYPE_SOUND_UP
    static let soundDownCode = 1  // NX_KEYTYPE_SOUND_DOWN
    static let muteCode = 7       // NX_KEYTYPE_MUTE
    static let keyDownState = 0x0A
    static let repeatFlag = 0x1

    /// Decodes `NSEvent.data1` of a system-defined event:
    /// bits 16-31 = key code, bits 8-15 = key state (0x0A down, 0x0B up), bit 0 = repeat.
    /// Returns nil for all other keys (brightness, play/pause, ...).
    public init?(data1: Int) {
        let code = (data1 & 0xFFFF_0000) >> 16
        let flags = data1 & 0x0000_FFFF
        switch code {
        case Self.soundUpCode: key = .volumeUp
        case Self.soundDownCode: key = .volumeDown
        case Self.muteCode: key = .mute
        default: return nil
        }
        self.code = code
        isDown = (flags & 0xFF00) >> 8 == Self.keyDownState
        isRepeat = flags & Self.repeatFlag == Self.repeatFlag
    }
}
