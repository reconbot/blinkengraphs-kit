// ADR 0013: Probes start once the network path has settled, so the first results after a
// network change or a return to the app don't measure the switch itself.

/// Whether the path has settled: the OS has reported a working route, and that route hasn't
/// changed for `quiet` seconds.
public struct PathSettle: Sendable {
    /// What a Probe's result depends on. Other path changes (link quality, cost) don't count.
    public struct Route: Equatable, Sendable {
        public var link: Link, up: Bool, ipv4: Bool, ipv6: Bool
        public init(link: Link, up: Bool, ipv4: Bool, ipv6: Bool) {
            self.link = link; self.up = up; self.ipv4 = ipv4; self.ipv6 = ipv6
        }
    }

    public let quiet: Double
    private var route: Route?
    private var since = 0.0

    public init(quiet: Double) { self.quiet = quiet }

    public mutating func report(_ route: Route, at now: Double) {
        guard route != self.route else { return }
        self.route = route
        since = now
    }

    /// Forgets the route, as after a pause: the path may have changed unseen.
    public mutating func reset() { route = nil }

    public func ready(at now: Double) -> Bool {
        guard let route, route.up else { return false }
        return now - since >= quiet
    }
}
