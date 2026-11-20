import AppKit
import DesktopControlCore
import SwiftUI

// MARK: - Window

struct SettingsView: View {
    @ObservedObject var model: AppModel

    enum Page: String, CaseIterable, Identifiable {
        case overview, contacts, apps, mqtt, general
        var id: String { rawValue }
        var title: String {
            switch self {
            case .overview: return "Übersicht"
            case .contacts: return "Auslöser"
            case .apps: return "Programme"
            case .mqtt: return "MQTT"
            case .general: return "Allgemein"
            }
        }
        var symbol: String {
            switch self {
            case .overview: return "gauge.with.dots.needle.67percent"
            case .contacts: return "door.left.hand.open"
            case .apps: return "macwindow.on.rectangle"
            case .mqtt: return "network"
            case .general: return "gearshape"
            }
        }
    }

    @State private var page: Page?

    init(model: AppModel, page: Page = .overview) {
        self.model = model
        _page = State(initialValue: page)
    }

    var body: some View {
        NavigationSplitView {
            List(Page.allCases, selection: $page) { item in
                Label(item.title, systemImage: item.symbol).tag(item)
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 180, max: 210)
        } detail: {
            ScrollView {
                Group {
                    switch page ?? .overview {
                    case .overview: OverviewPage(model: model)
                    case .contacts: ContactsPage(model: model)
                    case .apps: AppsPage(model: model)
                    case .mqtt: MQTTPage(model: model)
                    case .general: GeneralPage(model: model)
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle((page ?? .overview).title)
        }
        .frame(minWidth: 760, minHeight: 540)
        .onAppear { model.refreshPermissions() }
    }
}

// MARK: - Building blocks

private struct Card<Content: View>: View {
    var title: String?
    var symbol: String?
    var tint: Color = .accentColor
    /// Stretch to the row height so neighbouring cards line up.
    var fillHeight = false
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title {
                Label {
                    Text(title).font(.headline)
                } icon: {
                    if let symbol { Image(systemName: symbol).foregroundStyle(tint) }
                }
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: fillHeight ? .infinity : nil, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.primary.opacity(0.08)))
    }
}

private struct StatusDot: View {
    var color: Color
    var body: some View { Circle().fill(color).frame(width: 9, height: 9) }
}

private struct Hint: View {
    var text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(LocalizedStringKey(text)).font(.caption).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private func appIcon(bundleId: String) -> NSImage {
    if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
        return NSWorkspace.shared.icon(forFile: url.path)
    }
    return NSImage(systemSymbolName: "app.dashed", accessibilityDescription: nil) ?? NSImage()
}

// MARK: - Overview

private struct OverviewPage: View {
    @ObservedObject var model: AppModel

    private var paused: Bool { model.snapshot.status == .pausedByContact }
    private var enabled: Bool { model.snapshot.enabled }

    private var heroSymbol: String {
        !enabled ? "slash.circle.fill" : (paused ? "pause.circle.fill" : "checkmark.circle.fill")
    }
    private var heroColor: Color { !enabled ? .gray : (paused ? .orange : .green) }
    private var heroTitle: String { !enabled ? "Deaktiviert" : (paused ? "Pausiert – Auslöser aktiv" : "Bereit") }
    private var heroSubtitle: String {
        model.snapshot.openSources.isEmpty
            ? "Alle Auslöser inaktiv"
            : "Aktiv: " + model.snapshot.openSources.joined(separator: ", ")
    }

    var body: some View {
        VStack(spacing: 14) {
            if let error = model.lastError {
                HStack(alignment: .top) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text(error).font(.callout).textSelection(.enabled)
                    Spacer()
                    Button { model.dismissError() } label: { Image(systemName: "xmark") }
                        .buttonStyle(.borderless)
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.orange.opacity(0.14)))
            }

            Card {
                HStack(spacing: 16) {
                    Image(systemName: heroSymbol)
                        .font(.system(size: 44))
                        .foregroundStyle(heroColor)
                        .symbolRenderingMode(.hierarchical)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(heroTitle).font(.title2.weight(.semibold))
                        Text(heroSubtitle).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("Steuerung aktiv", isOn: Binding(
                        get: { model.snapshot.enabled }, set: { model.setEnabled($0) }))
                        .toggleStyle(.switch)
                }
            }

