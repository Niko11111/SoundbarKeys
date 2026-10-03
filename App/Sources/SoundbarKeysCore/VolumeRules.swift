/// Volume limits and the rules for keys and slider (pure logic, no I/O).
public struct VolumeLimits: Equatable, Sendable {
    /// Lowest value keys/slider may set: the soundbar's hard limit (`properties.minLimit`, usually 0).
    /// The soundbar's soft `min` (e.g. 10) can be undercut with a PUT, so it is ignored on purpose.
    public var floor: Int
    /// Highest value keys/slider may set: the user's maximum, never above the soundbar's own `max`.
    public var ceiling: Int

    public init(floor: Int, userMax: Int, deviceMax: Int) {
        self.floor = floor
        self.ceiling = max(floor, min(userMax, deviceMax))
    }

    public func clamp(_ value: Int) -> Int {
        min(ceiling, max(floor, value))
    }

    /// Target for a key press, or nil if nothing should be sent.
    ///
    /// If the soundbar is already at or above the ceiling (e.g. turned up with the TV remote),
    /// "louder" does nothing instead of jumping *down* to the ceiling.
    public func target(from current: Int, delta: Int) -> Int? {
        if delta > 0 && current >= ceiling { return nil }
        return clamp(current + delta)
    }
}

/// The soundbar's volume state as reported by `/audio/volume`.
public struct VolumeState: Equatable, Sendable {
    public var value: Int
    public var muted: Bool
    /// Hard lower limit (`properties.minLimit`).
    public var floor: Int
    /// The soundbar's own upper limit (`max`).
    public var max: Int

    public init(value: Int = 0, muted: Bool = false, floor: Int = 0, max: Int = 100) {
        self.value = value
        self.muted = muted
        self.floor = floor
        self.max = max
    }

    /// Applies the fields present in a `/audio/volume` body; missing fields keep their value.
    public func updated(with body: [String: Any]) -> VolumeState {
        var v = self
        if let x = body["value"] as? Int { v.value = x }
        if let x = body["muted"] as? Bool { v.muted = x }
        if let x = (body["properties"] as? [String: Any])?["minLimit"] as? Int { v.floor = x }
        if let x = body["max"] as? Int { v.max = x }
        return v
    }
}
