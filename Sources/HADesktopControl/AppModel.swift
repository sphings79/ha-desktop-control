import AppKit
import Combine
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
    private var permissionWatcher: Task<Void, Never>?
    private var autosave: AnyCancellable?
    private var appearanceWatcher: AnyCancellable?

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

        // Rules, apps and browser choices are saved automatically; only broker changes
        // need the explicit "save & connect" because they reconnect.
        autosave = $config
            .dropFirst()
            .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.persist() }

        // Appearance applies immediately, not after the autosave debounce.
        appearanceWatcher = $config.map(\.appearance).removeDuplicates()
            .sink { Self.apply(appearance: $0) }

        Task { await connect() }
        startPoller()
        startPermissionWatcher()
    }

    static func apply(appearance: AppearanceMode) {
        switch appearance {
        case .system: NSApp?.appearance = nil
        case .light: NSApp?.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp?.appearance = NSAppearance(named: .darkAqua)
        }
    }

    /// Fixed sample state for README screenshots (`--snapshots`); does no I/O and never connects.
    init(demo config: AppConfig, snapshot: RuleEngine.Snapshot, nowPlaying: String) {
        self.config = config
        self.snapshot = snapshot
        self.nowPlaying = nowPlaying
        launchAtLogin = false
        media = BrowserMediaController(browsers: { [] })
        engine = RuleEngine(config: config, media: media, windows: windows)
        mqttConnected = true
        accessibilityTrusted = true
    }

    private func persist() {
        do { try store.save(config) } catch { lastError = "Saving config failed: \(error)" }
        engine.config = config
    }

    func dismissError() { lastError = nil }

    // MARK: - Settings

    func save(password: String?) {
        persist()
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
        let trusted = AXWindowController.isTrusted
        if trusted != accessibilityTrusted { accessibilityTrusted = trusted }
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

    /// Re-checks the Accessibility permission, so the Settings tab updates right after the user
    /// grants it in System Settings (macOS sends no notification for this).
    private func startPermissionWatcher() {
        permissionWatcher = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                self?.refreshPermissions()
            }
        }
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refreshPermissions() }
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
