import XCTest
@testable import DesktopControlCore

final class TopicsTests: XCTestCase {
    func testSlug() {
        XCTAssertEqual(Topics.slug("Dennis' Mac mini"), "dennis_mac_mini")
        XCTAssertEqual(Topics.slug("***"), "mac")
    }

    func testContactTopicParsing() {
        let t = Topics(deviceId: "mini")
        XCTAssertEqual(t.contact("balkon"), "ha-desktop-control/mini/contact/balkon")
        XCTAssertEqual(t.source(fromContactTopic: "ha-desktop-control/mini/contact/balkon"), "balkon")
        XCTAssertNil(t.source(fromContactTopic: "ha-desktop-control/mini/contact/a/b"))
        XCTAssertNil(t.source(fromContactTopic: "ha-desktop-control/other/contact/balkon"))
    }
}

final class ConfigTests: XCTestCase {
    func testMissingKeysFallBackToDefaults() throws {
        let data = Data(#"{"deviceId":"mini"}"#.utf8)
        let config = try JSONDecoder().decode(AppConfig.self, from: data)
        XCTAssertEqual(config.deviceId, "mini")
        XCTAssertEqual(config.resumeDelaySeconds, 10)
        XCTAssertEqual(config.broker.port, 1883)
        XCTAssertEqual(config.appearance, .system)
    }

    func testAppearanceRoundTrip() throws {
        let data = try JSONEncoder().encode(AppConfig(appearance: .dark))
        XCTAssertEqual(try JSONDecoder().decode(AppConfig.self, from: data).appearance, .dark)
    }

    func testStoreRoundTrip() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathComponent("config.json")
        let store = ConfigStore(url: url)
        var config = AppConfig(deviceId: "mini")
        config.sources["door"] = SourceRule(actions: [.pauseMedia, .windows])
        config.apps = [AppRule(bundleId: "a.b", name: "AB", action: .hide)]
        try store.save(config)
        XCTAssertEqual(store.load(), config)
        XCTAssertEqual(ConfigStore(url: url.deletingLastPathComponent().appendingPathComponent("none.json")).load(), AppConfig())
    }

    func testConfigNeverContainsPassword() throws {
        let data = try JSONEncoder().encode(AppConfig())
        XCTAssertFalse(String(decoding: data, as: UTF8.self).lowercased().contains("password"))
    }
}

@MainActor
final class BridgeTests: XCTestCase {
    private func makeBridge() -> (MQTTBridge, FakeTransport, RuleEngine, FakeMedia) {
        let media = FakeMedia()
        let engine = RuleEngine(config: AppConfig(resumeDelaySeconds: 0), media: media, windows: FakeWindows())
        let transport = FakeTransport()
        let bridge = MQTTBridge(
            transport: transport, engine: engine, topics: Topics(deviceId: "mini"), deviceName: "Mini")
        return (bridge, transport, engine, media)
    }

    func testParseContact() {
        XCTAssertEqual(MQTTBridge.parseContact("open"), true)
        XCTAssertEqual(MQTTBridge.parseContact(" ON\n"), true)
        XCTAssertEqual(MQTTBridge.parseContact("Closed"), false)
        XCTAssertNil(MQTTBridge.parseContact("unavailable"))
    }

    func testConnectSubscribesAndPublishesDiscovery() async throws {
        let (bridge, transport, _, _) = makeBridge()
        try await bridge.start(broker: BrokerConfig(host: "h"), password: nil)
        let ok = await waitUntil { transport.lastPayload("ha-desktop-control/mini/status") != nil }
        XCTAssertTrue(ok)

        XCTAssertEqual(transport.will?.payload, "offline")
        XCTAssertEqual(Set(transport.subscribed), [
            "ha-desktop-control/mini/contact/+",
            "ha-desktop-control/mini/enabled/set",
            "ha-desktop-control/mini/cmd/+",
            "ha-desktop-control/mini/popup"
        ])
        XCTAssertEqual(transport.lastPayload("ha-desktop-control/mini/availability"), "online")
        XCTAssertEqual(transport.lastPayload("ha-desktop-control/mini/enabled"), "ON")
        XCTAssertEqual(transport.lastPayload("ha-desktop-control/mini/status"), "idle")
        let discovery = transport.published.filter { $0.topic.hasPrefix("homeassistant/") }
        XCTAssertEqual(discovery.count, 5)
        XCTAssertTrue(discovery.allSatisfy { $0.retain })
        XCTAssertTrue(discovery.allSatisfy { (try? JSONSerialization.jsonObject(with: Data($0.payload.utf8))) != nil })
        await bridge.stop()
    }

