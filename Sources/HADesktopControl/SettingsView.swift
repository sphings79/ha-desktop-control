import AppKit
import DesktopControlCore
import SwiftUI

// MARK: - Window

struct SettingsView: View {
    @ObservedObject var model: AppModel

    enum Page: String, CaseIterable, Identifiable {
        case overview, contacts, apps, popup, mac, mqtt, general
        var id: String { rawValue }
        var titleKey: String {
            switch self {
            case .overview: return "Overview"
            case .contacts: return "Triggers"
            case .apps: return "Programs"
            case .popup: return "Popup"
            case .mac: return "Mac"
            case .mqtt: return "MQTT"
            case .general: return "General"
            }
        }
        var symbol: String {
            switch self {
            case .overview: return "gauge.with.dots.needle.67percent"
            case .contacts: return "door.left.hand.open"
            case .apps: return "macwindow.on.rectangle"
            case .popup: return "bell.badge"
            case .mac: return "macbook.and.iphone"
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
                Label(model.t(item.titleKey), systemImage: item.symbol).tag(item)
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 180, max: 210)
        } detail: {
            ScrollView {
                Group {
                    switch page ?? .overview {
                    case .overview: OverviewPage(model: model)
                    case .contacts: ContactsPage(model: model)
                    case .apps: AppsPage(model: model)
                    case .popup: PopupPage(model: model)
                    case .mac: MacPage(model: model)
                    case .mqtt: MQTTPage(model: model)
                    case .general: GeneralPage(model: model)
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle(model.t((page ?? .overview).titleKey))
        }
        .frame(minWidth: 760, minHeight: 540)
        .onAppear { model.refreshPermissions() }
        .onChange(of: model.requestedPage) { _, requested in
            if let requested { page = requested; model.requestedPage = nil }
        }
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
    private var heroTitle: String {
        !enabled ? model.t("Disabled") : (paused ? model.t("Paused – trigger active") : model.t("Ready"))
    }
    private var heroSubtitle: String {
        model.snapshot.openSources.isEmpty
            ? model.t("All triggers inactive")
            : model.t("Active: %@", model.snapshot.openSources.joined(separator: ", "))
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

            if let update = model.availableUpdate {
                Card(title: model.t("Update available"), symbol: "arrow.down.circle.fill") {
                    HStack {
                        Text(model.t("Version %@ is available (you have %@).", update.tag, AppModel.currentVersion))
                        Spacer()
                        Button(model.t("Download")) { model.openReleasePage() }
                            .buttonStyle(.borderedProminent)
                    }
                }
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
                    Toggle(model.t("Control active"), isOn: Binding(
                        get: { model.snapshot.enabled }, set: { model.setEnabled($0) }))
                        .toggleStyle(.switch)
                }
            }

            HStack(alignment: .top, spacing: 14) {
                Card(title: model.t("Connection"), symbol: "network", fillHeight: true) {
                    HStack {
                        StatusDot(color: model.mqttConnected ? .green : .red)
                        Text(model.mqttConnected ? model.t("MQTT connected") : model.t("Not connected"))
                    }
                    Hint(model.config.broker.host.isEmpty
                         ? model.t("No broker configured")
                         : model.t("%@:%@ · device “%@”", model.config.broker.host,
                                   String(model.config.broker.port), Topics.slug(model.config.deviceId)))
                }
                Card(title: model.t("Now playing"), symbol: "play.circle", fillHeight: true) {
                    Text(model.nowPlaying.isEmpty ? model.t("Nothing") : model.nowPlaying)
                        .lineLimit(3)
                        .foregroundStyle(model.nowPlaying.isEmpty ? .secondary : .primary)
                    Hint(model.t("Updated every 15 seconds."))
                }
            }
            .fixedSize(horizontal: false, vertical: true)

            Card(title: model.t("Manual"), symbol: "hand.tap") {
                HStack {
                    Button { model.manualPause() } label: {
                        Label(model.t("Pause media"), systemImage: "pause.fill")
                    }
                    Button { model.manualRestore() } label: {
                        Label(model.t("Restore"), systemImage: "arrow.counterclockwise")
                    }
                    Spacer()
                }
                Hint(model.t("Same as the buttons in Home Assistant."))
            }

            Card(title: model.t("Permissions"), symbol: "lock.shield") {
                HStack {
                    StatusDot(color: model.accessibilityTrusted ? .green : .orange)
                    Text(model.t("Accessibility"))
                    Spacer()
                    if model.accessibilityTrusted {
                        Text(model.t("granted")).foregroundStyle(.secondary)
                    } else {
                        Button(model.t("Request")) { model.requestAccessibility() }
                    }
                }
                Hint(model.t("Needed to leave full screen and minimize windows."))
                Divider()
                HStack(alignment: .top) {
                    Image(systemName: "safari").foregroundStyle(.secondary)
                    Hint(model.t("Browser: enable View › Developer › “Allow JavaScript from Apple Events”. macOS asks for the Automation permission the first time media is paused."))
                }
            }
        }
    }
}

// MARK: - Triggers

private struct ContactsPage: View {
    @ObservedObject var model: AppModel
    @State private var newSource = ""
    @State private var expanded: Set<String> = []

