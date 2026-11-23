// rules/verdict.md
import Foundation

public struct Probe: Codable, Hashable, Sendable {
    public static let gateway = "gateway"
    public static let systemDNS = "system-dns"

    public var target: String
    /// `icmp`, `dns`, `tcp:<port>` or `udp:<port>`.
    public var `protocol`: String

    public init(target: String, protocol: String) { self.target = target; self.protocol = `protocol` }

    /// The Target's IP version, when it is an address literal. Names like `gateway` have none.
    public var isIPv6: Bool? {
        if target.contains(":") { return true }
        let parts = target.split(separator: ".")
        return parts.count == 4 && parts.allSatisfy { UInt8($0) != nil } ? false : nil
    }
}

public enum FaultDomain: String, Codable, Sendable {
    case localLoad = "LocalLoad", lan = "Lan", isp = "Isp", dns = "Dns", remote = "Remote"
    case icmpFiltering = "IcmpFiltering", selfSaturation = "SelfSaturation", offline = "Offline", vpn = "Vpn"
    case captivePortal = "CaptivePortal", clear = "Clear", paused = "Paused"
}

/// Declared most severe first; `Comparable` sorts in that order.
public enum Severity: String, Codable, Comparable, Sendable {
    case crit = "Crit", warn = "Warn", ok = "Ok"

    private var rank: Int { switch self { case .crit: 0; case .warn: 1; case .ok: 2 } }
    public static func < (a: Self, b: Self) -> Bool { a.rank < b.rank }
}

public struct Finding: Codable, Equatable, Sendable {
    public var domain: FaultDomain
    public var severity: Severity
    public var headline: String

    public init(domain: FaultDomain, severity: Severity, headline: String) {
        self.domain = domain; self.severity = severity; self.headline = headline
    }
}

public struct VerdictInput: Codable, Sendable {
    public struct ProbeStat: Codable, Sendable {
        public var probe: Probe
        public var stat: ProbeStats
        public init(probe: Probe, stat: ProbeStats) { self.probe = probe; self.stat = stat }
    }

    /// Denied Probes are absent.
    public var probes: [ProbeStat]
    /// The last Sample. iOS fills only `netUp`.
    public var sample: Sample?
    public var uploadPeakBps: Double
    /// Whether the OS reports any usable network path; absent in a vector means true.
    public var pathUp: Bool
    /// Whether the traffic goes through a VPN tunnel; absent in a vector means false.
    public var viaVPN: Bool
    /// Whether a sign-in page holds back the internet; absent in a vector means false.
    public var captivePortal: Bool
    /// Seconds since the last Pause ended; nil when there has been none.
    public var sincePauseS: Double?
    /// `history.recent_window_s`: how long after a Pause "Resuming measurements" can show.
    public var windowS: Double

    public init(probes: [ProbeStat], sample: Sample? = nil, uploadPeakBps: Double = 0,
                pathUp: Bool = true, viaVPN: Bool = false, captivePortal: Bool = false,
                sincePauseS: Double? = nil, windowS: Double = 30) {
        self.probes = probes; self.sample = sample; self.uploadPeakBps = uploadPeakBps
        self.pathUp = pathUp; self.viaVPN = viaVPN; self.captivePortal = captivePortal
        self.sincePauseS = sincePauseS; self.windowS = windowS
    }

    enum CodingKeys: String, CodingKey {
        case probes, sample, uploadPeakBps = "upload_peak_bps", pathUp = "path_up", viaVPN = "via_vpn"
        case captivePortal = "captive_portal", sincePauseS = "since_pause_s"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        probes = try c.decode([ProbeStat].self, forKey: .probes)
        sample = try c.decodeIfPresent(Sample.self, forKey: .sample)
        uploadPeakBps = try c.decodeIfPresent(Double.self, forKey: .uploadPeakBps) ?? 0
        pathUp = try c.decodeIfPresent(Bool.self, forKey: .pathUp) ?? true
        viaVPN = try c.decodeIfPresent(Bool.self, forKey: .viaVPN) ?? false
        captivePortal = try c.decodeIfPresent(Bool.self, forKey: .captivePortal) ?? false
        sincePauseS = try c.decodeIfPresent(Double.self, forKey: .sincePauseS)
        windowS = 30
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(probes, forKey: .probes)
        try c.encodeIfPresent(sample, forKey: .sample)
        try c.encode(uploadPeakBps, forKey: .uploadPeakBps)
        try c.encode(pathUp, forKey: .pathUp)
        try c.encode(viaVPN, forKey: .viaVPN)
        try c.encode(captivePortal, forKey: .captivePortal)
        try c.encodeIfPresent(sincePauseS, forKey: .sincePauseS)
    }
}

