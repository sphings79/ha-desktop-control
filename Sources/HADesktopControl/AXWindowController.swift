import AppKit
import ApplicationServices
import DesktopControlCore

/// Minimizes, hides or quits applications. Needs the Accessibility permission for minimize.
final class AXWindowController: WindowControlling {
    var onError: ((String) -> Void)?

    static var isTrusted: Bool { AXIsProcessTrusted() }

    static func requestTrust() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    func apply(_ rule: AppRule) async -> WindowJournalEntry? {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: rule.bundleId).first else {
            return nil
        }
        switch rule.action {
        case .hide:
            guard !app.isHidden else { return nil }
            app.hide()
            return WindowJournalEntry(rule: rule)
        case .quit:
            app.terminate()
            return WindowJournalEntry(rule: rule)
        case .minimize:
            guard Self.isTrusted else {
                onError?("Accessibility permission missing: cannot minimize \(rule.name)")
                return nil
            }
            let titles = await minimizeWindows(of: app)
            return titles.isEmpty ? nil : WindowJournalEntry(rule: rule, minimizedWindowTitles: titles)
        }
    }

    func restore(_ entry: WindowJournalEntry) async {
        switch entry.rule.action {
        case .hide:
            NSRunningApplication.runningApplications(withBundleIdentifier: entry.rule.bundleId).first?.unhide()
        case .quit:
            guard NSRunningApplication.runningApplications(withBundleIdentifier: entry.rule.bundleId).isEmpty,
                  let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: entry.rule.bundleId) else { return }
            let config = NSWorkspace.OpenConfiguration()
            _ = try? await NSWorkspace.shared.openApplication(at: url, configuration: config)
        case .minimize:
            guard Self.isTrusted,
                  let app = NSRunningApplication.runningApplications(withBundleIdentifier: entry.rule.bundleId).first
            else { return }
            var remaining = entry.minimizedWindowTitles
            for window in windows(of: app) where bool(window, kAXMinimizedAttribute) == true {
                let title = string(window, kAXTitleAttribute)
                if let index = remaining.firstIndex(of: title) {
                    remaining.remove(at: index)
                    AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
                }
            }
        }
    }

    // MARK: - Accessibility helpers

    private func windows(of app: NSRunningApplication) -> [AXUIElement] {
        let element = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(element, 2)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXWindowsAttribute as CFString, &value) == .success else {
            return []
        }
        return value as? [AXUIElement] ?? []
    }

    private func bool(_ element: AXUIElement, _ attribute: String) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return (value as? Bool)
    }

    private func string(_ element: AXUIElement, _ attribute: String) -> String {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return "" }
        return value as? String ?? ""
    }

    /// Leaves full screen first (a full-screen window cannot be minimized), waits for the
    /// transition, then re-reads the window list because macOS replaces window objects meanwhile.
    private func minimizeWindows(of app: NSRunningApplication) async -> [String] {
        for window in windows(of: app) where bool(window, "AXFullScreen") == true {
            AXUIElementSetAttributeValue(window, "AXFullScreen" as CFString, kCFBooleanFalse)
        }
        for _ in 0..<30 { // up to 6 s
            if !windows(of: app).contains(where: { bool($0, "AXFullScreen") == true }) { break }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        try? await Task.sleep(nanoseconds: 500_000_000)

        var titles: [String] = []
        for window in windows(of: app) where bool(window, kAXMinimizedAttribute) == false {
            let title = string(window, kAXTitleAttribute)
            if AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanTrue) == .success {
                titles.append(title)
            }
        }
        return titles
    }
}
