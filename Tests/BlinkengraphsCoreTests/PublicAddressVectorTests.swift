import Testing
import BlinkengraphsCore

private struct PublicAddressVector: Decodable {
    struct Input: Decodable {
        var family: IPFamily
        var dns_txt: [String]?
        var https_body: String?
    }
    var input: Input
    var expected: PublicAddressReading
}

@Test func publicAddressVectors() throws {
    for (name, v) in try Spec.vectors("public-address", as: PublicAddressVector.self) {
        let got = PublicAddress.read(family: v.input.family, dnsTXT: v.input.dns_txt, httpsBody: v.input.https_body)
        #expect(got == v.expected, "\(name)")
    }
}