            HStack(alignment: .top, spacing: 14) {
                Card(title: "Verbindung", symbol: "network", fillHeight: true) {
                    HStack {
                        StatusDot(color: model.mqttConnected ? .green : .red)
                        Text(model.mqttConnected ? "MQTT verbunden" : "Nicht verbunden")
                    }
                    Hint(model.config.broker.host.isEmpty
                         ? "Kein Broker eingetragen"
                         : "\(model.config.broker.host):\(model.config.broker.port) · Gerät „\(Topics.slug(model.config.deviceId))“")
                }
                Card(title: "Läuft gerade", symbol: "play.circle", fillHeight: true) {
                    Text(model.nowPlaying.isEmpty ? "Nichts" : model.nowPlaying)
                        .lineLimit(3)
                        .foregroundStyle(model.nowPlaying.isEmpty ? .secondary : .primary)
                    Hint("Wird alle 15 Sekunden aktualisiert.")
                }
            }
            .fixedSize(horizontal: false, vertical: true)

            Card(title: "Manuell", symbol: "hand.tap") {
                HStack {
                    Button { model.manualPause() } label: { Label("Medien pausieren", systemImage: "pause.fill") }
                    Button { model.manualRestore() } label: {
                        Label("Wiederherstellen", systemImage: "arrow.counterclockwise")
                    }
                    Spacer()
                }
                Hint("Dasselbe wie die Buttons in Home Assistant.")
            }

            Card(title: "Berechtigungen", symbol: "lock.shield") {
                HStack {
                    StatusDot(color: model.accessibilityTrusted ? .green : .orange)
                    Text("Bedienungshilfen")
                    Spacer()
                    if model.accessibilityTrusted {
                        Text("erteilt").foregroundStyle(.secondary)
                    } else {
                        Button("Anfragen") { model.requestAccessibility() }
                    }
                }
                Hint("Nötig, um Fenster im Vollbild zu verlassen und zu minimieren.")
                Divider()
                HStack(alignment: .top) {
                    Image(systemName: "safari").foregroundStyle(.secondary)
                    Hint("Browser: Menü Ansicht › Entwickler › „JavaScript von Apple Events erlauben“ einschalten. macOS fragt beim ersten Pausieren nach der Automation-Freigabe.")
                }
            }
        }
    }
}

// MARK: - Contacts

private struct ContactsPage: View {
    @ObservedObject var model: AppModel
    @State private var newSource = ""

