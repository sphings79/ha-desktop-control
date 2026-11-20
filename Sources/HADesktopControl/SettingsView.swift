import AppKit
import DesktopControlCore
import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @State private var password = ""
    @State private var newSource = ""

    var body: some View {
        TabView {
            brokerTab.tabItem { Label("MQTT", systemImage: "network") }
            sourcesTab.tabItem { Label("Kontakte", systemImage: "door.left.hand.open") }
            appsTab.tabItem { Label("Programme", systemImage: "macwindow") }
            generalTab.tabItem { Label("Allgemein", systemImage: "gearshape") }
        }
        .frame(width: 520, height: 420)
        .onAppear {
            password = model.storedPassword()
            model.refreshPermissions()
        }
    }

    // MARK: Broker

    private var brokerTab: some View {
        Form {
            TextField("Host", text: $model.config.broker.host)
            TextField("Port", value: $model.config.broker.port, format: .number.grouping(.never))
            Toggle("TLS", isOn: $model.config.broker.tls)
            TextField("Benutzer", text: $model.config.broker.username)
            SecureField("Passwort (Schlüsselbund)", text: $password)
            TextField("Geräte-ID", text: $model.config.deviceId)
            HStack {
                Text("Topics: ha-desktop-control/\(Topics.slug(model.config.deviceId))/…")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Speichern & verbinden") { model.save(password: password) }
            }
        }
        .padding()
    }

    // MARK: Sources

    private var sourcesTab: some View {
        VStack(alignment: .leading) {
            Text("Quelle = Name im Topic …/contact/<Name>. Nicht aufgeführte Quellen pausieren nur Medien.")
                .font(.caption).foregroundStyle(.secondary)
            List {
                ForEach(model.config.sources.keys.sorted(), id: \.self) { name in
                    HStack {
                        Text(name).frame(minWidth: 120, alignment: .leading)
                        Toggle("Medien", isOn: actionBinding(name, .pauseMedia))
                        Toggle("Programme", isOn: actionBinding(name, .windows))
                        Spacer()
                        Button(role: .destructive) { model.config.sources[name] = nil } label: {
                            Image(systemName: "trash")
                        }.buttonStyle(.borderless)
                    }
                }
            }
            HStack {
                TextField("Neue Quelle (z. B. balkontuer)", text: $newSource)
                Button("Hinzufügen") {
                    let name = Topics.slug(newSource)
                    if !newSource.isEmpty, model.config.sources[name] == nil {
                        model.config.sources[name] = SourceRule(actions: [.pauseMedia])
                    }
                    newSource = ""
                }
            }
            HStack {
                Stepper(value: $model.config.resumeDelaySeconds, in: 0...300, step: 5) {
                    Text("Fortsetzen nach \(Int(model.config.resumeDelaySeconds)) s")
                }
                Spacer()
                Button("Speichern") { model.save(password: nil) }
            }
        }
        .padding()
    }

    private func actionBinding(_ source: String, _ action: SourceAction) -> Binding<Bool> {
        Binding(
            get: { model.config.sources[source]?.actions.contains(action) ?? false },
            set: { on in
                var actions = model.config.sources[source]?.actions ?? []
                actions.removeAll { $0 == action }
                if on { actions.append(action) }
                model.config.sources[source] = SourceRule(actions: actions)
            })
    }

    // MARK: Apps

    private var appsTab: some View {
        VStack(alignment: .leading) {
            Text("Wird bei Quellen mit „Programme“ angewendet. Rückgängig nur, was die App selbst getan hat.")
                .font(.caption).foregroundStyle(.secondary)
            List {
                ForEach($model.config.apps) { $rule in
                    HStack {
                        Text(rule.name).frame(minWidth: 110, alignment: .leading)
                        Picker("", selection: $rule.action) {
                            Text("Minimieren").tag(WindowAction.minimize)
                            Text("Ausblenden").tag(WindowAction.hide)
                            Text("Beenden").tag(WindowAction.quit)
                        }.labelsHidden().frame(width: 130)
                        Toggle(rule.action == .quit ? "Neu starten" : "Zurückholen", isOn: $rule.restore)
                        Spacer()
                        Button(role: .destructive) {
                            model.config.apps.removeAll { $0.bundleId == rule.bundleId }
                        } label: { Image(systemName: "trash") }.buttonStyle(.borderless)
                    }
                }
            }
            HStack {
                Menu("Laufendes Programm hinzufügen") {
                    ForEach(runningApps, id: \.bundleIdentifier) { app in
                        Button(app.localizedName ?? app.bundleIdentifier ?? "?") {
                            guard let id = app.bundleIdentifier,
                                  !model.config.apps.contains(where: { $0.bundleId == id }) else { return }
                            model.config.apps.append(
                                AppRule(bundleId: id, name: app.localizedName ?? id, action: .minimize))
                        }
                    }
                }
                Spacer()
                Button("Speichern") { model.save(password: nil) }
            }
        }
        .padding()
    }

    private var runningApps: [NSRunningApplication] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != Bundle.main.bundleIdentifier }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
    }

    // MARK: General

    private var generalTab: some View {
        Form {
            Section("Browser (JavaScript von Apple Events erlauben)") {
                ForEach(BrowserKind.allCases, id: \.self) { browser in
                    Toggle(browser.displayName, isOn: Binding(
                        get: { model.config.browsers.contains(browser) },
                        set: { on in
                            model.config.browsers.removeAll { $0 == browser }
                            if on { model.config.browsers.append(browser) }
                        }))
                }
            }
            Section("Berechtigungen") {
                HStack {
                    Image(systemName: model.accessibilityTrusted ? "checkmark.circle.fill" : "xmark.circle")
                    Text("Bedienungshilfen (zum Minimieren)")
                    Spacer()
                    if !model.accessibilityTrusted { Button("Anfragen") { model.requestAccessibility() } }
                }
            }
            Toggle("Beim Anmelden starten", isOn: Binding(
                get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) }))
            HStack {
                Spacer()
                Button("Speichern") { model.save(password: nil) }
            }
        }
        .padding()
    }
}
