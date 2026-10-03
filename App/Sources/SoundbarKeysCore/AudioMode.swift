/// The soundbar's sound mode as reported by `/audio/mode` (pure logic, no I/O).
///
/// Example body: `{"value": "NORMAL", "properties": {"supportedValues": ["DIALOG", "NORMAL"]}}`.
/// Which modes exist depends on the model (Soundbar 700: NORMAL, DIALOG).
public struct AudioModeState: Equatable, Sendable {
    public static let normal = "NORMAL"

    public var value: String
    public var supported: [String]

    public init(value: String, supported: [String]) {
        self.value = value
        self.supported = supported
    }

    /// Applies the fields present in a `/audio/mode` body; missing fields keep their value.
    public func updated(with body: [String: Any]) -> AudioModeState {
        var mode = self
        if let value = body["value"] as? String { mode.value = value }
        if let values = (body["properties"] as? [String: Any])?["supportedValues"] as? [String] {
            mode.supported = values
        }
        return mode
    }

    /// Modes in display order: NORMAL first, then the others as the soundbar lists them.
    public var orderedModes: [String] {
        supported.filter { $0 == Self.normal } + supported.filter { $0 != Self.normal }
    }

    /// A switch only makes sense with at least two modes.
    public var isSwitchable: Bool { supported.count >= 2 }
}
