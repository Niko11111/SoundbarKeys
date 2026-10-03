/// SF Symbol for a volume level, like the system's volume indicator (pure logic).
public enum VolumeSymbol {
    /// - Parameters:
    ///   - value: current volume
    ///   - ceiling: effective upper limit; the level is shown as a fraction of it
    public static func name(value: Int, ceiling: Int, muted: Bool) -> String {
        if muted { return "speaker.slash.fill" }
        let fraction = fractionOf(value: value, ceiling: ceiling)
        switch fraction {
        case ..<0.01: return "speaker.fill"
        case ..<0.34: return "speaker.wave.1.fill"
        case ..<0.67: return "speaker.wave.2.fill"
        default: return "speaker.wave.3.fill"
        }
    }

    /// Fill fraction 0…1 of the level bar.
    public static func fractionOf(value: Int, ceiling: Int) -> Double {
        guard ceiling > 0 else { return 0 }
        return min(1, max(0, Double(value) / Double(ceiling)))
    }
}
