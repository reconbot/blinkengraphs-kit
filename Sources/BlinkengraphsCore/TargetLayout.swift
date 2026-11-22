// How a Probe Group's Targets appear: names, IP versions, which Probe a graph charts, Probe order
// and colour slots. One place for the screen, the report and redaction to agree on.

public struct TargetLayout: Equatable, Sendable {
    public struct Entry: Equatable, Sendable, Identifiable {
        public var target: String
        public var name: String
        /// Nil for names, `gateway` and `system-dns`: their IP version isn't known up front.
        public var family: IPFamily?
        /// ICMP, else TCP. DNS answers time a resolver, not the path, so it is never charted.
        public var charted: Probe?
        /// ICMP, TCP, UDP, then DNS.
        public var probes: [Probe]
        /// The Target's row in the group, so its colour stays put when others change.
        public var slot: Int
        public var traced: Bool
        public var id: String { target }
    }

    public var entries: [Entry]

    public init(_ group: Defaults.ProbeGroup) {
        let rank = { (p: Probe) in
            p.protocol == "icmp" ? 0 : p.protocol.hasPrefix("tcp:") ? 1 : p.protocol.hasPrefix("udp:") ? 2 : 3
        }
        entries = group.targets.enumerated().map { slot, row in
            let probes = group.probes.filter { $0.target == row.target }.sorted { rank($0) < rank($1) }
            let v6 = Probe(target: row.target, protocol: "").isIPv6
            return Entry(target: row.target, name: Self.name(row.target), family: v6.map { $0 ? .ipv6 : .ipv4 },
                         charted: probes.first { rank($0) <= 1 }, probes: probes, slot: slot,
                         traced: row.trace && row.traceable)
        }
    }

    public static func name(_ target: String) -> String {
        switch target {
        case Probe.gateway: "Gateway"
        case Probe.systemDNS: "System DNS"
        default: target
        }
    }

    /// The keyword Targets, in the order the editor offers them.
    public static let presets = [Probe.gateway, Probe.systemDNS]

    /// Presets that complete what's typed, matched on the keyword or its name ("sys" and "system d"
    /// both offer `system-dns`). Empty input offers every preset; a finished keyword offers none.
    public static func presets(completing input: String) -> [String] {
        let typed = input.trimmingCharacters(in: .whitespaces).lowercased()
        return presets.filter { $0 != typed && ($0.hasPrefix(typed) || name($0).lowercased().hasPrefix(typed)) }
    }

    public func entry(_ target: String) -> Entry? { entries.first { $0.target == target } }

    /// Targets with a charted Probe, in group order.
    public var charted: [Entry] { entries.filter { $0.charted != nil } }

    /// Traced Targets: IPv4, then IPv6, then names.
    public var traced: [Entry] {
        let order = { (e: Entry) in e.family == .ipv4 ? 0 : e.family == .ipv6 ? 1 : 2 }
        return entries.filter(\.traced).enumerated()
            .sorted { (order($0.element), $0.offset) < (order($1.element), $1.offset) }.map(\.element)
    }

    /// Every Target as configured; a redacted report keeps these.
    public var targets: Set<String> { Set(entries.map(\.target)) }
    /// The Targets that are address literals.
    public var addresses: Set<String> { Set(entries.filter { $0.family != nil }.map(\.target)) }
}
