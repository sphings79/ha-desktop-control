import AppKit
import DesktopControlCore
import SwiftUI

/// Renders README screenshots with fixed sample data (no personal data, no network).
@MainActor
enum SnapshotRunner {
    static func run(into directory: String) -> Never {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        // Outside an app bundle there is no icon; use the project's own.
        if let icon = NSImage(contentsOfFile: "Resources/AppIcon.icns") { app.applicationIconImage = icon }
        Task { @MainActor in
            let pages: [(SettingsView.Page, String, CGFloat)] = [
                (.overview, "screenshot-overview.png", 590),
                (.contacts, "screenshot-contacts.png", 1020),
                (.apps, "screenshot-programs.png", 470)
            ]
            for (page, name, height) in pages {
                for language in [AppLanguage.en, .de] {
                    for dark in [false, true] {
                        var file = name.replacingOccurrences(of: ".png", with: "")
                        if language == .de { file += "-de" }
                        if dark { file += "-dark" }
                        capture(page: page, height: height, dark: dark, language: language,
                                to: URL(fileURLWithPath: directory).appendingPathComponent(file + ".png"))
                        try? await Task.sleep(nanoseconds: 700_000_000)
                    }
                }
            }
            for language in [AppLanguage.en, .de] {
                for dark in [false, true] {
                    var file = "screenshot-welcome"
                    if language == .de { file += "-de" }
                    if dark { file += "-dark" }
                    captureWelcome(dark: dark, language: language,
                                   to: URL(fileURLWithPath: directory).appendingPathComponent(file + ".png"))
                    try? await Task.sleep(nanoseconds: 700_000_000)
                }
            }
            exit(0)
        }
        app.run()
        exit(0)
    }

    private static func sampleConfig(_ language: AppLanguage) -> AppConfig {
        AppConfig(
            broker: BrokerConfig(host: "mqtt.local", port: 1883, tls: false, username: "homeassistant"),
            deviceId: "mac_mini",
            resumeDelaySeconds: 10,
            sources: [
                "office_door": SourceRule(actions: [.pauseMedia, .minimizePausedWindows]),
                "balcony_window": SourceRule(actions: [.pauseMedia]),
                "front_door": SourceRule(actions: [.pauseMedia, .windows])
            ],
            browsers: [.brave, .vivaldi, .chrome],
            apps: [
                AppRule(bundleId: "com.apple.calculator", name: "Calculator", action: .minimize),
                AppRule(bundleId: "com.apple.MobileSMS", name: "Messages", action: .hide)
            ],
            language: language)
    }

    private static func captureWelcome(dark: Bool, language: AppLanguage, to url: URL) {
        let model = AppModel(
            demo: sampleConfig(language),
            snapshot: RuleEngine.Snapshot(status: .idle, enabled: true, openSources: []),
            nowPlaying: "")
        let hosting = NSHostingView(rootView: WelcomeView(model: model))
        let size = hosting.fittingSize
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = hosting
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKey()
        RunLoop.main.run(until: Date().addingTimeInterval(1.6))
        write(window: window, to: url)
    }

    private static func write(window: NSWindow, to url: URL) {
        guard let frameView = window.contentView?.superview,
              let rep = frameView.bitmapImageRepForCachingDisplay(in: frameView.bounds) else { return }
        frameView.cacheDisplay(in: frameView.bounds, to: rep)
        if let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: url)
            print("wrote \(url.path)")
        }
        window.orderOut(nil)
    }

    private static func capture(page: SettingsView.Page, height: CGFloat, dark: Bool, language: AppLanguage, to url: URL) {
        let model = AppModel(
            demo: sampleConfig(language),
            snapshot: RuleEngine.Snapshot(status: .pausedByContact, enabled: true, openSources: ["office_door"]),
            nowPlaying: "Brave: Big Buck Bunny - YouTube")
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 860, height: height),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = NSHostingView(rootView: SettingsView(model: model, page: page))
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKey()
        RunLoop.main.run(until: Date().addingTimeInterval(1.6)) // let SwiftUI lay out and the window become key

        guard let frameView = window.contentView?.superview,
              let rep = frameView.bitmapImageRepForCachingDisplay(in: frameView.bounds) else { return }
        frameView.cacheDisplay(in: frameView.bounds, to: rep)
        if let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: url)
            print("wrote \(url.path)")
        }
        window.orderOut(nil)
    }
}
