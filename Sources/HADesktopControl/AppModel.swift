import AppKit
import DesktopControlCore
import ServiceManagement
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    @Published var config: AppConfig
    @Published private(set) var snapshot = RuleEngine.Snapshot(status: .idle, enabled: true, openSources: [])
    @Published private(set) var mqttConnected = false
    @Published private(set) var lastError: String?
    @Published private(set) var nowPlaying = ""
    @Published private(set) var accessibilityTrusted = AXWindowController.isTrusted
    @Published var launchAtLogin: Bool

    private let store = ConfigStore()
    private let media: BrowserMediaController
    private let windows = AXWindowController()
    private let engine: RuleEngine
    private var bridge: MQTTBridge?
    private var poller: Task<Void, Never>?

    init() {
        let loaded = ConfigStore().load()
        config = loaded
        launchAtLogin = SMAppService.mainApp.status == .enabled

        var browsers: () -> [BrowserKind] = { [] }
        let mediaController = BrowserMediaController(browsers: { browsers() })
        media = mediaController
        engine = RuleEngine(config: loaded, media: mediaController, windows: windows)
        browsers = { [weak self] in self?.engine.config.browsers ?? [] }

        mediaController.onError = { [weak self] message in
            Task { @MainActor in self?.lastError = message }
        }
        windows.onError = { [weak self] message in
            Task { @MainActor in self?.lastError = message }
        }
        engine.onChange = { [weak self] snapshot in
            self?.snapshot = snapshot
        }

        Task { await connect() }
        startPoller()
    }

    // MARK: - Settings

    func save(password: String?) {
        do { try store.save(config) } catch { lastError = "Saving config failed: \(error)" }
        engine.config = config
        if let password { KeychainStore.setPassword(password, for: config.broker.username) }
        Task {
            await bridge?.stop()
            bridge = nil
            await connect()
        }
    }

    func storedPassword() -> String {
        KeychainStore.password(for: config.broker.username) ?? ""
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            lastError = "Login item: \(error.localizedDescription)"
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func requestAccessibility() {
        AXWindowController.requestTrust()
        refreshPermissions()
    }

    func refreshPermissions() {
        accessibilityTrusted = AXWindowController.isTrusted
    }

    // MARK: - Control

    func setEnabled(_ value: Bool) {
        Task { await engine.setEnabled(value) }
    }

    func manualPause() { Task { await engine.manualPause() } }
    func manualRestore() { Task { await engine.manualRestore() } }

    // MARK: - MQTT

    private func connect() async {
        guard !config.broker.host.isEmpty else {
            lastError = "No MQTT broker configured (Settings)"
            return
        }
        let topics = Topics(deviceId: config.deviceId)
        let bridge = MQTTBridge(
            transport: MQTTNIOTransport(), engine: engine, topics: topics,
            deviceName: Host.current().localizedName ?? "Mac")
        bridge.onConnectionChange = { [weak self] isUp in
            self?.mqttConnected = isUp
            if isUp { self?.lastError = nil }
        }
        self.bridge = bridge
        do {
            let password = KeychainStore.password(for: config.broker.username)
            try await bridge.start(broker: config.broker, password: password)
            lastError = nil
        } catch {
            lastError = "MQTT: \(error)"
        }
    }

    private func startPoller() {
        poller = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                guard let self else { return }
                guard self.mqttConnected, self.snapshot.enabled else { continue }
                let playing = await self.media.nowPlaying()
                self.nowPlaying = playing
                await self.bridge?.setNowPlaying(playing)
            }
        }
    }
}
