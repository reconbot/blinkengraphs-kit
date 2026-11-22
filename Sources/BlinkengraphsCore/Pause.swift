// spec rules/history.md, "Pauses".

/// `[begin, end)` in Unix seconds when nothing was measured. Machine-wide: every key and Link
/// shares it. `end` includes the settle time after measuring resumed.
public struct Pause: Codable, Equatable, Sendable {
    public var begin: Double
    public var end: Double

    public init(begin: Double, end: Double) { self.begin = begin; self.end = end }

    /// The Pause a kill leaves, found on the next launch: from the second after the newest Raw
    /// record to the settle time after launch. Empty, never negative, if the clock went back.
    public static func afterKill(newestAt: Int, launch: Double, settle: Double) -> Pause {
        let begin = Double(newestAt) + 1
        return Pause(begin: begin, end: max(begin, launch + settle))
    }

    /// Whether a Round from `start` to the end of its last Probe falls in any Pause, so it
    /// records nothing. One ending exactly as a Pause begins still records.
    public static func cuts(start: Double, end: Double, _ pauses: [Pause]) -> Bool {
        pauses.contains { start < $0.end && end > $0.begin }
    }

    /// Seconds of `[from, to)` in Pauses, which don't overlap.
    public static func seconds(in pauses: [Pause], from: Double, to: Double) -> Double {
        pauses.reduce(0) { $0 + max(0, min($1.end, to) - max($1.begin, from)) }
    }
}