    var body: some View {
        VStack(spacing: 14) {
            Hint(model.t("Each source is a trigger: any sensor or other entity from Home Assistant. HA sends `open` (or `on`) when it triggers and `closed` (or `off`) when it ends, to `ha-desktop-control/%@/contact/<name>`. Sources without a rule only pause media.", Topics.slug(model.config.deviceId)))

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
                        .help(model.t("Remove trigger"))
                    }
                    HStack {
                        chip(model.t("Pause video"), "pause.fill", name, .pauseMedia)
                        chip(model.t("Minimize video windows"), "rectangle.bottomhalf.inset.filled", name, .minimizePausedWindows)
                        chip(model.t("Programs"), "macwindow", name, .windows)
                    }
                    Hint(summary(for: name))
                    DisclosureGroup(model.t("Home Assistant automation (YAML)"), isExpanded: Binding(
                        get: { expanded.contains(name) },
                        set: { open in
                            if open { expanded.insert(name) } else { expanded.remove(name) }
                        })) {
                        AutomationGenerator(model: model, source: name)
                    }
                    .font(.callout)
                }
            }

            Card(title: model.t("New trigger"), symbol: "plus.circle") {
                HStack {
                    TextField(model.t("Name, e.g. office_door"), text: $newSource)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(add)
                    Button(model.t("Add"), action: add)
                        .disabled(newSource.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }

            Card(title: model.t("Restoring"), symbol: "timer") {
                Stepper(value: $model.config.resumeDelaySeconds, in: 0...300, step: 5) {
                    Text(model.t("Wait %@ seconds after the last trigger became inactive",
                                 String(Int(model.config.resumeDelaySeconds))))
                }
                Hint(model.t("If a trigger becomes active again in this time, everything stays paused."))
            }
        }
        .onAppear { if model.demoExpandYAML { expanded = ["office_door"] } }
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
        if actions.isEmpty { return model.t("No action – this trigger has no effect.") }
        var parts: [String] = []
        if actions.contains(.pauseMedia) { parts.append(model.t("pauses playing videos")) }
        if actions.contains(.minimizePausedWindows) { parts.append(model.t("minimizes their browser windows")) }
        if actions.contains(.windows) { parts.append(model.t("handles the apps from “Programs”")) }
        return model.t("When triggered: %@.", parts.joined(separator: ", "))
    }

    private func add() {
        let name = Topics.slug(newSource)
        guard !newSource.trimmingCharacters(in: .whitespaces).isEmpty,
              model.config.sources[name] == nil else { return }
        model.config.sources[name] = SourceRule(actions: [.pauseMedia])
        newSource = ""
    }
}

/// Live YAML for the Home Assistant automation that feeds one trigger.
private struct AutomationGenerator: View {
    @ObservedObject var model: AppModel
    var source: String
    @State private var entity = AutomationExample.placeholderEntity

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField(model.t("Entity ID"), text: $entity)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
            if !AutomationExample.isValidEntityId(entity) {
                Hint(model.t("Not a valid entity ID, the placeholder is used."))
            }
            ScrollView {
                Text(model.automationYAML(for: source, entity: entity))
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .frame(height: 200)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06)))
            HStack {
                Hint(model.t("Replace the entity with your sensor. The state is published retained, so the Mac knows it after a restart."))
                Spacer()
                Button {
                    model.copyAutomationYAML(for: source, entity: entity)
                } label: {
                    Label(model.copiedSource == source ? model.t("Copied") : model.t("Copy YAML"),
                          systemImage: model.copiedSource == source ? "checkmark" : "doc.on.doc")
                }
            }
        }
        .padding(.top, 6)
    }
}

// MARK: - Programs

