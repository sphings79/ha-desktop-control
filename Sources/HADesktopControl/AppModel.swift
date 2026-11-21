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
    @Published private(set) var availableUpdate: ReleaseInfo?
    @Published private(set) var updateState: UpdateState = .idle
    @Published private(set) var copiedSource: String?
    /// Screenshot mode only: open the YAML generator of the first trigger.
    private(set) var demoExpandYAML = false
    @Published private(set) var browserChecks: [BrowserCheck] = []
    /// Set by the setup window; the settings window jumps to this page.
    @Published var requestedPage: SettingsView.Page?

    enum UpdateState: Equatable {
        case idle, checking, upToDate(Date), failed
    }

    /// `CFBundleShortVersionString` of the app bundle, or "dev" when run from `swift run`.
    static let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"

    private let store = ConfigStore()
    private let media: BrowserMediaController
    private let windows = AXWindowController()
    private let audio = CoreAudioOutputController()
    private let popup = PopupController()
    private var popupPaused = false
    @Published var copiedPopup = false
    private let engine: RuleEngine
    private var bridge: MQTTBridge?
    private var poller: Task<Void, Never>?
    private var permissionWatcher: Task<Void, Never>?
    private var autosave: AnyCancellable?
    private var appearanceWatcher: AnyCancellable?
    private var updateLoop: Task<Void, Never>?

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
        startUpdateLoop()
    }

    // MARK: - Language

    var language: AppLanguage { L10n.resolve(config.language) }

    /// Translated text; views call this so they refresh when the language changes.
    func t(_ key: String, _ args: String...) -> String {
        L10n.tr(key, args, language: language)
    }

    // MARK: - Setup guide

    func refreshOnboarding() async {
        guard !demoExpandYAML else { return } // screenshot mode keeps its sample data
        refreshPermissions()
        var checks: [BrowserCheck] = []
        let runner = AppleScriptRunner()
        for browser in BrowserKind.allCases where NSWorkspace.shared.urlForApplication(withBundleIdentifier: browser.bundleId) != nil {
            let automation = PermissionChecker.automation(for: browser)
            var javascript = BrowserCheck.JavaScript.unknown
            if automation == .granted { javascript = await PermissionChecker.javascript(for: browser, runner: runner) }
            checks.append(BrowserCheck(browser: browser, automation: automation, javascript: javascript))
        }
        if checks != browserChecks { browserChecks = checks }
    }

    // MARK: - Updates

    func checkForUpdates() {
        guard updateState != .checking else { return }
        updateState = .checking
        Task {
            var request = URLRequest(
                url: URL(string: "https://api.github.com/repos/sphings79/ha-desktop-control/releases/latest")!,
                timeoutInterval: 10)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("ha-desktop-control/\(Self.currentVersion)", forHTTPHeaderField: "User-Agent")
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard (response as? HTTPURLResponse)?.statusCode == 200, let info = ReleaseInfo.parse(data) else {
                    updateState = .failed
                    return
                }
                if let current = AppVersion(Self.currentVersion), current < info.version {
                    availableUpdate = info
                } else {
                    availableUpdate = nil
                }
                updateState = .upToDate(Date())
            } catch {
                updateState = .failed
            }
        }
    }

    func openReleasePage() {
        if let url = availableUpdate?.url { NSWorkspace.shared.open(url) }
    }

    private func startUpdateLoop() {
        updateLoop = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            while !Task.isCancelled {
                guard let self else { return }
                if self.config.checkForUpdates { self.checkForUpdates() }
                try? await Task.sleep(nanoseconds: 24 * 3600 * 1_000_000_000)
            }
        }
    }

    // MARK: - Automation example

    func automationYAML(for source: String, entity: String) -> String {
        AutomationExample.yaml(deviceId: config.deviceId, source: source, entity: entity)
    }

    // MARK: - Popup

    static var systemSounds: [String] {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: "/System/Library/Sounds")) ?? []
        return files.filter { $0.hasSuffix(".aiff") }.map { String($0.dropLast(5)) }.sorted()
    }

    func showPopup(_ request: PopupRequest) {
        guard config.popup.enabled else { return }
        popup.onDismiss = { [weak self] in self?.popupClosed() }
        popup.show(
            title: request.title,
            imageURL: request.imageURL(base: config.haBaseURL),
            seconds: request.displaySeconds(config: config.popup))
        if let name = request.soundName(config: config.popup) { NSSound(named: NSSound.Name(name))?.play() }
        if request.shouldPause(config: config.popup), engine.status == .idle, !popupPaused {
            popupPaused = true
            Task { await engine.manualPause() }
        }
    }

    func testPopup() {
        showPopup(PopupRequest(title: t("Test popup"), duration: 8, sound: .on))
    }

    private func popupClosed() {
        guard popupPaused else { return }
        popupPaused = false
        Task {
            if engine.openSources.isEmpty { await engine.manualRestore() }
        }
    }

    func previewSound(_ name: String) {
        if !name.isEmpty { NSSound(named: NSSound.Name(name))?.play() }
    }

    func popupYAML(trigger: String, camera: String) -> String {
        AutomationExample.popupYAML(deviceId: config.deviceId, trigger: trigger, camera: camera, title: t("Doorbell"))
    }

    func copyPopupYAML(trigger: String, camera: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(popupYAML(trigger: trigger, camera: camera), forType: .string)
        copiedPopup = true
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            copiedPopup = false
        }
    }

    func copyAutomationYAML(for source: String, entity: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(automationYAML(for: source, entity: entity), forType: .string)
        copiedSource = source
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if copiedSource == source { copiedSource = nil }
        }
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
        demoExpandYAML = true
        browserChecks = [
            BrowserCheck(browser: .brave, automation: .granted, javascript: .on),
            BrowserCheck(browser: .vivaldi, automation: .notAsked, javascript: .unknown)
        ]
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
            deviceName: Host.current().localizedName ?? "Mac", audio: audio)
        bridge.onPopup = { [weak self] request in self?.showPopup(request) }
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
