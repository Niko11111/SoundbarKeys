/// A daily time window with a lower maximum volume, e.g. 22:00-07:00 at most 20 (pure logic).
public struct QuietHours: Equatable, Sendable {
    public static let minutesPerDay = 24 * 60

    public var isEnabled: Bool
    /// Start and end as minutes since midnight (0 ..< 1440). End is exclusive.
    public var startMinute: Int
    public var endMinute: Int
    public var maxVolume: Int

    public init(isEnabled: Bool, startMinute: Int, endMinute: Int, maxVolume: Int) {
        self.isEnabled = isEnabled
        self.startMinute = startMinute
        self.endMinute = endMinute
        self.maxVolume = maxVolume
    }

    /// Whether the window is active at `minute` (minutes since midnight).
    /// Windows may cross midnight (22:00-07:00). Start == end means "never" (empty window).
    public func isActive(atMinute minute: Int) -> Bool {
        guard isEnabled, startMinute != endMinute else { return false }
        if startMinute < endMinute {
            return minute >= startMinute && minute < endMinute
        }
        return minute >= startMinute || minute < endMinute
    }

    /// The maximum that applies at `minute`: the normal one, or the lower quiet-hours one.
    public func userMax(normal: Int, atMinute minute: Int) -> Int {
        isActive(atMinute: minute) ? min(normal, maxVolume) : normal
    }
}
