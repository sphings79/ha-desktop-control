import AppKit
import DesktopControlCore
import SwiftUI

/// Renders README screenshots with fixed sample data (no personal data, no network).
@MainActor
enum SnapshotRunner {
    static func run(into directory: String) -> Never {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        Task { @MainActor in
            let pages: [(SettingsView.Page, String, CGFloat)] = [
                (.overview, "screenshot-overview.png", 590),
                (.contacts, "screenshot-contacts.png", 700),
                (.apps, "screenshot-programs.png", 470)
            ]
            for (page, name, height) in pages {
                for dark in [false, true] {
                    let file = dark ? name.replacingOccurrences(of: ".png", with: "-dark.png") : name
                    capture(page: page, height: height, dark: dark,
                            to: URL(fileURLWithPath: directory).appendingPathComponent(file))
                    try? await Task.sleep(nanoseconds: 800_000_000)
                }
            }
            exit(0)
        }
        app.run()
        exit(0)
    }

    private static func sampleConfig() -> AppConfig {
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
            ])
    }

    private static func capture(page: SettingsView.Page, height: CGFloat, dark: Bool, to url: URL) {
        let model = AppModel(
            demo: sampleConfig(),
            snapshot: RuleEngine.Snapshot(status: .pausedByContact, enabled: true, openSources: ["office_door"]),
            nowPlaying: "Brave: Big Buck Bunny - YouTube")
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 860, height: height),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = NSHostingView(rootView: SettingsView(model: model, page: page))
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        RunLoop.main.run(until: Date().addingTimeInterval(1.2)) // let SwiftUI lay out

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