    func testAudioStateDiscoveryAndCommands() async throws {
        let audio = FakeAudio()
        let engine = RuleEngine(config: AppConfig(resumeDelaySeconds: 0), media: FakeMedia(), windows: FakeWindows())
        let transport = FakeTransport()
        let bridge = MQTTBridge(
            transport: transport, engine: engine, topics: Topics(deviceId: "mini"), deviceName: "Mini", audio: audio)
        try await bridge.start(broker: BrokerConfig(host: "h"), password: nil)
        let ready = await waitUntil { transport.lastPayload("ha-desktop-control/mini/audio/muted") != nil }
        XCTAssertTrue(ready)

        XCTAssertTrue(transport.subscribed.contains("ha-desktop-control/mini/audio/+/set"))
        XCTAssertEqual(transport.lastPayload("ha-desktop-control/mini/audio/output"), "Speakers")
        XCTAssertEqual(transport.lastPayload("ha-desktop-control/mini/audio/output_type"), "builtin_speaker")
        XCTAssertEqual(transport.lastPayload("ha-desktop-control/mini/audio/volume"), "40")
        XCTAssertEqual(transport.lastPayload("ha-desktop-control/mini/audio/muted"), "OFF")
        let discovery = transport.published.filter { $0.topic.hasPrefix("homeassistant/") }
        XCTAssertEqual(discovery.count, 9)

        transport.onMessage?(MQTTMessage(topic: "ha-desktop-control/mini/audio/volume/set", payload: "150"))
        let clamped = await waitUntil { audio.current.volume == 100 }
        XCTAssertTrue(clamped)
        let published = await waitUntil { transport.lastPayload("ha-desktop-control/mini/audio/volume") == "100" }
        XCTAssertTrue(published)

        transport.onMessage?(MQTTMessage(topic: "ha-desktop-control/mini/audio/muted/set", payload: "ON"))
        let muted = await waitUntil { transport.lastPayload("ha-desktop-control/mini/audio/muted") == "ON" }
        XCTAssertTrue(muted)

        transport.onMessage?(MQTTMessage(topic: "ha-desktop-control/mini/audio/output/set", payload: "AirPods"))
        let switched = await waitUntil { transport.lastPayload("ha-desktop-control/mini/audio/output_type") == "bluetooth" }
        XCTAssertTrue(switched)
        XCTAssertEqual(transport.lastPayload("ha-desktop-control/mini/audio/output"), "AirPods")

        transport.onMessage?(MQTTMessage(topic: "ha-desktop-control/mini/audio/volume/set", payload: "abc"))
        transport.onMessage?(MQTTMessage(topic: "ha-desktop-control/mini/audio/output/set", payload: "Nope"))
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(audio.current.volume, 100)
        XCTAssertEqual(audio.current.deviceName, "AirPods")

        // A volume change on a device without software volume is published as unknown.
        audio.current.volume = nil
        audio.onChange?()
        let reset = await waitUntil { transport.lastPayload("ha-desktop-control/mini/audio/volume") == "None" }
        XCTAssertTrue(reset)
        await bridge.stop()
    }