private struct AppsPage: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 14) {
            Hint(model.t("These apps are handled by triggers with the “Programs” option. Only what the app did itself is restored."))

            if model.config.apps.isEmpty {
                Card { Hint(model.t("No programs yet. Add one below.")) }
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
                        Picker(model.t("Action"), selection: $rule.action) {
                            Text(model.t("Minimize")).tag(WindowAction.minimize)
                            Text(model.t("Hide")).tag(WindowAction.hide)
                            Text(model.t("Quit")).tag(WindowAction.quit)
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 340)
                        Spacer()
                        Toggle(rule.action == .quit ? model.t("Relaunch") : model.t("Restore"), isOn: $rule.restore)
                    }
                }
            }

            Card(title: model.t("Add program"), symbol: "plus.circle") {
                HStack {
                    Menu(model.t("Running app …")) {
                        ForEach(runningApps, id: \.bundleIdentifier) { app in
                            Button(app.localizedName ?? app.bundleIdentifier ?? "?") {
                                add(bundleId: app.bundleIdentifier, name: app.localizedName)
                            }
                        }
                    }
                    Button(model.t("Choose from folder …"), action: choose)
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

// MARK: - Popup

private struct PopupPage: View {
    @ObservedObject var model: AppModel
    @State private var trigger = "input_boolean.doorbell"
    @State private var camera = "camera.front_door"

    var body: some View {
        VStack(spacing: 14) {
            Card(title: model.t("Popup"), symbol: "bell.badge") {
                Toggle(model.t("Show popups"), isOn: $model.config.popup.enabled)
                HStack {
                    Text(model.t("Display time: %@ seconds", String(Int(model.config.popup.durationSeconds))))
                    Slider(value: $model.config.popup.durationSeconds, in: 5...120, step: 5)
                }
                HStack {
                    Text(model.t("Sound"))
                    Picker("", selection: $model.config.popup.sound) {
                        Text(model.t("Silent")).tag("")
                        ForEach(AppModel.systemSounds, id: \.self) { Text($0).tag($0) }
                    }
                    .labelsHidden().frame(width: 160)
                    Button(model.t("Preview")) { model.previewSound(model.config.popup.sound) }
                        .disabled(model.config.popup.sound.isEmpty)
                    Spacer()
                }
                Toggle(model.t("Pause video while the popup is shown"), isOn: $model.config.popup.pauseMedia)
                Toggle(model.t("Respect Do Not Disturb"), isOn: Binding(
                    get: { model.config.popup.respectDoNotDisturb },
                    set: { model.setRespectDoNotDisturb($0) }))
                Hint(model.t("Skips popups while a Focus is on, except critical ones. macOS asks for permission once."))
                Hint(model.t("Video resumes when the popup closes. Home Assistant can override sound and pause for each popup."))
                HStack {
                    Spacer()
                    Button(model.t("Show test popup")) { model.testPopup() }
                }
            }

            Card(title: model.t("Camera image"), symbol: "video") {
                TextField("http://homeassistant.local:8123", text: $model.config.haBaseURL)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                Hint(model.t("Home Assistant address, used only to load the camera image of a popup. The image link comes from your automation with a short-lived token, so no password is stored here. HTTPS needs a valid certificate."))
            }

            PopupActionYAML(model: model)

            Card(title: model.t("Home Assistant automation: popup with camera image"), symbol: "doc.text") {
                TextField(model.t("Trigger entity"), text: $trigger)
                    .textFieldStyle(.roundedBorder).font(.system(.body, design: .monospaced))
                TextField(model.t("Camera entity"), text: $camera)
                    .textFieldStyle(.roundedBorder).font(.system(.body, design: .monospaced))
                ScrollView {
                    Text(model.popupYAML(trigger: trigger, camera: camera))
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                }
                .frame(height: 220)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06)))
                HStack {
                    Hint(model.t("Optional fields in the message: duration (seconds), sound (true, false or a system sound name) and pause (true or false)."))
                    Spacer()
                    Button {
                        model.copyPopupYAML(trigger: trigger, camera: camera)
                    } label: {
                        Label(model.copiedPopup ? model.t("Copied") : model.t("Copy YAML"),
                              systemImage: model.copiedPopup ? "checkmark" : "doc.on.doc")
                    }
                }
            }
        }
    }
}

private struct PopupActionYAML: View {
    @ObservedObject var model: AppModel
    @State private var popupId = "window-kids"
    @State private var action = "ignore"

