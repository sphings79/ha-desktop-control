import AppKit
import ApplicationServices
import DesktopControlCore
import SwiftUI

/// Live state of the permissions the app needs; polled while the setup window is open.
struct BrowserCheck: Identifiable, Equatable {
    enum Automation: Equatable { case notRunning, granted, denied, notAsked }
    enum JavaScript: Equatable { case on, off, unknown }

    var browser: BrowserKind
    var automation: Automation
    var javascript: JavaScript
    var id: String { browser.rawValue }
}

enum PermissionChecker {
    /// Asks macOS without prompting whether we may send Apple Events to the browser.
    static func automation(for browser: BrowserKind) -> BrowserCheck.Automation {
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: browser.bundleId).isEmpty else {
            return .notRunning
        }
        let target = NSAppleEventDescriptor(bundleIdentifier: browser.bundleId)
        let status = AEDeterminePermissionToAutomateTarget(target.aeDesc, typeWildCard, typeWildCard, false)
        switch status {
        case noErr: return .granted
        case OSStatus(errAEEventNotPermitted): return .denied
        default: return .notAsked // errAEEventWouldRequireUserConsent or unknown
        }
    }

    /// Runs a harmless script in the front tab. Chromium refuses with a message that names
    /// "Apple Events" when the Developer-menu switch is off; no open window means we cannot tell.
    static func javascript(for browser: BrowserKind, runner: AppleScriptRunner) async -> BrowserCheck.JavaScript {
        let script = """
        tell application id "\(browser.bundleId)"
            if (count of windows) is 0 then return "nowindow"
            return execute (active tab of front window) javascript "1"
        end tell
        """
        switch await runner.run(script) {
        case .success(let text): return text == "nowindow" ? .unknown : .on
        case .failure(let error): return error.message.contains("Apple Events") ? .off : .unknown
        }
    }
}

enum SystemSettingsLink {
    static func open(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }
}

struct WelcomeView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 52, height: 52)
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.t("Welcome to HA Desktop Control")).font(.title2.weight(.semibold))
                    Text(model.t("A few permissions are needed so your Mac can react to Home Assistant. This window updates by itself."))
                        .font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            step(done: model.mqttConnected, symbol: "network", title: model.t("Connect to your MQTT broker"),
                 status: model.mqttConnected ? model.t("Connected") : model.t("Not connected yet")) {
                if !model.mqttConnected {
                    Button(model.t("Open MQTT settings")) { openSettings(page: .mqtt) }
                }
            }

            step(done: model.accessibilityTrusted, symbol: "figure.stand", title: model.t("Accessibility access"),
                 status: model.accessibilityTrusted ? model.t("Allowed") : model.t("Not allowed yet"),
                 detail: model.t("Lets the app leave full screen and minimize windows.")) {
                if !model.accessibilityTrusted {
                    Button(model.t("Open Accessibility settings")) {
                        model.requestAccessibility()
                        SystemSettingsLink.open("Privacy_Accessibility")
                    }
                }
            }

            let browsersDone = model.browserChecks.contains { $0.automation == .granted && $0.javascript == .on }
            step(done: browsersDone, symbol: "safari", title: model.t("Browser control"), status: nil,
                 detail: model.t("Start your browser, then enable View › Developer › “Allow JavaScript from Apple Events”. macOS asks for Automation access the first time media is paused.")) {
                VStack(alignment: .leading, spacing: 6) {
                    if model.browserChecks.allSatisfy({ $0.automation == .notRunning }) {
                        Text(model.t("No browser is running. Start one to check its permissions."))
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    ForEach(model.browserChecks.filter { $0.automation != .notRunning }) { check in
                        HStack(spacing: 10) {
                            Text(check.browser.displayName).font(.callout.weight(.medium)).frame(width: 70, alignment: .leading)
                            badge(model.t("Automation"), automationText(check.automation),
                                  ok: check.automation == .granted)
                            badge(model.t("JavaScript from Apple Events"), jsText(check.javascript),
                                  ok: check.javascript == .on)
                        }
                    }
                    if model.browserChecks.contains(where: { $0.automation == .denied || $0.automation == .notAsked }) {
                        Button(model.t("Open Automation settings")) { SystemSettingsLink.open("Privacy_Automation") }
                    }
                }
            }

            step(done: !model.config.sources.isEmpty, symbol: "door.left.hand.open",
                 title: model.t("Create your first trigger"), status: nil,
                 detail: model.t("Add a trigger and copy the generated Home Assistant automation.")) {
                Button(model.t("Open triggers")) { openSettings(page: .contacts) }
            }

            HStack {
                Spacer()
                Button(model.t("Done")) {
                    model.config.onboardingCompleted = true
                    dismissWindow(id: "welcome")
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 560)
        .task {
            while !Task.isCancelled {
                await model.refreshOnboarding()
                try? await Task.sleep(nanoseconds: 2_500_000_000)
            }
        }
    }

    private func openSettings(page: SettingsView.Page) {
        model.requestedPage = page
        openWindow(id: "settings")
        NSApp.activate(ignoringOtherApps: true)
    }

    private func automationText(_ state: BrowserCheck.Automation) -> String {
        switch state {
        case .granted: return model.t("allowed")
        case .denied, .notAsked: return model.t("not allowed yet")
        case .notRunning: return model.t("not running")
        }
    }

    private func jsText(_ state: BrowserCheck.JavaScript) -> String {
        switch state {
        case .on: return model.t("on")
        case .off: return model.t("off")
        case .unknown: return model.t("open a window to check")
        }
    }

    private func badge(_ title: String, _ value: String, ok: Bool) -> some View {
        HStack(spacing: 5) {
            Image(systemName: ok ? "checkmark.circle.fill" : "circle.dashed")
                .foregroundStyle(ok ? Color.green : Color.orange)
            Text("\(title): \(value)").font(.caption)
        }
    }

    private func step<Content: View>(
        done: Bool, symbol: String, title: String, status: String?, detail: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: done ? "checkmark.circle.fill" : symbol)
                .font(.title2)
                .foregroundStyle(done ? Color.green : Color.accentColor)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(title).font(.headline)
                    if let status {
                        Text(status).font(.caption).foregroundStyle(done ? Color.green : Color.orange)
                    }
                }
                if let detail {
                    Text(detail).font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                content()
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.08)))
    }
}
