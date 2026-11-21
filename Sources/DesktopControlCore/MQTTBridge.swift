import Foundation

/// Connects the MQTT transport to the rule engine: incoming contact states and commands go
/// to the engine, engine state and "now playing" go back to HA.
@MainActor
public final class MQTTBridge {
    public let topics: Topics
    private let transport: MQTTTransport
    private let engine: RuleEngine
    private let deviceName: String
    private let audio: AudioControlling?

    private var inbox: AsyncStream<MQTTMessage>.Continuation?
    private var consumer: Task<Void, Never>?
    private var connected = false
    private var nowPlaying = "none"
    private var previousOnChange: ((RuleEngine.Snapshot) -> Void)?
    private var lastAudio: AudioOutputState?

    public var onConnectionChange: ((Bool) -> Void)?
    /// Called for every valid popup request from Home Assistant.
    public var onPopup: ((PopupRequest) -> Void)?

    public init(transport: MQTTTransport, engine: RuleEngine, topics: Topics, deviceName: String, audio: AudioControlling? = nil) {
        self.audio = audio
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

        audio?.onChange = { [weak self] in
            Task { @MainActor in await self?.publishAudio() }
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
        audio?.onChange = nil
        lastAudio = nil
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
            var filters = [topics.contactFilter, topics.enabledSet, topics.commandFilter, topics.popup]
            if audio != nil { filters.append(topics.audioSetFilter) }
            try await transport.subscribe(filters)
            try await transport.publish(MQTTMessage(topic: topics.availability, payload: "online", retain: true))
            lastAudio = nil
            let audioState = audio?.state()
            for message in Discovery.messages(topics: topics, deviceName: deviceName, audioOutputs: audioState.map(Self.options)) {
                try await transport.publish(message)
            }
            await publishState()
            await publishAudio()
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

    /// Select options: all output devices, always including the current one.
    private static func options(_ state: AudioOutputState) -> [String] {
        state.available.contains(state.deviceName) ? state.available : state.available + [state.deviceName]
    }

    private func publishAudio() async {
        guard connected, let audio else { return }
        let state = audio.state()
        let previous = lastAudio
        guard state != previous else { return }
        lastAudio = state
        if let previous, Self.options(previous) != Self.options(state) {
            for message in Discovery.messages(topics: topics, deviceName: deviceName, audioOutputs: Self.options(state))
            where message.topic.contains("/audio_") {
                try? await transport.publish(message)
            }
        }
        func send(_ topic: String, _ payload: String) async {
            try? await transport.publish(MQTTMessage(topic: topic, payload: payload, retain: true))
        }
        if previous?.deviceName != state.deviceName { await send(topics.audioOutput, state.deviceName) }
        if previous?.kind != state.kind { await send(topics.audioOutputType, state.kind.rawValue) }
        // "None" resets a number entity to unknown (devices without software volume).
        if previous?.volume != state.volume { await send(topics.audioVolume, state.volume.map(String.init) ?? "None") }
        if previous?.muted != state.muted { await send(topics.audioMuted, state.muted == true ? "ON" : "OFF") }
    }

    private func routeAudio(_ name: String, _ payload: String) async {
        guard let audio else { return }
        let text = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        switch name {
        case "volume":
            guard let value = Double(text), value.isFinite else { return }
            audio.setVolume(Int(min(100, max(0, value)).rounded()))
        case "muted":
            switch text.uppercased() {
            case "ON": audio.setMuted(true)
            case "OFF": audio.setMuted(false)
            default: return
            }
        case "output":
            audio.selectOutput(named: text)
        default: return
        }
        await publishAudio()
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
        } else if message.topic == topics.popup {
            // A retained popup would replay on every reconnect, so only live messages count.
            if !message.retain, let request = PopupRequest.parse(message.payload) { onPopup?(request) }
        } else if let name = topics.audioSetName(fromTopic: message.topic) {
            await routeAudio(name, message.payload)
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
