import AppKit
import CoreGraphics
import SoundbarKeysCore

/// Intercepts the media keys volume up/down/mute (NX_SYSDEFINED, subtype 8).
/// Requires Accessibility permission because events are swallowed.
///
/// Additionally there is a listen-only tap on key presses that, only during the 30 s after a
/// volume key, logs where key presses go and which modifiers are held (no characters/key codes).
/// It helps diagnose a "keyboard stops typing" issue.
@MainActor
final class KeyTap {
    typealias Key = MediaKeyEvent.Key

    /// Decides synchronously inside the tap whether the key is swallowed (must be cheap).
    var shouldHandle: (() -> Bool)?
    /// Performs the actual action – asynchronously, after returning from the tap.
    var handler: ((Key, _ isRepeat: Bool) -> Void)?

    private var tap: CFMachPort?
    private var diagTap: CFMachPort?
    /// Key codes whose key-down was swallowed → only their key-up is swallowed as well.
    private var swallowedDown: Set<Int> = []
    private var diagUntil = Date.distantPast

    private static let NX_SYSDEFINED: UInt32 = 14

    static var isTrusted: Bool { AXIsProcessTrusted() }

    static func requestTrust() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    @discardableResult
    func start() -> Bool {
        guard tap == nil else { return true }
        let refcon = Unmanaged.passUnretained(self).toOpaque()

        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let me = Unmanaged<KeyTap>.fromOpaque(refcon).takeUnretainedValue()
            return MainActor.assumeIsolated { me.process(type: type, event: event) }
        }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: CGEventMask(1) << CGEventMask(Self.NX_SYSDEFINED),
            callback: callback, userInfo: refcon
        ) else {
            DiagLog.write("KeyTap: tapCreate failed")
            return false
        }
        self.tap = tap
        let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        // Diagnostics: listen only, never swallows anything.
        let diagCallback: CGEventTapCallBack = { _, type, event, refcon in
            if let refcon {
                let me = Unmanaged<KeyTap>.fromOpaque(refcon).takeUnretainedValue()
                MainActor.assumeIsolated { me.diagnose(type: type, event: event) }
            }
            return Unmanaged.passUnretained(event)
        }
        let diagMask = (CGEventMask(1) << CGEventType.keyDown.rawValue)
            | (CGEventMask(1) << CGEventType.flagsChanged.rawValue)
        if let d = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .tailAppendEventTap, options: .listenOnly,
            eventsOfInterest: diagMask, callback: diagCallback, userInfo: refcon
        ) {
            diagTap = d
            let s = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, d, 0)
            CFRunLoopAddSource(CFRunLoopGetMain(), s, .commonModes)
            CGEvent.tapEnable(tap: d, enable: true)
        }
        DiagLog.write("KeyTap started")
        return true
    }

    private func process(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            DiagLog.write("KeyTap: disabled by the system (\(type == .tapDisabledByTimeout ? "timeout" : "user input")), re-enabling")
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        guard type.rawValue == Self.NX_SYSDEFINED,
              let ns = NSEvent(cgEvent: event), ns.subtype.rawValue == 8 else {
            return Unmanaged.passUnretained(event)
        }
        guard let media = MediaKeyEvent(data1: ns.data1) else { return Unmanaged.passUnretained(event) }

        let swallow = decideSwallow(media)
        diagUntil = Date().addingTimeInterval(Config.keyDiagnosticsWindowSeconds)
        DiagLog.write("Media key \(media.key) \(media.isDown ? "down" : "up")\(media.isRepeat ? " repeat" : "") "
            + "flags=\(DiagLog.describe(event.flags)) → \(swallow ? "swallowed" : "passed through")")
        return swallow ? nil : Unmanaged.passUnretained(event)
    }

    /// Key-up is only swallowed if its key-down was (otherwise macOS would see an unpaired event).
    private func decideSwallow(_ media: MediaKeyEvent) -> Bool {
        guard media.isDown else { return swallowedDown.remove(media.code) != nil }
        guard shouldHandle?() == true else { return false }
        swallowedDown.insert(media.code)
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated { self?.handler?(media.key, media.isRepeat) }
        }
        return true
    }

    private func diagnose(type: CGEventType, event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let diagTap { CGEvent.tapEnable(tap: diagTap, enable: true) }
            return
        }
        guard Date() < diagUntil else { return }
        let target = pid_t(event.getIntegerValueField(.eventTargetUnixProcessID))
        let front = NSWorkspace.shared.frontmostApplication?.localizedName ?? "?"
        let session = CGEventSource.flagsState(.combinedSessionState)
        let kind = type == .keyDown ? "key" : "modifier changed"
        DiagLog.write("Diag \(kind): flags=\(DiagLog.describe(event.flags)) session=\(DiagLog.describe(session)) "
            + "target=\(DiagLog.appName(pid: target)) front=\(front) selfActive=\(NSApp.isActive) "
            + "keyWindow=\(NSApp.keyWindow.map { String(describing: Swift.type(of: $0)) } ?? "-")")
    }
}
