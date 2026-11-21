import AppKit
import SwiftUI

struct HADesktopControlApp: App {
    @StateObject private var model = AppModel()

    init() {
        // Hidden check used while setting up permissions: pause, wait, resume, exit.
        if CommandLine.arguments.contains("--selftest-ax") {
            print("AXIsProcessTrusted: \(AXWindowController.isTrusted)")
            exit(0)
        }
        if CommandLine.arguments.contains("--selftest-audio") {
            let audio = CoreAudioOutputController()
            let state = audio.state()
            print(state)
            // Writing the current value back proves the volume/mute controls are settable.
            if let volume = state.volume { print("setVolume(\(volume)): \(audio.setVolume(volume))") }
            if let muted = state.muted { print("setMuted(\(muted)): \(audio.setMuted(muted))") }
            print("selectOutput(current): \(audio.selectOutput(named: state.deviceName))")
            exit(0)
        }
        if CommandLine.arguments.contains("--selftest-media") {
            SelfTest.runMediaAndExit()
        }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuView(model: model)
        } label: {
            MenuBarIcon(model: model)
        }
        Window("HA Desktop Control", id: "welcome") {
            WelcomeView(model: model)
        }
        .windowResizability(.contentSize)
        Window("HA Desktop Control", id: "settings") {
            SettingsView(model: model)
        }
        .windowResizability(.contentSize)
    }
}

/// The menu bar icon; it also opens the setup guide once, on the first launch.
struct MenuBarIcon: View {
    @ObservedObject var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Image(systemName: model.snapshot.status == .pausedByContact
              ? "pause.circle.fill" : (model.snapshot.enabled ? "window.vertical.open" : "slash.circle"))
            .onAppear {
                guard !model.config.onboardingCompleted else { return }
                openWindow(id: "welcome")
                NSApp.activate(ignoringOtherApps: true)
            }
    }
}

struct MenuView: View {
    @ObservedObject var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text(model.snapshot.status == .pausedByContact
             ? model.t("Paused (trigger active)") : model.t("Ready"))
        if !model.snapshot.openSources.isEmpty {
            Text(model.t("Active: %@", model.snapshot.openSources.joined(separator: ", ")))
        }
        Text(model.mqttConnected ? model.t("MQTT: connected") : model.t("MQTT: not connected"))
        if !model.nowPlaying.isEmpty { Text(model.t("Playing: %@", model.nowPlaying)) }
        if let error = model.lastError { Text("⚠︎ \(error)") }
        Divider()
        if let update = model.availableUpdate {
            Button(model.t("Update available: %@", update.tag)) { model.openReleasePage() }
            Divider()
        }
        Toggle(model.t("Control active"), isOn: Binding(
            get: { model.snapshot.enabled }, set: { model.setEnabled($0) }))
        Button(model.t("Pause media")) { model.manualPause() }
        Button(model.t("Restore")) { model.manualRestore() }
        Divider()
        Button(model.t("Settings …")) {
            openWindow(id: "settings")
            NSApp.activate(ignoringOtherApps: true)
        }
        .keyboardShortcut(",")
        Button(model.t("Setup guide …")) {
            openWindow(id: "welcome")
            NSApp.activate(ignoringOtherApps: true)
        }
        Text(model.t("Version %@", AppModel.currentVersion))
        Button(model.t("Quit")) { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
