import CoreAudio
import Foundation
import SoundbarKeysCore

/// An audio output device of this Mac.
struct OutputDevice: Identifiable, Equatable {
    /// Persistent unique ID (kAudioDevicePropertyDeviceUID); stays the same across restarts.
    var uid: String
    var name: String
    var isHDMI: Bool

    var id: String { uid }
}

/// Observes the default output device and decides whether the volume keys control the soundbar
/// (rule in `KeyActivation`: any HDMI device, or the device selected in the settings).
@MainActor
final class OutputWatcher {
    private(set) var current: OutputDevice?
    private(set) var isActive = false
    var onChange: (() -> Void)?

    /// Device chosen in the settings; nil = automatic (any HDMI device).
    var selectedUID: String? {
        didSet { if selectedUID != oldValue { update() } }
    }

    var deviceName: String { current?.name ?? "?" }

    private var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    init() {
        update()
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.main
        ) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.update() }
        }
    }

    private func update() {
        var deviceID = AudioObjectID(0)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID)
        current = Self.device(deviceID)
        isActive = KeyActivation.isActive(currentUID: current?.uid, currentIsHDMI: current?.isHDMI ?? false,
                                          selectedUID: selectedUID)
        onChange?()
    }

    /// All devices that can play audio (for the selection in the settings).
    static func allOutputDevices() -> [OutputDevice] {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size) == noErr
        else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids)
        return ids.filter(hasOutputStreams).compactMap(device)
    }

    // MARK: - CoreAudio helpers

    private static func device(_ id: AudioObjectID) -> OutputDevice? {
        guard let uid = stringProperty(kAudioDevicePropertyDeviceUID, of: id) else { return nil }
        return OutputDevice(uid: uid, name: stringProperty(kAudioObjectPropertyName, of: id) ?? uid,
                            isHDMI: transport(of: id) == kAudioDeviceTransportTypeHDMI)
    }

    private static func stringProperty(_ selector: AudioObjectPropertySelector, of id: AudioObjectID) -> String? {
        var addr = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &value) == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }

    private static func transport(of id: AudioObjectID) -> UInt32 {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &value)
        return value
    }

    private static func hasOutputStreams(_ id: AudioObjectID) -> Bool {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size) == noErr && size > 0
    }
}
