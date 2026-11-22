// Everything measured while the app runs, kept per Link (ADR 0005, ADR 0009). The app feeds it
// events and reads one Snapshot per refresh; scheduling and sockets stay outside.

public struct Measurements: Sendable {
    /// One Probe attempt's result, as a runner reports it.
    public enum Outcome: Sendable, Equatable {
        case reply(ms: Double)
        case lost
        /// The OS refused to send it, such as Local Network Privacy. Not a loss (rules/probe-stats.md).
        case denied
        /// The path can't reach the Target's IP version. Not sent, not a loss.
        case unreachable
    }

    /// What the screen and the report show for the current Link.
    public struct Snapshot: Sendable {
        public var findings: [Finding]
        public var stats: [Probe: ProbeStats]
        public var denied: Set<Probe>
        public var hops: [String: [HopRow]]
        /// Each Probe's RAM History, for the graphs.
        public var results: [Probe: [ProbeResult]]
        public var captivePortal: Bool
        public var publicAddress: [IPFamily: PublicAddressReading]
    }

    private let defaults: Defaults
    private var histories: LinkHistories
    private var traces: [Link: [String: HopTrace]] = [:]
    private var plans: [Link: [String: HopSweepPlan]] = [:]
    public private(set) var link = Link(interface: "none", gateway: nil)
    private var pathUp = true
    private var viaVPN = false
    // These describe the current Link only and reset when it changes.
    private var denied: Set<Probe> = []
    private var captivePortal = false
    private var publicAddress: [IPFamily: PublicAddressReading] = [:]
    /// The Probe Group's Probes and traced Targets; history for anything else stays out of the snapshot.
    private var probes: Set<Probe>
    private var traced: Set<String>

    public init(defaults: Defaults) {
        probes = Set(defaults.probeGroup.probes)
        traced = Set(defaults.probeGroup.targets.filter(\.trace).map(\.target))
        self.defaults = defaults
        histories = LinkHistories(ramSeconds: Double(defaults.history.ramMinutes * 60))
    }

    /// After the user edits the Probe Group. History of removed Probes is kept but not shown.
    public mutating func setProbeGroup(_ group: Defaults.ProbeGroup) {
        probes = Set(group.probes)
        traced = Set(group.targets.filter(\.trace).map(\.target))
        denied.formIntersection(probes)
    }

    /// Returns whether the Link changed.
    @discardableResult
    public mutating func setPath(link: Link, up: Bool, viaVPN: Bool) -> Bool {
        pathUp = up
        self.viaVPN = viaVPN
        guard link != self.link else { return false }
        self.link = link
        denied = []
        captivePortal = false
        publicAddress = [:]
        return true
    }

    /// Records an outcome on the Link it was sent on. Returns the result stored, for the Rollups,
    /// or nil when nothing was (denied and unreachable aren't results).
    public mutating func record(_ probe: Probe, _ outcome: Outcome, sentOn link: Link, at: Double) -> ProbeResult? {
        let rtt: Double?
        switch outcome {
        case .reply(let ms): rtt = ms
        case .lost: rtt = nil
        case .denied:
            if link == self.link { denied.insert(probe) }
            return nil
        case .unreachable:
            return nil
        }
        if link == self.link { denied.remove(probe) }
        let result = ProbeResult(at: at, rttMs: rtt.map(RTT.recorded))
        histories.record(probe, result, on: link)
        return result
    }

    /// The TTLs the next sweep toward `target` sends on the current Link (rules/hop-trace.md).
    public mutating func sweepTTLs(_ target: String, at: Double) -> ClosedRange<Int> {
        let cfg = defaults.hopTrace
        var plan = plans[link]?[target] ?? HopSweepPlan(maxTtl: cfg.maxTtl, fullSweepEveryS: Double(cfg.fullSweepEveryS))
        let ttls = plan.ttls(at: at, pathLength: traces[link]?[target]?.pathLength)
        plans[link, default: [:]][target] = plan
        return ttls
    }

    /// One sweep's results, in any order.
    public mutating func recordSweep(_ results: [HopResult], target: String, sentOn link: Link) {
        var trace = traces[link]?[target] ?? HopTrace(hopWindow: defaults.hopTrace.hopWindow)
        // Highest TTL first: past the Target every TTL is `reached`, and the lowest reached one,
        // recorded last, prunes the rows above it.
        for var r in results.sorted(by: { $0.ttl > $1.ttl }) {
            r.rttMs = r.rttMs.map(RTT.recorded)
            trace.record(r)
        }
        traces[link, default: [:]][target] = trace
    }

    /// A check made on a Link we've since left says nothing about this one.
    public mutating func setCaptivePortal(_ portal: Bool, checkedOn link: Link) {
        if link == self.link { captivePortal = portal }
    }

    public mutating func setPublicAddress(_ readings: [IPFamily: PublicAddressReading], lookedUpOn link: Link) {
        if link == self.link { publicAddress = readings }
    }

    public func snapshot() -> Snapshot {
        let stats = histories.stats(on: link, windowSeconds: Double(defaults.history.recentWindowS))
            .filter { probes.contains($0.key) }
        let findings = Verdict.evaluate(VerdictInput(
            probes: stats.map { .init(probe: $0.key, stat: $0.value) },
            pathUp: pathUp, viaVPN: viaVPN, captivePortal: captivePortal))
        return Snapshot(findings: findings, stats: stats, denied: denied,
                        hops: (traces[link] ?? [:]).filter { traced.contains($0.key) }.mapValues(\.table),
                        results: histories.results(on: link).filter { probes.contains($0.key) },
                        captivePortal: captivePortal, publicAddress: publicAddress)
    }
}
