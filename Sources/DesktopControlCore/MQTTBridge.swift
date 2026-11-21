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
    private let sensors: SensorReading?
    private let mac: MacControlling?
    private let commandRunner: CommandRunning?
    private let sensorInterval: TimeInterval

    private var inbox: AsyncStream<MQTTMessage>.Continuation?
    private var consumer: Task<Void, Never>?
    private var connected = false
    private var nowPlaying = "none"
    private var previousOnChange: ((RuleEngine.Snapshot) -> Void)?
    private var lastAudio: AudioOutputState?
    private var desiredConfigTopics: Set<String> = []
    private var lastSensors: SensorSnapshot?
    private var lastSensorActiveApp = false
    private var sensorTask: Task<Void, Never>?
    private var commandRunning = false

    public var onConnectionChange: ((Bool) -> Void)?
    /// Called for every valid popup request from Home Assistant.
    public var onPopup: ((PopupRequest) -> Void)?

    public init(
        transport: MQTTTransport, engine: RuleEngine, topics: Topics, deviceName: String,
        audio: AudioControlling? = nil, sensors: SensorReading? = nil, mac: MacControlling? = nil,
        commands: CommandRunning? = nil, sensorInterval: TimeInterval = 5
    ) {
        self.audio = audio
        self.sensors = sensors
        self.mac = mac
        self.commandRunner = commands
        self.sensorInterval = sensorInterval
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
        sensorTask?.cancel()
        sensorTask = nil
        lastSensors = nil
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

    /// The popup action button the user clicked, for an HA automation to react to.
    public func publishAction(popupId: String, action: String) async {
        guard connected else { return }
        let payload = Discovery.json(["id": popupId, "action": action])
        try? await transport.publish(MQTTMessage(topic: topics.action, payload: payload, retain: false))
    }

    /// Call after the configuration changed: republishes discovery (adding and removing entities).
    public func configChanged() async {
        guard connected else { return }
        try? await publishDiscovery()
        await publishSensors()
    }

    // MARK: - Internals

    private func discoveryMessages() -> [MQTTMessage] {
        let config = engine.config
        let options = DiscoveryOptions(
            audioOutputs: audio.map { Self.options($0.state()) },
            sensors: sensors != nil,
            activeApp: config.sensors.activeApp,
            macControl: mac == nil ? MacControlConfig() : config.macControl,
            commands: (commandRunner != nil && config.commandsEnabled) ? config.commands.filter(\.isValid) : [])
        return Discovery.messages(topics: topics, deviceName: deviceName, options: options)
    }

    /// Publishes all entity configs and clears entities that are no longer wanted.
    private func publishDiscovery() async throws {
        let messages = discoveryMessages()
        let now = Set(messages.map(\.topic))
        let removed = desiredConfigTopics.subtracting(now)
        desiredConfigTopics = now
        for topic in removed.sorted() {
            try await transport.publish(MQTTMessage(topic: topic, payload: "", retain: true))
        }
        for message in messages { try await transport.publish(message) }
    }

    private func connectionChanged(_ isUp: Bool) async {
        connected = isUp
        onConnectionChange?(isUp)
        guard isUp else { return }
        do {
            // Fix the wanted set before subscribing, so stale retained configs can be told apart.
            desiredConfigTopics = Set(discoveryMessages().map(\.topic))
            var filters = [topics.contactFilter, topics.enabledSet, topics.commandFilter, topics.popup, topics.discoveryConfigFilter]
            if audio != nil { filters.append(topics.audioSetFilter) }
            try await transport.subscribe(filters)
            try await transport.publish(MQTTMessage(topic: topics.availability, payload: "online", retain: true))
            lastAudio = nil
            lastSensors = nil
            try await publishDiscovery()
            await publishState()
            await publishAudio()
            startSensors()
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
            try? await publishDiscovery()
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

    // MARK: Sensors

    private func startSensors() {
        sensorTask?.cancel()
        guard sensors != nil else { return }
        let interval = sensorInterval
        sensorTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                await self?.publishSensors()
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }
        }
    }

    private func publishSensors() async {
        guard connected, let sensors else { return }
        let includeApp = engine.config.sensors.activeApp
        let now = sensors.read(includeActiveApp: includeApp)
        let previous = lastSensors
        let appToggled = includeApp != lastSensorActiveApp
        guard now != previous || appToggled else { return }
        lastSensors = now
        lastSensorActiveApp = includeApp

        func send(_ name: String, _ payload: String) async {
            try? await transport.publish(MQTTMessage(topic: topics.sensor(name), payload: payload, retain: true))
        }
        if previous?.cameraInUse != now.cameraInUse { await send("camera_in_use", now.cameraInUse ? "ON" : "OFF") }
        if previous?.microphoneInUse != now.microphoneInUse { await send("microphone_in_use", now.microphoneInUse ? "ON" : "OFF") }
        if previous?.screenLocked != now.screenLocked { await send("screen_locked", now.screenLocked ? "ON" : "OFF") }
        // Idle time grows every second; publish when activity resets it or every 30 s.
        if let previous {
            if now.idleSeconds < previous.idleSeconds || now.idleSeconds >= previous.idleSeconds + 30 {
                await send("idle_seconds", String(now.idleSeconds))
            } else {
                lastSensors?.idleSeconds = previous.idleSeconds
            }
        } else {
            await send("idle_seconds", String(now.idleSeconds))
        }
        if includeApp, previous?.activeApp != now.activeApp || appToggled {
            await send("active_app", now.activeApp ?? "none")
        }
    }

    // MARK: Commands

    private func runMacControl(_ command: String) {
        guard let mac else { return }
        let allowed = engine.config.macControl
        switch command {
        case "mac_sleep": if allowed.sleep { mac.sleepSystem() }
        case "mac_display_off": if allowed.displayOff { mac.displayOff() }
        case "mac_lock": if allowed.lock { mac.lockScreen() }
        default: break
        }
    }

    private func runCustom(id: String) async {
        let config = engine.config
        guard let runner = commandRunner, config.commandsEnabled,
              let command = config.commands.first(where: { $0.id == id }), command.isValid else { return }
        guard !commandRunning else {
            await publishLastCommand(command, CommandResult(.busy))
            return
        }
        commandRunning = true
        let result = await runner.run(command)
        commandRunning = false
        await publishLastCommand(command, result)
    }

    private func publishLastCommand(_ command: CustomCommand, _ result: CommandResult) async {
        guard connected else { return }
        let attributes = Discovery.json(["command": command.name, "finished": ISO8601DateFormatter().string(from: Date())])
        try? await transport.publish(MQTTMessage(topic: topics.lastCommandAttributes, payload: attributes, retain: true))
        try? await transport.publish(MQTTMessage(topic: topics.lastCommand, payload: result.status.rawValue, retain: true))
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

    private func isOwnDiscoveryConfig(_ topic: String) -> Bool {
        let parts = topic.split(separator: "/", omittingEmptySubsequences: false)
        return parts.count == 5 && parts[0] == Topics.discoveryPrefix[...] && parts[2] == topics.deviceId[...] && parts[4] == "config"
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
        } else if isOwnDiscoveryConfig(message.topic) {
            // A retained config of ours that is no longer wanted (for example a deleted command).
            if !message.payload.isEmpty, !desiredConfigTopics.contains(message.topic) {
                try? await transport.publish(MQTTMessage(topic: message.topic, payload: "", retain: true))
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
            case let name where name.hasPrefix("run_"): await runCustom(id: String(name.dropFirst(4)))
            case let name where name.hasPrefix("mac_"): runMacControl(name)
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
