// Everything measured while the app runs, kept per Link (ADR 0009). The app feeds it events and
// reads one Snapshot per refresh; scheduling, sockets and files stay outside.

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

    /// One firing of the Probe Group on one Link: committed whole, or not at all when a Pause
    /// cuts it (spec rules/history.md, "Pauses").
    public struct Round: Sendable {
        /// The Round's whole Unix second, rounded down from `start`.
        public var at: Int { Int(start.rounded(.down)) }
        public var start: Double
        /// When its last Probe ended.
        public var end: Double
        public var link: Link
        public var outcomes: [(Probe, Outcome)]

        public init(start: Double, end: Double, link: Link, outcomes: [(Probe, Outcome)]) {
            self.start = start; self.end = end; self.link = link; self.outcomes = outcomes
        }
    }

    /// What the screen and the report show for the current Link.
    public struct Snapshot: Sendable {
        public var findings: [Finding]
        /// Probes with an empty window have none (rules/probe-stats.md).
        public var stats: [Probe: ProbeStats]
        public var denied: Set<Probe>
        public var hops: [String: [HopRow]]
        /// Each Probe's results in its stats window, for the readouts.
        public var window: [Probe: [ProbeResult]]
        public var captivePortal: Bool
        public var publicAddress: [IPFamily: PublicAddressReading]
        /// Measuring stopped, or resumed and still settling.
        public var paused: Bool
        public var now: Double
    }

    private let defaults: Defaults
    public private(set) var history: History
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
    /// In Probe Group order, which the Verdict's tie-break follows.
    private var probes: [Probe]
    private var traced: Set<String>
    /// A Pause that has begun and not ended: measuring is stopped.
    private var pauseBegan: Double?
    /// How long after measuring resumes the network is given to become usable.
    public let settle: Double

    /// `history` seeds what was measured before, as demo data does; nil starts empty.
    public init(defaults: Defaults, settle: Double, history: History? = nil) {
        probes = defaults.probeGroup.probes
        traced = Set(defaults.probeGroup.targets.filter(\.trace).map(\.target))
        self.defaults = defaults
        self.settle = settle
        self.history = history ?? History(defaults: defaults)
    }

    /// After the user edits the Probe Group. History of removed Probes is kept but not shown.
    public mutating func setProbeGroup(_ group: Defaults.ProbeGroup) {
        probes = group.probes
        traced = Set(group.targets.filter(\.trace).map(\.target))
        denied.formIntersection(Set(probes))
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

    // MARK: - Pauses

    /// Measuring stops: the app went to the background.
    public mutating func pause(at t: Double) {
        if pauseBegan == nil { pauseBegan = t }
    }

    /// Measuring resumes at `t`. The Pause ends a settle time later. With no Pause open, as at
    /// launch, the Pause is the launch itself: "not yet started" (CONTEXT.md, Pause).
    public mutating func resume(at t: Double) {
        let begin = pauseBegan ?? t
        pauseBegan = nil
        history.add(Pause(begin: begin, end: t + settle))
    }

    /// On launch, the stretch after the newest record restored from disk was a kill.
    public mutating func restore(_ restored: History, launch: Double) {
        history = restored
        if let newest = restored.newestAt, Double(newest) < launch {
            pauseBegan = Pause.afterKill(newestAt: newest, launch: launch, settle: 0).begin
        }
    }

    private var pauses: [Pause] {
        history.pauses + (pauseBegan.map { [Pause(begin: $0, end: .infinity)] } ?? [])
    }

    /// Whether `t` is in a Pause, the settle time included.
    public func paused(at t: Double) -> Bool { pauses.contains { $0.begin <= t && t < $0.end } }

    // MARK: - Results

    /// Records a Round on the Link it was sent on, unless a Pause cut it. Returns whether it recorded.
    @discardableResult
    public mutating func commit(_ round: Round) -> Bool {
        guard !Pause.cuts(start: round.start, end: round.end, pauses) else { return false }
        for (probe, outcome) in round.outcomes {
            let rtt: Double?
            switch outcome {
            case .reply(let ms): rtt = ms
            case .lost: rtt = nil
            case .denied:
                if round.link == link { denied.insert(probe) }
                continue
            case .unreachable:
                continue
            }
            if round.link == link { denied.remove(probe) }
            history.record(HistoryKey(link: round.link, probe: probe), RawResult(at: round.at, rttMs: rtt.map(RTT.recorded)))
        }
        return true
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

    /// Writes the Archive Rows whose steps have ended, and applies retention.
    public mutating func advance(now: Double) {
        history.advance(now: Int(now.rounded(.down)))
    }

    // MARK: - Reading

    public func snapshot(now: Double) -> Snapshot {
        let windowS = Double(defaults.history.recentWindowS)
        var stats: [Probe: ProbeStats] = [:], window: [Probe: [ProbeResult]] = [:]
        for probe in probes {
            let raw = history.results(HistoryKey(link: link, probe: probe), after: Int.min, through: Int(now))
            let results = raw.map { ProbeResult(at: Double($0.at), rttMs: $0.rttMs) }
            if let s = ProbeStats.of(results, now: now, windowSeconds: windowS, rawSeconds: Double(history.rawSeconds)) {
                stats[probe] = s
                window[probe] = results.filter { $0.at > now - windowS }
            }
        }
        let since = history.pauses.last.flatMap { $0.end <= now ? now - $0.end : nil }
        let isPaused = paused(at: now)
        let findings = Verdict.evaluate(VerdictInput(
            probes: probes.compactMap { p in stats[p].map { .init(probe: p, stat: $0) } },
            pathUp: pathUp, viaVPN: viaVPN, captivePortal: captivePortal,
            sincePauseS: isPaused ? 0 : since, windowS: windowS))
        return Snapshot(findings: findings, stats: stats, denied: denied,
                        hops: (traces[link] ?? [:]).filter { traced.contains($0.key) }.mapValues(\.table),
                        window: window, captivePortal: captivePortal, publicAddress: publicAddress,
                        paused: isPaused, now: now)
    }
}
