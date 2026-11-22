import Foundation

/// Masks what identifies a person in a shared report: their public addresses and the names of
/// their routers. Targets and private address space identify nobody, so they stay.
public struct Redactor: Sendable {
    public let targets: Set<String>

    public init(targets: Set<String>) { self.targets = targets }

    public func address(_ a: String) -> String {
        if targets.contains(a) || Self.isPrivate(a) { return a }
        if a.contains(":") {
            // Keep the /32 an ISP is allocated; a household's /48 or /56 identifies it.
            let groups = a.split(separator: ":", omittingEmptySubsequences: false)
            return groups.prefix(2).joined(separator: ":") + "::x"
        }
        let octets = a.split(separator: ".")
        return octets.count == 4 ? octets.prefix(3).joined(separator: ".") + ".x" : "x"
    }

    /// Names reveal a home domain or a carrier's city; only a Target's name stays.
    public func name(_ name: String, of addr: String) -> String? {
        targets.contains(addr) ? name : nil
    }

    static func isPrivate(_ a: String) -> Bool {
        if a.contains(":") {
            let first = a.lowercased().split(separator: ":").first.flatMap { UInt16($0, radix: 16) } ?? 0
            return first & 0xFE00 == 0xFC00 || first & 0xFFC0 == 0xFE80 // ULA fc00::/7, link-local fe80::/10
        }
        let o = a.split(separator: ".").compactMap { UInt8($0) }
        guard o.count == 4 else { return false }
        return o[0] == 10 || (o[0] == 172 && (16...31).contains(o[1])) || (o[0] == 192 && o[1] == 168)
            || (o[0] == 100 && (64...127).contains(o[1])) || (o[0] == 169 && o[1] == 254) || o[0] == 127
            || (o[0] == 192 && o[1] == 0 && o[2] == 0)
    }
}

/// Everything a report shows, gathered by the app.
public struct ReportInput: Sendable {
    public var generatedAt: Date
    public var header: [String]
    public var verdict: [Finding]
    public var connection: [(String, String)]
    public var probes: [Probe: ProbeStats]
    public var denied: Set<Probe>
    public var hops: [String: [HopRow]]
    public var names: [String: String]
    public var targets: Set<String>

    public init(generatedAt: Date, header: [String], verdict: [Finding], connection: [(String, String)],
                probes: [Probe: ProbeStats], denied: Set<Probe>, hops: [String: [HopRow]],
                names: [String: String], targets: Set<String>) {
        self.generatedAt = generatedAt; self.header = header; self.verdict = verdict
        self.connection = connection; self.probes = probes; self.denied = denied
        self.hops = hops; self.names = names; self.targets = targets
    }
}

/// A plain-text snapshot of the app's state, laid out like `mtr -r`, for pasting into a bug report.
public enum Report {
    public static func text(_ r: ReportInput, redact: Bool) -> String {
        let red = Redactor(targets: r.targets)
        func addr(_ a: String) -> String { redact ? red.address(a) : a }
        func host(_ a: String) -> String {
            let name = r.names[a].flatMap { redact ? red.name($0, of: a) : $0 }
            return name.map { "\($0) (\(addr(a)))" } ?? addr(a)
        }
        func ms(_ v: Double?) -> String { v.map { String(format: "%.1f", $0) } ?? "-" }
        func pct(_ v: Double) -> String { "\(Int((v * 100).rounded()))%" }
        func pad(_ s: String, _ n: Int) -> String { s.count >= n ? s : s + String(repeating: " ", count: n - s.count) }
        func right(_ s: String, _ n: Int) -> String { s.count >= n ? s : String(repeating: " ", count: n - s.count) + s }

        let stamp = ISO8601DateFormatter().string(from: r.generatedAt)
        var out = ["blinkengraphs report \(stamp)", r.header.joined(separator: " · ")]
        if redact { out.append("redacted: public addresses masked, names hidden except Targets") }

        out += ["", "Verdict"]
        out += r.verdict.map { "  \($0.severity.rawValue)  \($0.domain.rawValue)  \($0.headline)" }

        out += ["", "Connection"]
        out += r.connection.map { label, value in
            let shown = label == "Gateway" && value != "—" ? addr(value) : value
            return "  \(pad(label, 14))\(shown)"
        }

        out += ["", "Probes  (window: loss, rtt, baseline, jitter in ms)"]
        let all = Set(r.probes.keys).union(r.denied).sorted { ($0.target, $0.protocol) < ($1.target, $1.protocol) }
        for p in all {
            let name = pad("\(addr(p.target)) \(p.protocol)", 34)
            if r.denied.contains(p) {
                out.append("  \(name)denied")
            } else if let s = r.probes[p] {
                out.append("  \(name)\(pad(pct(s.loss), 6))\(pad(ms(s.rttMs), 8))\(pad(ms(s.baselineMs), 8))\(ms(s.jitterMs))")
            }
        }

        for target in r.hops.keys.sorted() {
            out += ["", "Hop Trace to \(addr(target))", "   #  \(pad("host", 46))loss   last    avg   best  worst"]
            for h in r.hops[target] ?? [] {
                let line = "  \(String(format: "%2d", h.ttl))  \(pad(h.addr.map(host) ?? "*", 46))"
                    + pad(pct(h.loss), 5) + [h.lastMs, h.avgMs, h.bestMs, h.worstMs].map { right(ms($0), 6) }.joined(separator: " ")
                out.append(line)
            }
        }
        return out.joined(separator: "\n") + "\n"
    }
}