    var body: some View {
        Card(title: model.t("Home Assistant automation: reaction to a button click"), symbol: "hand.tap") {
            HStack {
                TextField(model.t("Popup id"), text: $popupId).textFieldStyle(.roundedBorder)
                TextField(model.t("Action id"), text: $action).textFieldStyle(.roundedBorder)
            }
            .font(.system(.body, design: .monospaced))
            ScrollView {
                Text(model.popupActionYAML(popupId: popupId, action: action))
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .frame(height: 170)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06)))
            Hint(model.t("Add `sticky`, `level` (info, warning, critical), `id`, `url` and up to three `actions` with `id` and `label` to the popup message. The click is sent to this topic."))
        }
    }
}

// MARK: - Mac

private struct MacPage: View {
    @ObservedObject var model: AppModel
    @State private var name = ""
    @State private var kind: CustomCommand.Kind = .shell
    @State private var commandText = ""
    @State private var pending: CustomCommand?

    var body: some View {
        VStack(spacing: 14) {
            Card(title: model.t("Sensors"), symbol: "sensor") {
                Hint(model.t("Camera and microphone in use (yes or no only), idle time and screen lock are sent to Home Assistant."))
                Toggle(model.t("Share the name of the frontmost app"), isOn: $model.config.sensors.activeApp)
                Hint(model.t("Off by default. It shows which app you are using."))
            }

            Card(title: model.t("Control from Home Assistant"), symbol: "power") {
                Toggle(model.t("Sleep"), isOn: $model.config.macControl.sleep)
                Toggle(model.t("Display off"), isOn: $model.config.macControl.displayOff)
                Toggle(model.t("Lock screen"), isOn: $model.config.macControl.lock)
                Hint(model.t("Each command is off by default and shows up in Home Assistant as a button only while it is on."))
            }

            Card(title: model.t("Commands"), symbol: "terminal") {
                Toggle(model.t("Allow commands"), isOn: $model.config.commandsEnabled)
                Hint(model.t("Home Assistant can only press the button of a command listed here. Nothing from MQTT is put into the command line. Commands run with your user rights and are stopped after 30 seconds."))
                ForEach(model.config.commands) { command in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(command.name).font(.headline)
                            Text("\(command.kind == .shell ? model.t("Shell command") : model.t("Shortcut")): \(command.command)")
                                .font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary).lineLimit(2)
                        }
                        Spacer()
                        Button(role: .destructive) {
                            model.config.commands.removeAll { $0.id == command.id }
                        } label: { Image(systemName: "trash") }.buttonStyle(.borderless)
                    }
                    Divider()
                }
                TextField(model.t("Name"), text: $name).textFieldStyle(.roundedBorder)
                Picker("", selection: $kind) {
                    Text(model.t("Shell command")).tag(CustomCommand.Kind.shell)
                    Text(model.t("Shortcut")).tag(CustomCommand.Kind.shortcut)
                }
                .pickerStyle(.segmented).labelsHidden()
                TextField(kind == .shell ? model.t("Command line") : model.t("Shortcut name"), text: $commandText)
                    .textFieldStyle(.roundedBorder).font(.system(.body, design: .monospaced))
                HStack {
                    Spacer()
                    Button(model.t("Add command")) {
                        let candidate = CustomCommand(
                            id: CustomCommand.makeId(name: name, existing: model.config.commands),
                            name: name.trimmingCharacters(in: .whitespacesAndNewlines), kind: kind,
                            command: commandText.trimmingCharacters(in: .whitespacesAndNewlines))
                        if candidate.isValid { pending = candidate }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || commandText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .alert(model.t("Add this command?"), isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } })) {
            Button(model.t("Add command")) {
                if let pending { model.config.commands.append(pending) }
                pending = nil
                name = ""
                commandText = ""
            }
            Button(model.t("Cancel"), role: .cancel) { pending = nil }
        } message: {
            Text("\(model.t("It runs with your user rights whenever Home Assistant presses its button:"))\n\n\(pending?.command ?? "")")
        }
    }
}

// MARK: - MQTT

private struct MQTTPage: View {
    @ObservedObject var model: AppModel
    @State private var password = ""