    var body: some View {
        VStack(spacing: 14) {
            Hint("Jede Quelle ist ein Auslöser, also ein beliebiger Sensor oder eine andere Entität aus Home Assistant. HA sendet `open` (oder `on`) beim Auslösen und `closed` (oder `off`) beim Beenden an `ha-desktop-control/\(Topics.slug(model.config.deviceId))/contact/<Name>`. Quellen ohne Regel pausieren nur Medien.")

            ForEach(model.config.sources.keys.sorted(), id: \.self) { name in
                Card {
                    HStack {
                        Image(systemName: "door.left.hand.open").foregroundStyle(Color.accentColor)
                        Text(name).font(.headline.monospaced())
                        Spacer()
                        Button(role: .destructive) { model.config.sources[name] = nil } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .help("Quelle entfernen")
                    }
                    HStack {
                        chip("Video pausieren", "pause.fill", name, .pauseMedia)
                        chip("Video-Fenster minimieren", "rectangle.bottomhalf.inset.filled", name, .minimizePausedWindows)
                        chip("Programme", "macwindow", name, .windows)
                    }
                    Hint(summary(for: name))
                }
            }

            Card(title: "Neuer Auslöser", symbol: "plus.circle") {
                HStack {
                    TextField("Name, z. B. buero_tuer", text: $newSource)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(add)
                    Button("Hinzufügen", action: add)
                        .disabled(newSource.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }

            Card(title: "Zurückholen", symbol: "timer") {
                Stepper(value: $model.config.resumeDelaySeconds, in: 0...300, step: 5) {
                    Text("Erst \(Int(model.config.resumeDelaySeconds)) Sekunden nachdem der letzte Auslöser inaktiv wurde")
                }
                Hint("Wird in dieser Zeit ein Auslöser erneut aktiv, bleibt alles pausiert.")
            }
        }
    }

    private func chip(_ title: String, _ symbol: String, _ source: String, _ action: SourceAction) -> some View {
        Toggle(isOn: binding(source, action)) {
            Label(title, systemImage: symbol).font(.callout)
        }
        .toggleStyle(.button)
    }

    private func binding(_ source: String, _ action: SourceAction) -> Binding<Bool> {
        Binding(
            get: { model.config.sources[source]?.actions.contains(action) ?? false },
            set: { on in
                var actions = model.config.sources[source]?.actions ?? []
                actions.removeAll { $0 == action }
                if on { actions.append(action) }
                model.config.sources[source] = SourceRule(actions: actions)
            })
    }

    private func summary(for source: String) -> String {
        let actions = model.config.sources[source]?.actions ?? []
        if actions.isEmpty { return "Keine Aktion – dieser Auslöser hat keine Wirkung." }
        var parts: [String] = []
        if actions.contains(.pauseMedia) { parts.append("pausiert laufende Videos") }
        if actions.contains(.minimizePausedWindows) { parts.append("minimiert deren Browserfenster") }
        if actions.contains(.windows) { parts.append("behandelt die Programme aus „Programme“") }
        return "Beim Auslösen: " + parts.joined(separator: ", ") + "."
    }

    private func add() {
        let name = Topics.slug(newSource)
        guard !newSource.trimmingCharacters(in: .whitespaces).isEmpty,
              model.config.sources[name] == nil else { return }
        model.config.sources[name] = SourceRule(actions: [.pauseMedia])
        newSource = ""
    }
}

// MARK: - Apps

private struct AppsPage: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 14) {
            Hint("Diese Programme werden bei Auslösern mit der Option „Programme“ behandelt. Zurückgeholt wird nur, was die App selbst getan hat.")

            if model.config.apps.isEmpty {
                Card { Hint("Noch keine Programme. Füge unten eines hinzu.") }
            }

            ForEach($model.config.apps) { $rule in
                Card {
                    HStack(spacing: 12) {
                        Image(nsImage: appIcon(bundleId: rule.bundleId))
                            .resizable().frame(width: 36, height: 36)
                        VStack(alignment: .leading) {
                            Text(rule.name).font(.headline)
                            Text(rule.bundleId).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(role: .destructive) {
                            model.config.apps.removeAll { $0.bundleId == rule.bundleId }
                        } label: { Image(systemName: "trash") }
                            .buttonStyle(.borderless)
                    }
                    HStack {
                        Picker("Aktion", selection: $rule.action) {
                            Text("Minimieren").tag(WindowAction.minimize)
                            Text("Ausblenden").tag(WindowAction.hide)
                            Text("Beenden").tag(WindowAction.quit)
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 300)
                        Spacer()
                        Toggle(rule.action == .quit ? "Neu starten" : "Zurückholen", isOn: $rule.restore)
                    }
                }
            }

            Card(title: "Programm hinzufügen", symbol: "plus.circle") {
                HStack {
                    Menu("Laufendes Programm …") {
                        ForEach(runningApps, id: \.bundleIdentifier) { app in
                            Button(app.localizedName ?? app.bundleIdentifier ?? "?") {
                                add(bundleId: app.bundleIdentifier, name: app.localizedName)
                            }
                        }
                    }
                    Button("Aus Ordner wählen …", action: choose)
                    Spacer()
                }
            }
        }
    }

