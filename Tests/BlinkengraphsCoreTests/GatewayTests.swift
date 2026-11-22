import Testing
import BlinkengraphsCore

// A Gateway is a router on the path. On IPv6-only cellular, iOS reports its 464XLAT
// translator (192.0.0.0/29, RFC 7335) as the gateway; pinging it measures nothing.
@Test func translatorAddressesAreNotGateways() {
    #expect(Gateway.isRouter("192.0.0.1") == false)
    #expect(Gateway.isRouter("192.0.0.7") == false)
    #expect(Gateway.isRouter("192.0.0.8") == true)
    #expect(Gateway.isRouter("192.168.1.1") == true)
    #expect(Gateway.isRouter("10.0.0.1") == true)
    #expect(Gateway.isRouter("not an address") == false)
}