    var body: some View {
        VStack(spacing: 14) {
            Card(title: model.t("Broker"), symbol: "server.rack") {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                    GridRow {
                        Text(model.t("Host"))
                        TextField("", text: $model.config.broker.host).textFieldStyle(.roundedBorder)
                    }
                    GridRow {
                        Text(model.t("Port"))
                        TextField("", value: $model.config.broker.port, format: .number.grouping(.never))
                            .textFieldStyle(.roundedBorder).frame(width: 100)
                    }
                    GridRow {
                        Text(model.t("User"))
                        TextField("", text: $model.config.broker.username).textFieldStyle(.roundedBorder)
                    }
                    GridRow {
                        Text(model.t("Password"))
                        SecureField("", text: $password).textFieldStyle(.roundedBorder)
                    }
                    GridRow {
                        Text(model.t("Encryption"))
                        Toggle(model.t("TLS (1.2 or newer)"), isOn: $model.config.broker.tls)
                    }
                }
                Hint(model.t("The password is stored in the macOS Keychain, never in the config file."))
            }

            Card(title: model.t("Device"), symbol: "desktopcomputer") {
                HStack {
                    Text(model.t("Device ID"))
                    TextField("", text: $model.config.deviceId).textFieldStyle(.roundedBorder)
                }
                Hint(model.t("Topics: ha-desktop-control/%@/…", Topics.slug(model.config.deviceId)))
            }

            HStack {
                StatusDot(color: model.mqttConnected ? .green : .red)
                Text(model.mqttConnected ? model.t("Connected") : model.t("Not connected"))
                Spacer()
                Button(model.t("Save & connect")) { model.save(password: password) }
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
            Card(title: model.t("Browsers"), symbol: "globe") {
                ForEach(BrowserKind.allCases, id: \.self) { browser in
                    let installed = NSWorkspace.shared.urlForApplication(withBundleIdentifier: browser.bundleId) != nil
                    HStack {
                        Image(nsImage: appIcon(bundleId: browser.bundleId)).resizable().frame(width: 24, height: 24)
                        Text(browser.displayName)
                        if !installed { Text(model.t("not installed")).font(.caption).foregroundStyle(.secondary) }
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
                Hint(model.t("Chromium browsers via AppleScript. Safari and Opera GX are not supported."))
            }

            Card(title: model.t("Appearance"), symbol: "circle.lefthalf.filled") {
                Picker(model.t("Appearance"), selection: $model.config.appearance) {
                    Text(model.t("System")).tag(AppearanceMode.system)
                    Text(model.t("Light")).tag(AppearanceMode.light)
                    Text(model.t("Dark")).tag(AppearanceMode.dark)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 320)
                Hint(model.t("“System” follows the macOS setting."))
            }

            Card(title: model.t("Language"), symbol: "globe.europe.africa") {
                Picker(model.t("Language"), selection: $model.config.language) {
                    Text(model.t("System")).tag(AppLanguage.system)
                    Text("Deutsch").tag(AppLanguage.de)
                    Text("English").tag(AppLanguage.en)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 320)
            }

            Card(title: model.t("Start"), symbol: "power") {
                Toggle(model.t("Launch at login"), isOn: Binding(
                    get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) }))
            }

            Card(title: model.t("Permissions"), symbol: "lock.shield") {
                HStack {
                    StatusDot(color: model.accessibilityTrusted ? .green : .orange)
                    Text(model.t("Accessibility"))
                    Spacer()
                    if model.accessibilityTrusted {
                        Text(model.t("granted")).foregroundStyle(.secondary)
                    } else {
                        Button(model.t("Request")) { model.requestAccessibility() }
                    }
                }
            }

            Card(title: model.t("About"), symbol: "info.circle") {
                HStack {
                    Text(model.t("Version %@", AppModel.currentVersion)).font(.headline)
                    Spacer()
                    Button(model.t("Check for updates")) { model.checkForUpdates() }
                        .disabled(model.updateState == .checking)
                }
                HStack {
                    switch model.updateState {
                    case .checking: Text(model.t("Checking …"))
                    case .failed: Text(model.t("Could not check for updates.")).foregroundStyle(.orange)
                    case .upToDate(let date):
                        if let update = model.availableUpdate {
                            Text(model.t("Update available: %@", update.tag))
                            Button(model.t("Download")) { model.openReleasePage() }
                        } else {
                            Text("\(model.t("Up to date")) · \(model.t("Last checked: %@", date.formatted(date: .abbreviated, time: .shortened)))")
                                .foregroundStyle(.secondary)
                        }
                    case .idle: EmptyView()
                    }
                }
                .font(.callout)
                Toggle(model.t("Automatically check for updates"), isOn: $model.config.checkForUpdates)
                Hint(model.t("Checks GitHub once a day for a new release. GitHub sees your IP address and the app version."))
            }
        }
    }
}
