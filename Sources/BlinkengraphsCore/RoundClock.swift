// spec rules/history.md, "Timing".

/// When each Probe round starts: round k at `start + k × interval`, however long earlier rounds
/// took. A round that came due while the previous one ran starts when that one ends; rounds it
/// missed are skipped.
public struct RoundClock: Sendable {
    public let interval: Double
    /// The grid time of the current round.
    private var due: Double
    /// When the current round starts, in Unix seconds.
    public private(set) var start: Double

    public init(start: Double, interval: Double) {
        self.interval = interval
        due = start
        self.start = start
    }

    /// The current round's `at`: whole Unix seconds, rounded down, when it started.
    public var at: Double { start.rounded(.down) }

    /// Moves to the next round, given when the current one ended.
    public mutating func finished(at end: Double) {
        let next = due + interval
        if end >= next {
            due += ((end - due) / interval).rounded(.down) * interval
            start = end
        } else {
            due = next
            start = next
        }
    }
}
