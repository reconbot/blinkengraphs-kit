// rules/verdict.md
import Foundation

public struct Probe: Codable, Hashable, Sendable {
    public static let gateway = "gateway"
    public static let systemDNS = "system-dns"

    public var target: String
    /// `icmp`, `dns`, `tcp:<port>` or `udp:<port>`.
    public var `protocol`: String

    public init(target: String, protocol: String) { self.target = target; self.protocol = `protocol` }
}

public enum FaultDomain: String, Codable, Sendable {
    case localLoad = "LocalLoad", lan = "Lan", isp = "Isp", dns = "Dns", remote = "Remote"
    case icmpFiltering = "IcmpFiltering", selfSaturation = "SelfSaturation", clear = "Clear"
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
    /// Metric values keyed by the spec's Windows names (`CpuTotal`, `NetUp`…). iOS fills only `NetUp`.
    public var sample: [String: Double]?
    public var uploadPeakBps: Double

    public init(probes: [ProbeStat], sample: [String: Double]? = nil, uploadPeakBps: Double = 0) {
        self.probes = probes; self.sample = sample; self.uploadPeakBps = uploadPeakBps
    }

    enum CodingKeys: String, CodingKey { case probes, sample, uploadPeakBps = "upload_peak_bps" }
}

public enum Verdict {
    /// Findings, most severe first. Never empty.
    public static func evaluate(_ input: VerdictInput) -> [Finding] {
        let network = networkFindings(input)
        // Rule 1 stops every other network rule, the DNS rule included (vector lan-down).
        let lanDown = network.first?.domain == .lan && network.first?.severity == .crit
        var findings = network + (lanDown ? [] : dnsFindings(input)) + localFindings(input.sample)
        if findings.isEmpty { return [Finding(domain: .clear, severity: .ok, headline: "All clear")] }
        // Stable: ties keep rule order.
        findings = findings.enumerated()
            .sorted { ($0.element.severity, $0.offset) < ($1.element.severity, $1.offset) }
            .map(\.element)
        return findings
    }

    private typealias P = VerdictInput.ProbeStat

    private static func counts(_ p: P) -> Bool { p.stat.baselineMs != nil || p.stat.loss > 0 }

    private static func networkFindings(_ input: VerdictInput) -> [Finding] {
        let gateway = input.probes.filter { $0.probe.target == Probe.gateway && counts($0) }
        let internet = input.probes.filter {
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
        guard !internet.isEmpty else { return out }

        let best = internet.min { $0.stat.loss < $1.stat.loss }!
        // Ties go to the last Probe, matching Rust's `max_by` in the reference (vector isp-loss).
        let worst = internet.reversed().max { $0.stat.loss < $1.stat.loss }!
        let icmp = internet.filter { $0.probe.protocol == "icmp" }
        let tcp = internet.filter { $0.probe.protocol.hasPrefix("tcp:") }

        // 3–7: the first that matches wins.
        if best.stat.loss >= 0.5 {
            out.append(Finding(domain: .isp, severity: .crit, headline: gateway.isEmpty
                ? "Internet unreachable, gateway not measured: ISP or WAN problem"
                : "Gateway OK, internet unreachable: ISP or WAN problem"))
        } else if !icmp.isEmpty, icmp.allSatisfy({ $0.stat.loss >= 0.5 }), tcp.contains(where: { $0.stat.loss < 0.05 }) {
            out.append(Finding(domain: .icmpFiltering, severity: .warn,
                               headline: "ICMP blocked; TCP gets through: something filters ping"))
        } else if worst.stat.loss >= 0.05, best.stat.loss >= 0.05 {
            let prefix = gateway.isEmpty ? "" : "Gateway OK, "
            out.append(Finding(domain: .isp, severity: worst.stat.loss >= 0.2 ? .crit : .warn,
                               headline: "\(prefix)\(worst.probe.target) losing \(pct(worst.stat.loss)): ISP problem"))
        } else if worst.stat.loss >= 0.05 {
            let good = internet.first { $0.stat.loss < 0.05 && $0.probe.target != worst.probe.target } ?? best
            out.append(Finding(domain: .remote, severity: .warn, headline:
                "\(worst.probe.target) losing \(pct(worst.stat.loss)), \(good.probe.target) fine: problem is on their side"))
        } else if let up = input.sample?["NetUp"], up > 1_000_000, up >= 0.8 * input.uploadPeakBps,
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
    private static func localFindings(_ sample: [String: Double]?) -> [Finding] {
        guard let s = sample else { return [] }
        var out: [Finding] = []
        if let cpu = s["CpuTotal"], cpu >= 90 {
            out.append(Finding(domain: .localLoad, severity: .crit, headline: "CPU pinned at \(whole(cpu))%"))
        }
        if let commit = s["MemCommit"], commit >= 90 {
            out.append(Finding(domain: .localLoad, severity: .crit, headline: "Memory nearly exhausted: commit \(whole(commit))%"))
        } else if let faults = s["MemHardFaults"], faults >= 1000 {
            out.append(Finding(domain: .localLoad, severity: .warn, headline: "Paging heavily: \(whole(faults)) hard faults/s"))
        }
        if let active = s["DiskActive"], let resp = s["DiskResponse"], active >= 90, resp >= 50 {
            out.append(Finding(domain: .localLoad, severity: .warn,
                               headline: "Disk saturated: \(whole(active))% busy, \(whole(resp)) ms response"))
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