public enum Verdict {
    /// Findings, most severe first. Never empty.
    public static func evaluate(_ input: VerdictInput) -> [Finding] {
        var findings: [Finding]
        if !input.pathUp {
            // With no network path, Offline replaces every network and DNS rule.
            findings = [Finding(domain: .offline, severity: .crit, headline: "No network connection")]
        } else if resuming(input) {
            // Right after a Pause no Probe has stats yet: a resume never reads as a fault.
            findings = [Finding(domain: .paused, severity: .ok, headline: "Resuming measurements")]
        } else {
            let network = networkFindings(input)
            // Rule 1 stops every other network rule, the DNS rule included (vector lan-down).
            let lanDown = network.first?.domain == .lan && network.first?.severity == .crit
            // A portal hijacks DNS too, so the DNS rule doesn't run behind one.
            findings = network + (lanDown || input.captivePortal ? [] : dnsFindings(input))
        }
        findings += localFindings(input.sample)
        if findings.isEmpty { return [Finding(domain: .clear, severity: .ok, headline: "All clear")] }
        // Stable: ties keep rule order.
        findings = findings.enumerated()
            .sorted { ($0.element.severity, $0.offset) < ($1.element.severity, $1.offset) }
            .map(\.element)
        return findings
    }

    private typealias P = VerdictInput.ProbeStat

    /// rules/verdict.md, "Resuming": no Gateway or Internet Probe has stats, within a window of a Pause.
    private static func resuming(_ input: VerdictInput) -> Bool {
        guard let since = input.sincePauseS, since < input.windowS else { return false }
        return !input.probes.contains { $0.probe.target != Probe.systemDNS && $0.probe.protocol != "dns" }
    }

    private static func counts(_ p: P) -> Bool { p.stat.baselineMs != nil || p.stat.loss > 0 }

    private static func networkFindings(_ input: VerdictInput) -> [Finding] {
        let gateway = input.probes.filter { $0.probe.target == Probe.gateway && counts($0) }
        var internet = input.probes.filter {
            $0.probe.target != Probe.gateway && $0.probe.target != Probe.systemDNS
                && $0.probe.protocol != "dns" && counts($0)
        }
        let gatewayLoss = gateway.map(\.stat.loss).max()
        var out: [Finding] = []

        // 1
        if let g = gatewayLoss, g >= 0.5, internet.allSatisfy({ $0.stat.loss >= 0.5 }) {
            return [Finding(domain: .lan, severity: .crit, headline: "Gateway unreachable: Wi-Fi or LAN problem")]
        }
        // 2
        if let g = gatewayLoss, g >= 0.05 {
            out.append(Finding(domain: .lan, severity: .warn, headline: "Local network unstable: gateway losing \(pct(g))"))
        }
        // A sign-in page explains Internet loss; the family rules and rules 3–7 don't run.
        if input.captivePortal {
            return out + [Finding(domain: .captivePortal, severity: .warn, headline: "Sign-in page is blocking the internet")]
        }
        // One address family down while the other works: say so, then judge only the working one,
        // so a broken IPv6 path never reads as a remote host's problem.
        let v4 = internet.filter { $0.probe.isIPv6 == false }
        let v6 = internet.filter { $0.probe.isIPv6 == true }
        func bestLoss(_ ps: [P]) -> Double { ps.map(\.stat.loss).min() ?? 1 }
        func works(_ ps: [P]) -> Bool { ps.contains { $0.stat.loss < 0.05 } }
        // Through a VPN, what would blame the ISP or ping filtering is the tunnel or its exit.
        let vpn = input.viaVPN
        let blame: FaultDomain = vpn ? .vpn : .isp
        if !v4.isEmpty && !v6.isEmpty {
            if bestLoss(v6) >= 0.5 && works(v4) {
                out.append(Finding(domain: blame, severity: .warn, headline: vpn
                    ? "IPv6 broken; IPv4 works: VPN has no IPv6 route"
                    : "IPv6 broken; IPv4 works: ISP or router IPv6 problem"))
                internet = v4
            } else if bestLoss(v4) >= 0.5 && works(v6) {
                out.append(Finding(domain: blame, severity: .crit, headline: vpn
                    ? "IPv4 broken; IPv6 works: VPN has no IPv4 route"
                    : "IPv4 broken; IPv6 works: ISP or router IPv4 problem"))
                internet = v6
            }
        }

        guard !internet.isEmpty else { return out }

        // Worst and best compare loss as shown, a whole percent; among equals the first in
        // Probe Group order wins, so the headline doesn't flip between refreshes.
        func shown(_ p: P) -> Int { Int((p.stat.loss * 100).rounded()) }
        let best = internet.first { p in internet.allSatisfy { shown(p) <= shown($0) } }!
        let worst = internet.first { p in internet.allSatisfy { shown(p) >= shown($0) } }!
        let icmp = internet.filter { $0.probe.protocol == "icmp" }
        let tcp = internet.filter { $0.probe.protocol.hasPrefix("tcp:") }

        // 3–7: the first that matches wins.
        if best.stat.loss >= 0.5 && vpn {
            out.append(Finding(domain: .vpn, severity: .crit,
                               headline: "Internet unreachable through VPN: VPN or its exit problem"))
        } else if best.stat.loss >= 0.5 {
            out.append(Finding(domain: .isp, severity: .crit, headline: gateway.isEmpty
                ? "Internet unreachable, gateway not measured: ISP or WAN problem"
                : "Gateway OK, internet unreachable: ISP or WAN problem"))
        } else if !icmp.isEmpty, icmp.allSatisfy({ $0.stat.loss >= 0.5 }), tcp.contains(where: { $0.stat.loss < 0.05 }) {
            out.append(vpn
                ? Finding(domain: .vpn, severity: .warn, headline: "ICMP blocked; TCP gets through: VPN filters ping")
                : Finding(domain: .icmpFiltering, severity: .warn,
                          headline: "ICMP blocked; TCP gets through: something filters ping"))
        } else if worst.stat.loss >= 0.05, best.stat.loss >= 0.05 {
            let prefix = gateway.isEmpty ? "" : "Gateway OK, "
            out.append(Finding(domain: blame, severity: worst.stat.loss >= 0.2 ? .crit : .warn, headline: vpn
                ? "\(worst.probe.target) losing \(pct(worst.stat.loss)) through VPN: VPN or its exit problem"
                : "\(prefix)\(worst.probe.target) losing \(pct(worst.stat.loss)): ISP problem"))
        } else if worst.stat.loss >= 0.05 {
            let good = internet.first { $0.stat.loss < 0.05 && $0.probe.target != worst.probe.target } ?? best
            out.append(Finding(domain: .remote, severity: .warn, headline:
                "\(worst.probe.target) losing \(pct(worst.stat.loss)), \(good.probe.target) fine: problem is on their side"))
        } else if let up = input.sample?.netUp, up > 1_000_000, up >= 0.8 * input.uploadPeakBps,
                  let p = internet.first(where: { p in
                      guard let rtt = p.stat.rttMs, let base = p.stat.baselineMs else { return false }
                      return rtt > 3 * base && rtt - base > 30
                  }) {
            out.append(Finding(domain: .selfSaturation, severity: .warn, headline:
                "Upload saturated (\(bytes(up))/s): \(ms(p.stat.rttMs!)) ms vs \(ms(p.stat.baselineMs!)) ms normal"))
        }
        return out
    }

