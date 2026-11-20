import Foundation

/// Connects the MQTT transport to the rule engine: incoming contact states and commands go
/// to the engine, engine state and "now playing" go back to HA.
@MainActor
public final class MQTTBridge {
    public let topics: Topics
    private let transport: MQTTTransport
    private let engine: RuleEngine
    private let deviceName: String

    private var inbox: AsyncStream<MQTTMessage>.Continuation?
    private var consumer: Task<Void, Never>?
    private var connected = false
    private var nowPlaying = "none"
    private var previousOnChange: ((RuleEngine.Snapshot) -> Void)?

    public var onConnectionChange: ((Bool) -> Void)?

    public init(transport: MQTTTransport, engine: RuleEngine, topics: Topics, deviceName: String) {
        self.transport = transport
        self.engine = engine
        self.topics = topics
        self.deviceName = deviceName
    }

    public func start(broker: BrokerConfig, password: String?) async throws {
        // One consumer keeps messages strictly in arrival order (retained states first).
        let (stream, continuation) = AsyncStream<MQTTMessage>.makeStream()
        inbox = continuation
        consumer = Task { @MainActor [weak self] in
            for await message in stream {
                await self?.route(message)
            }
        }

        transport.onMessage = { message in continuation.yield(message) }
        transport.onConnectionChange = { [weak self] isUp in
            Task { @MainActor in await self?.connectionChanged(isUp) }
        }

        // Chain to an existing handler (the UI's) instead of replacing it.
        let previous = engine.onChange
        previousOnChange = previous
        engine.onChange = { [weak self] snapshot in
            previous?(snapshot)
            Task { @MainActor in await self?.publishState() }
        }

        let will = MQTTMessage(topic: topics.availability, payload: "offline", retain: true)
        try await transport.connect(
            broker: broker, password: password,
            clientId: "ha-desktop-control-\(topics.deviceId)", will: will)
    }

    public func stop() async {
        if connected {
            try? await transport.publish(MQTTMessage(topic: topics.availability, payload: "offline", retain: true))
        }
        await transport.disconnect()
        engine.onChange = previousOnChange
        previousOnChange = nil
        inbox?.finish()
        consumer?.cancel()
        inbox = nil
        consumer = nil
        connected = false
    }

    public func setNowPlaying(_ text: String) async {
        let value = text.isEmpty ? "none" : text
        guard value != nowPlaying else { return }
        nowPlaying = value
        if connected {
            try? await transport.publish(MQTTMessage(topic: topics.nowPlaying, payload: value, retain: true))
        }
    }

    // MARK: - Internals

    private func connectionChanged(_ isUp: Bool) async {
        connected = isUp
        onConnectionChange?(isUp)
        guard isUp else { return }
        do {
            try await transport.subscribe([topics.contactFilter, topics.enabledSet, topics.commandFilter])
            try await transport.publish(MQTTMessage(topic: topics.availability, payload: "online", retain: true))
            for message in Discovery.messages(topics: topics, deviceName: deviceName) {
                try await transport.publish(message)
            }
            await publishState()
            try await transport.publish(MQTTMessage(topic: topics.nowPlaying, payload: nowPlaying, retain: true))
        } catch {
            // The transport reports the drop via onConnectionChange(false) and reconnects.
        }
    }

    private func publishState() async {
        guard connected else { return }
        let snap = engine.snapshot
        try? await transport.publish(
            MQTTMessage(topic: topics.enabledState, payload: snap.enabled ? "ON" : "OFF", retain: true))
        try? await transport.publish(
            MQTTMessage(topic: topics.status, payload: snap.status.rawValue, retain: true))
    }

    func route(_ message: MQTTMessage) async {
        if let source = topics.source(fromContactTopic: message.topic) {
            guard let isOpen = MQTTBridge.parseContact(message.payload) else { return }
            await engine.setContact(source: source, open: isOpen)
        } else if message.topic == topics.enabledSet {
            switch message.payload.uppercased() {
            case "ON": await engine.setEnabled(true)
            case "OFF": await engine.setEnabled(false)
            default: break
            }
        } else if let command = topics.commandName(fromTopic: message.topic) {
            switch command {
            case "pause_media": await engine.manualPause()
            case "restore": await engine.manualRestore()
            default: break
            }
        }
    }

    /// `open`/`on`/`true`/`1` -> open, `closed`/`off`/`false`/`0` -> closed, anything else is ignored.
    public static func parseContact(_ payload: String) -> Bool? {
        switch payload.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "open", "on", "true", "1": return true
        case "closed", "off", "false", "0": return false
        default: return nil
        }
    }
}
