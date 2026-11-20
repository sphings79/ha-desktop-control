import DesktopControlCore

/// Placeholder until the MQTT client implementation is chosen.
final class UnavailableTransport: MQTTTransport {
    struct NotAvailable: Error, CustomStringConvertible {
        var description: String { "No MQTT client implementation yet" }
    }

    var onMessage: ((MQTTMessage) -> Void)?
    var onConnectionChange: ((Bool) -> Void)?

    func connect(broker: BrokerConfig, password: String?, clientId: String, will: MQTTMessage) async throws {
        throw NotAvailable()
    }
    func subscribe(_ topics: [String]) async throws { throw NotAvailable() }
    func publish(_ message: MQTTMessage) async throws { throw NotAvailable() }
    func disconnect() async {}
}
