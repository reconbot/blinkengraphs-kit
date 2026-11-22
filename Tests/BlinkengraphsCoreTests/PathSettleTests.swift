import BlinkengraphsCore
import Testing

private let wifi = PathSettle.Route(link: Link(interface: "en0", gateway: "192.168.1.1"), up: true, ipv4: true, ipv6: true)
private let cell = PathSettle.Route(link: Link(interface: "pdp_ip0", gateway: nil), up: true, ipv4: false, ipv6: true)

@Test func probingWaitsForTheFirstPathReport() {
    let s = PathSettle(quiet: 1)
    #expect(!s.ready(at: 100))
}

@Test func probingStartsOnceTheRouteHasHeldForTheQuietPeriod() {
    var s = PathSettle(quiet: 1)
    s.report(wifi, at: 100)
    #expect(!s.ready(at: 100.5))
    #expect(s.ready(at: 101))
}

@Test func aNewRouteRestartsTheWait() {
    var s = PathSettle(quiet: 1)
    s.report(wifi, at: 100)
    s.report(cell, at: 105)
    #expect(!s.ready(at: 105.9))
    s.report(cell, at: 105.5) // the same route again, e.g. only link quality changed
    #expect(s.ready(at: 106))
}

@Test func noPathMeansNoProbes() {
    var s = PathSettle(quiet: 1)
    s.report(.init(link: wifi.link, up: false, ipv4: false, ipv6: false), at: 100)
    #expect(!s.ready(at: 200))
}

@Test func resumingWaitsForAFreshReport() {
    var s = PathSettle(quiet: 1)
    s.report(wifi, at: 100)
    s.reset()
    #expect(!s.ready(at: 300))
    s.report(wifi, at: 300)
    #expect(s.ready(at: 301))
}
