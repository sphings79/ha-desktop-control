import DesktopControlCore
import Foundation
import MQTTNIO
import NIOCore

/// MQTT 3.1.1 transport on top of MQTT-Nio. Reconnects with backoff after a dropped connection
/// and reports every (re)connect through `onConnectionChange` so the bridge can resubscribe.
final class MQTTNIOTransport: MQTTTransport, @unchecked Sendable {
    var onMessage: ((MQTTMessage) -> Void)?
    var onConnectionChange: ((Bool) -> Void)?

    private let lock = NSLock()
    private var client: MQTTClient?
    private var will: MQTTMessage?
    private var stopping = false
    private var reconnectTask: Task<Void, Never>?

    private static let listenerName = "ha-desktop-control"

    func connect(broker: BrokerConfig, password: String?, clientId: String, will: MQTTMessage) async throws {
        lock.withLock {
            stopping = false
            self.will = will
        }

        let tls: MQTTClient.TLSConfigurationType? = broker.tls
            ? .ts(TSTLSConfiguration(minimumTLSVersion: .tlsV12)) : nil
        let configuration = MQTTClient.Configuration(
            version: .v3_1_1,
            keepAliveInterval: .seconds(60),
            connectTimeout: .seconds(10),
            timeout: .seconds(10),
            userName: broker.username.isEmpty ? nil : broker.username,
            password: (password?.isEmpty ?? true) ? nil : password,
            useSSL: broker.tls,
            tlsConfiguration: tls
        )
        let newClient = MQTTClient(
            host: broker.host,
            port: broker.port,
            identifier: clientId,
            eventLoopGroupProvider: .createNew,
            configuration: configuration
        )
        newClient.addPublishListener(named: Self.listenerName) { [weak self] result in
            guard case .success(let info) = result else { return }
            let text = info.payload.getString(at: info.payload.readerIndex, length: info.payload.readableBytes) ?? ""
            self?.onMessage?(MQTTMessage(topic: info.topicName, payload: text, retain: info.retain))
        }
        newClient.addCloseListener(named: Self.listenerName) { [weak self] _ in
            self?.connectionClosed()
        }
        lock.withLock { client = newClient }

        do {
            try await open(newClient)
        } catch {
            startReconnectLoop() // keep trying in the background, but report the first failure
            throw error
        }
    }

    func subscribe(_ topics: [String]) async throws {
        let client = try currentClient()
        _ = try await client.subscribe(
            to: topics.map { MQTTSubscribeInfo(topicFilter: $0, qos: .atLeastOnce) })
    }

    func publish(_ message: MQTTMessage) async throws {
        let client = try currentClient()
        try await client.publish(
            to: message.topic, payload: ByteBuffer(string: message.payload),
            qos: .atLeastOnce, retain: message.retain)
    }

    func disconnect() async {
        let (task, client): (Task<Void, Never>?, MQTTClient?) = lock.withLock {
            stopping = true
            let pair = (reconnectTask, self.client)
            reconnectTask = nil
            self.client = nil
            return pair
        }

        task?.cancel()
        guard let client else { return }
        client.removeCloseListener(named: Self.listenerName)
        client.removePublishListener(named: Self.listenerName)
        try? await client.disconnect()
        try? await client.shutdown()
        onConnectionChange?(false)
    }

    // MARK: - Internals

    private struct NotConnected: Error, CustomStringConvertible {
        var description: String { "MQTT not connected" }
    }

    private func currentClient() throws -> MQTTClient {
        lock.lock(); defer { lock.unlock() }
        guard let client, client.isActive() else { throw NotConnected() }
        return client
    }

    private func open(_ client: MQTTClient) async throws {
        let will = lock.withLock { self.will }
        let willTuple = will.map {
            (topicName: $0.topic, payload: ByteBuffer(string: $0.payload), qos: MQTTQoS.atMostOnce, retain: $0.retain)
        }
        _ = try await client.connect(cleanSession: true, will: willTuple)
        onConnectionChange?(true)
    }

    private func connectionClosed() {
        let isStopping = lock.withLock { stopping }
        guard !isStopping else { return }
        onConnectionChange?(false)
        startReconnectLoop()
    }

    private func startReconnectLoop() {
        lock.lock()
        guard reconnectTask == nil, !stopping else { lock.unlock(); return }
        reconnectTask = Task { [weak self] in
            var delay: UInt64 = 2
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: delay * 1_000_000_000)
                guard let self, !Task.isCancelled else { return }
                let client = self.lock.withLock { self.client }
                guard let client else { return }
                do {
                    try await self.open(client)
                    self.lock.withLock { self.reconnectTask = nil }
                    return
                } catch {
                    delay = min(delay * 2, 60)
                }
            }
        }
        lock.unlock()
    }
}