    private var runningApps: [NSRunningApplication] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != Bundle.main.bundleIdentifier }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
    }

    private func add(bundleId: String?, name: String?) {
        guard let bundleId, !model.config.apps.contains(where: { $0.bundleId == bundleId }) else { return }
        model.config.apps.append(AppRule(bundleId: bundleId, name: name ?? bundleId, action: .minimize))
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url, let bundle = Bundle(url: url) else { return }
        let name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? url.deletingPathExtension().lastPathComponent
        add(bundleId: bundle.bundleIdentifier, name: name)
    }
}

// MARK: - MQTT

private struct MQTTPage: View {
    @ObservedObject var model: AppModel
    @State private var password = ""

    var body: some View {
        VStack(spacing: 14) {
            Card(title: "Broker", symbol: "server.rack") {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                    GridRow {
                        Text("Host")
                        TextField("", text: $model.config.broker.host).textFieldStyle(.roundedBorder)
                    }
                    GridRow {
                        Text("Port")
                        TextField("", value: $model.config.broker.port, format: .number.grouping(.never))
                            .textFieldStyle(.roundedBorder).frame(width: 100)
                    }
                    GridRow {
                        Text("Benutzer")
                        TextField("", text: $model.config.broker.username).textFieldStyle(.roundedBorder)
                    }
                    GridRow {
                        Text("Passwort")
                        SecureField("", text: $password).textFieldStyle(.roundedBorder)
                    }
                    GridRow {
                        Text("Verschlüsselung")
                        Toggle("TLS (mindestens 1.2)", isOn: $model.config.broker.tls)
                    }
                }
                Hint("Das Passwort liegt im macOS-Schlüsselbund, nie in der Konfigurationsdatei.")
            }

            Card(title: "Gerät", symbol: "desktopcomputer") {
                HStack {
                    Text("Geräte-ID")
                    TextField("", text: $model.config.deviceId).textFieldStyle(.roundedBorder)
                }
                Hint("Topics: ha-desktop-control/\(Topics.slug(model.config.deviceId))/…")
            }

            HStack {
                StatusDot(color: model.mqttConnected ? .green : .red)
                Text(model.mqttConnected ? "Verbunden" : "Nicht verbunden")
                Spacer()
                Button("Speichern & verbinden") { model.save(password: password) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .onAppear { password = model.storedPassword() }
    }
}

// MARK: - General

private struct GeneralPage: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 14) {
            Card(title: "Browser", symbol: "globe") {
                ForEach(BrowserKind.allCases, id: \.self) { browser in
                    let installed = NSWorkspace.shared.urlForApplication(withBundleIdentifier: browser.bundleId) != nil
                    HStack {
                        Image(nsImage: appIcon(bundleId: browser.bundleId)).resizable().frame(width: 24, height: 24)
                        Text(browser.displayName)
                        if !installed { Text("nicht installiert").font(.caption).foregroundStyle(.secondary) }
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { model.config.browsers.contains(browser) },
                            set: { on in
                                model.config.browsers.removeAll { $0 == browser }
                                if on { model.config.browsers.append(browser) }
                            }))
                            .labelsHidden()
                            .disabled(!installed)
                    }
                }
                Hint("Chromium-Browser mit AppleScript. Safari und Opera GX werden nicht unterstützt.")
            }

            Card(title: "Darstellung", symbol: "circle.lefthalf.filled") {
                Picker("Darstellung", selection: $model.config.appearance) {
                    Text("System").tag(AppearanceMode.system)
                    Text("Hell").tag(AppearanceMode.light)
                    Text("Dunkel").tag(AppearanceMode.dark)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 320)
                Hint("„System“ folgt der Einstellung von macOS.")
            }

            Card(title: "Start", symbol: "power") {
                Toggle("Beim Anmelden starten", isOn: Binding(
                    get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) }))
            }

            Card(title: "Berechtigungen", symbol: "lock.shield") {
                HStack {
                    StatusDot(color: model.accessibilityTrusted ? .green : .orange)
                    Text("Bedienungshilfen")
                    Spacer()
                    if model.accessibilityTrusted {
                        Text("erteilt").foregroundStyle(.secondary)
                    } else {
                        Button("Anfragen") { model.requestAccessibility() }
                    }
                }
            }
        }
    }
}
