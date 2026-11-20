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
        if CommandLine.arguments.contains("--selftest-media") {
            SelfTest.runMediaAndExit()
        }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuView(model: model)
        } label: {
            Image(systemName: model.snapshot.status == .pausedByContact
                  ? "pause.circle.fill" : (model.snapshot.enabled ? "window.vertical.open" : "slash.circle"))
        }
        Window("Einstellungen", id: "settings") {
            SettingsView(model: model)
        }
        .windowResizability(.contentSize)
    }
}

struct MenuView: View {
    @ObservedObject var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text(model.snapshot.status == .pausedByContact
             ? "Pausiert (Auslöser aktiv)" : "Bereit")
        if !model.snapshot.openSources.isEmpty {
            Text("Aktiv: " + model.snapshot.openSources.joined(separator: ", "))
        }
        Text(model.mqttConnected ? "MQTT: verbunden" : "MQTT: nicht verbunden")
        if !model.nowPlaying.isEmpty { Text("Läuft: \(model.nowPlaying)") }
        if let error = model.lastError { Text("⚠︎ \(error)") }
        Divider()
        Toggle("Steuerung aktiv", isOn: Binding(
            get: { model.snapshot.enabled }, set: { model.setEnabled($0) }))
        Button("Medien pausieren") { model.manualPause() }
        Button("Wiederherstellen") { model.manualRestore() }
        Divider()
        Button("Einstellungen …") {
            openWindow(id: "settings")
            NSApp.activate(ignoringOtherApps: true)
        }
        .keyboardShortcut(",")
        Button("Beenden") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
