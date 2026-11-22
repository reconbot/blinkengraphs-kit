// Proposed in the spec (docs/access-points.md, "Link"); ahead of rules/probe-stats.md,
// which keeps one History per Probe. ADR 0005.

/// The Followed Adapter's current attachment: its interface and Gateway.
/// Two networks whose Gateways share an address are one Link until the Access Point is known.
public struct Link: Hashable, Sendable, Codable {
    public var interface: String
    public var gateway: String?

    public init(interface: String, gateway: String?) {
        self.interface = interface
        self.gateway = gateway
    }
}

/// Probe History kept per Link, so results from one Link never count on another.
public struct LinkHistories: Sendable {
    public let ramSeconds: Double
    private var byLink: [Link: [Probe: ProbeHistory]] = [:]
    private var newestAt: [Link: Double] = [:]

    public init(ramSeconds: Double) { self.ramSeconds = ramSeconds }

    public mutating func record(_ probe: Probe, _ result: ProbeResult, on link: Link) {
        byLink[link, default: [:]][probe, default: ProbeHistory(ramSeconds: ramSeconds)].record(result)
        newestAt[link] = max(newestAt[link] ?? result.at, result.at)
        // A Link idle for longer than the RAM History has nothing left to show.
        for (other, at) in newestAt where at + ramSeconds <= result.at {
            byLink[other] = nil
            newestAt[other] = nil
        }
    }

    /// Each Probe's kept results on `link`, oldest first; for history graphs.
    public func results(on link: Link) -> [Probe: [ProbeResult]] {
        (byLink[link] ?? [:]).mapValues(\.results)
    }

    public func stats(on link: Link, windowSeconds: Double) -> [Probe: ProbeStats] {
        (byLink[link] ?? [:]).mapValues { $0.stats(windowSeconds: windowSeconds) }
    }
}