    private static func dnsFindings(_ input: VerdictInput) -> [Finding] {
        let dns = input.probes.filter { $0.probe.protocol == "dns" }
        func bad(_ p: P) -> Bool { p.stat.loss >= 0.3 || (p.stat.rttMs ?? 0) > 250 }
        guard let system = dns.first(where: { $0.probe.target == Probe.systemDNS }), bad(system) else { return [] }
        var headline = system.stat.loss >= 0.3
            ? "Your DNS server is losing \(pct(system.stat.loss))"
            : "Your DNS server is slow (\(ms(system.stat.rttMs!)) ms)"
        if let fine = dns.first(where: { $0.probe.target != Probe.systemDNS && !bad($0) }) {
            headline += "; \(fine.probe.target) answers fine"
        }
        return [Finding(domain: .dns, severity: .warn, headline: headline)]
    }

    /// Windows-named Metrics; iOS never supplies them, but implementing them keeps every vector passing.
    /// rules/verdict.md, "Local rules".
    private static func localFindings(_ sample: Sample?) -> [Finding] {
        guard let s = sample else { return [] }
        var out: [Finding] = []
        if let cpu = s.cpuBusy, cpu >= 90 {
            out.append(Finding(domain: .localLoad, severity: .crit, headline: "CPU pinned at \(whole(cpu))%"))
        }
        if s.memPressure == .critical {
            out.append(Finding(domain: .localLoad, severity: .crit, headline: "Memory nearly exhausted"))
        } else if let rate = s.memPageIns, rate >= Sample.heavyPageInsBps {
            out.append(Finding(domain: .localLoad, severity: .warn, headline: "Paging heavily: \(bytes(rate))/s from disk"))
        }
        // The busiest saturated disk; on a tie, the first listed.
        var worst: Sample.Disk?
        for d in s.disks where d.busy >= 90 && d.responseMs >= 50 && d.busy > (worst?.busy ?? -1) { worst = d }
        if let disk = worst {
            out.append(Finding(domain: .localLoad, severity: .warn,
                               headline: "Disk saturated: \(whole(disk.busy))% busy, \(whole(disk.responseMs)) ms response"))
        }
        return out
    }

    // Formatting
    static func whole(_ x: Double) -> String { String(Int(x.rounded())) }
    static func pct(_ fraction: Double) -> String { "\(whole(fraction * 100))%" }
    static func ms(_ x: Double) -> String { whole(x) }
    static func bytes(_ b: Double) -> String {
        switch b {
        case 1e9...: String(format: "%.1f GB", b / 1e9)
        case 1e6...: String(format: "%.1f MB", b / 1e6)
        case 1e3...: "\(whole(b / 1e3)) kB"
        default: "\(whole(b)) B"
        }
    }
}
