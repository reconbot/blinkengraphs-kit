public enum GraphScale {
    /// The smallest of 1, 1.5, 2, 2.5, 5 or 7.5 times a power of ten that is at least `value`,
    /// so a graph's scale changes only when its data crosses a round number.
    public static func niceCeiling(_ value: Double) -> Double {
        guard value > 0 else { return 1 }
        var magnitude = 1.0
        while magnitude * 10 <= value { magnitude *= 10 }
        while magnitude > value { magnitude /= 10 }
        for step in [1, 1.5, 2, 2.5, 5, 7.5, 10] where step * magnitude >= value { return step * magnitude }
        return 10 * magnitude
    }
}
