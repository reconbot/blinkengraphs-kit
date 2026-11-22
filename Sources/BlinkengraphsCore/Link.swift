// CONTEXT.md "Link"; spec rules/history.md, "Archives": a Link is named by its interface and
// Gateway, so the Access Points behind one Gateway share its History.

/// One adapter's attachment to a network: its interface and its Gateway, when it has one.
/// Two networks whose Gateways share an address are one Link until the Access Point is known.
public struct Link: Hashable, Sendable, Codable {
    public var interface: String
    public var gateway: String?

    public init(interface: String, gateway: String?) {
        self.interface = interface
        self.gateway = gateway
    }
}