    func testPopupMessagesAreRoutedAndRetainedOnesIgnored() async throws {
        let (bridge, transport, _, _) = makeBridge()
        var received: [PopupRequest] = []
        bridge.onPopup = { received.append($0) }
        try await bridge.start(broker: BrokerConfig(host: "h"), password: nil)
        transport.onMessage?(MQTTMessage(topic: "ha-desktop-control/mini/popup", payload: #"{"title":"Door"}"#, retain: true))
        transport.onMessage?(MQTTMessage(topic: "ha-desktop-control/mini/popup", payload: "not json"))
        transport.onMessage?(MQTTMessage(topic: "ha-desktop-control/mini/popup", payload: #"{"title":"Door","duration":1,"sound":false}"#))
        let ok = await waitUntil { received.count == 1 }
        XCTAssertTrue(ok)
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(received.count, 1)
        XCTAssertEqual(received[0].title, "Door")
        XCTAssertEqual(received[0].duration, 3) // clamped to the minimum
        XCTAssertEqual(received[0].sound, .off)
        await bridge.stop()
    }

    func testContactMessageTriggersEngineAndStatusIsPublished() async throws {
        let (bridge, transport, engine, media) = makeBridge()
        try await bridge.start(broker: BrokerConfig(host: "h"), password: nil)
        transport.onMessage?(MQTTMessage(topic: "ha-desktop-control/mini/contact/balkon", payload: "open", retain: true))

        let paused = await waitUntil { engine.status == .pausedByContact }
        XCTAssertTrue(paused)
        XCTAssertEqual(media.pauseCalls, 1)
        let published = await waitUntil { transport.lastPayload("ha-desktop-control/mini/status") == "paused_by_contact" }
        XCTAssertTrue(published)

        transport.onMessage?(MQTTMessage(topic: "ha-desktop-control/mini/contact/balkon", payload: "closed", retain: true))
        let idle = await waitUntil { engine.status == .idle }
        XCTAssertTrue(idle)
        XCTAssertEqual(media.resumed.count, 1)
        await bridge.stop()
    }

    func testEnabledSetAndCommands() async throws {
        let (bridge, transport, engine, media) = makeBridge()
        try await bridge.start(broker: BrokerConfig(host: "h"), password: nil)

        transport.onMessage?(MQTTMessage(topic: "ha-desktop-control/mini/enabled/set", payload: "OFF"))
        let off = await waitUntil { !engine.enabled }
        XCTAssertTrue(off)
        let published = await waitUntil { transport.lastPayload("ha-desktop-control/mini/enabled") == "OFF" }
        XCTAssertTrue(published)

        transport.onMessage?(MQTTMessage(topic: "ha-desktop-control/mini/enabled/set", payload: "ON"))
        _ = await waitUntil { engine.enabled }
        transport.onMessage?(MQTTMessage(topic: "ha-desktop-control/mini/cmd/pause_media", payload: "PRESS"))
        let paused = await waitUntil { media.pauseCalls == 1 }
        XCTAssertTrue(paused)
        transport.onMessage?(MQTTMessage(topic: "ha-desktop-control/mini/cmd/restore", payload: "PRESS"))
        let restored = await waitUntil { media.resumed.count == 1 }
        XCTAssertTrue(restored)
        await bridge.stop()
    }

    func testBridgeKeepsExistingEngineHandler() async throws {
        let (bridge, _, engine, _) = makeBridge()
        var seen: [RuleEngine.Status] = []
        engine.onChange = { seen.append($0.status) }
        try await bridge.start(broker: BrokerConfig(host: "h"), password: nil)
        await engine.setContact(source: "a", open: true)
        XCTAssertEqual(seen, [.pausedByContact], "UI handler must still be called")
        await bridge.stop()
        await engine.setContact(source: "a", open: false)
        await engine.manualRestore()
        XCTAssertEqual(seen.first, .pausedByContact)
        XCTAssertNotNil(engine.onChange, "handler restored after stop")
    }

    func testNowPlayingIsPublishedOnlyOnChange() async throws {
        let (bridge, transport, _, _) = makeBridge()
        try await bridge.start(broker: BrokerConfig(host: "h"), password: nil)
        _ = await waitUntil { transport.lastPayload("ha-desktop-control/mini/now_playing") != nil }
        await bridge.setNowPlaying("YouTube")
        await bridge.setNowPlaying("YouTube")
        let count = transport.published.filter {
            $0.topic == "ha-desktop-control/mini/now_playing" && $0.payload == "YouTube"
        }.count
        XCTAssertEqual(count, 1)
        await bridge.stop()
    }
}
