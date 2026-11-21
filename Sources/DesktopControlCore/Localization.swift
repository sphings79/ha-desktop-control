import Foundation

/// UI language choice stored in the config.
public enum AppLanguage: String, Codable, CaseIterable, Sendable {
    case system, en, de
}

/// English text is the key; only the German translations live in the table.
/// Placeholders are always `%@` so argument types cannot clash.
public enum L10n {
    public static func resolve(_ choice: AppLanguage, preferred: [String] = Locale.preferredLanguages) -> AppLanguage {
        switch choice {
        case .en, .de: return choice
        case .system:
            let first = preferred.first?.lowercased() ?? "en"
            return first.hasPrefix("de") ? .de : .en
        }
    }

    public static func tr(_ key: String, _ args: [String] = [], language: AppLanguage) -> String {
        let template = language == .de ? (de[key] ?? key) : key
        guard !args.isEmpty else { return template }
        var result = ""
        var remaining = args[...]
        var index = template.startIndex
        while index < template.endIndex {
            if template[index...].hasPrefix("%@"), let next = remaining.first {
                result += next
                remaining = remaining.dropFirst()
                index = template.index(index, offsetBy: 2)
            } else {
                result.append(template[index])
                index = template.index(after: index)
            }
        }
        return result
    }

    public static let de: [String: String] = [
        // Menu
        "Ready": "Bereit",
        "Paused (trigger active)": "Pausiert (Auslöser aktiv)",
        "Active: %@": "Aktiv: %@",
        "MQTT: connected": "MQTT: verbunden",
        "MQTT: not connected": "MQTT: nicht verbunden",
        "Playing: %@": "Läuft: %@",
        "Control active": "Steuerung aktiv",
        "Pause media": "Medien pausieren",
        "Restore": "Wiederherstellen",
        "Settings …": "Einstellungen …",
        "Quit": "Beenden",
        "Update available: %@": "Update verfügbar: %@",
        "Version %@": "Version %@",
        // Pages
        "Overview": "Übersicht",
        "Triggers": "Auslöser",
        "Programs": "Programme",
        "MQTT": "MQTT",
        "General": "Allgemein",
        // Overview
        "Disabled": "Deaktiviert",
        "Paused – trigger active": "Pausiert – Auslöser aktiv",
        "All triggers inactive": "Alle Auslöser inaktiv",
        "Connection": "Verbindung",
        "MQTT connected": "MQTT verbunden",
        "Not connected": "Nicht verbunden",
        "No broker configured": "Kein Broker eingetragen",
        "%@:%@ · device “%@”": "%@:%@ · Gerät „%@“",
        "Now playing": "Läuft gerade",
        "Nothing": "Nichts",
        "Updated every 15 seconds.": "Wird alle 15 Sekunden aktualisiert.",
        "Manual": "Manuell",
        "Same as the buttons in Home Assistant.": "Dasselbe wie die Buttons in Home Assistant.",
        "Permissions": "Berechtigungen",
        "Accessibility": "Bedienungshilfen",
        "granted": "erteilt",
        "Request": "Anfragen",
        "Needed to leave full screen and minimize windows.": "Nötig, um Fenster im Vollbild zu verlassen und zu minimieren.",
        "Browser: enable View › Developer › “Allow JavaScript from Apple Events”. macOS asks for the Automation permission the first time media is paused.":
            "Browser: Menü Ansicht › Entwickler › „JavaScript von Apple Events erlauben“ einschalten. macOS fragt beim ersten Pausieren nach der Automation-Freigabe.",
        "Update available": "Update verfügbar",
        "Version %@ is available (you have %@).": "Version %@ ist verfügbar (installiert: %@).",
        "Download": "Herunterladen",
        // Triggers
        "Each source is a trigger: any sensor or other entity from Home Assistant. HA sends `open` (or `on`) when it triggers and `closed` (or `off`) when it ends, to `ha-desktop-control/%@/contact/<name>`. Sources without a rule only pause media.":
            "Jede Quelle ist ein Auslöser, also ein beliebiger Sensor oder eine andere Entität aus Home Assistant. HA sendet `open` (oder `on`) beim Auslösen und `closed` (oder `off`) beim Beenden an `ha-desktop-control/%@/contact/<Name>`. Quellen ohne Regel pausieren nur Medien.",
        "Pause video": "Video pausieren",
        "Minimize video windows": "Video-Fenster minimieren",
        "Remove trigger": "Auslöser entfernen",
        "Home Assistant automation (YAML)": "Home-Assistant-Automation (YAML)",
        "Entity ID": "Entität (Entity-ID)",
        "Copy YAML": "YAML kopieren",
        "Copied": "Kopiert",
        "Replace the entity with your sensor. The state is published retained, so the Mac knows it after a restart.":
            "Ersetze die Entität durch deinen Sensor. Der Zustand wird retained veröffentlicht, damit der Mac ihn nach einem Neustart kennt.",
        "Not a valid entity ID, the placeholder is used.": "Keine gültige Entity-ID, es wird der Platzhalter verwendet.",
        "No action – this trigger has no effect.": "Keine Aktion – dieser Auslöser hat keine Wirkung.",
        "pauses playing videos": "pausiert laufende Videos",
        "minimizes their browser windows": "minimiert deren Browserfenster",
        "handles the apps from “Programs”": "behandelt die Programme aus „Programme“",
        "When triggered: %@.": "Beim Auslösen: %@.",
        "New trigger": "Neuer Auslöser",
        "Name, e.g. office_door": "Name, z. B. buero_tuer",
        "Add": "Hinzufügen",
        "Restoring": "Zurückholen",
        "Wait %@ seconds after the last trigger became inactive": "Erst %@ Sekunden warten, nachdem der letzte Auslöser inaktiv wurde",
        "If a trigger becomes active again in this time, everything stays paused.": "Wird in dieser Zeit ein Auslöser erneut aktiv, bleibt alles pausiert.",
        // Programs
        "These apps are handled by triggers with the “Programs” option. Only what the app did itself is restored.":
            "Diese Programme werden bei Auslösern mit der Option „Programme“ behandelt. Zurückgeholt wird nur, was die App selbst getan hat.",
        "No programs yet. Add one below.": "Noch keine Programme. Füge unten eines hinzu.",
        "Action": "Aktion",
        "Minimize": "Minimieren",
        "Hide": "Ausblenden",
        "Relaunch": "Neu starten",
        "Add program": "Programm hinzufügen",
        "Running app …": "Laufendes Programm …",
        "Choose from folder …": "Aus Ordner wählen …",
        // MQTT
        "Broker": "Broker",
        "Host": "Host",
        "Port": "Port",
        "User": "Benutzer",
        "Password": "Passwort",
        "Encryption": "Verschlüsselung",
        "TLS (1.2 or newer)": "TLS (ab 1.2)",
        "The password is stored in the macOS Keychain, never in the config file.": "Das Passwort liegt im macOS-Schlüsselbund, nie in der Konfigurationsdatei.",
        "Device": "Gerät",
        "Device ID": "Geräte-ID",
        "Topics: ha-desktop-control/%@/…": "Topics: ha-desktop-control/%@/…",
        "Connected": "Verbunden",
        "Save & connect": "Speichern & verbinden",
        // General
        "Browsers": "Browser",
        "not installed": "nicht installiert",
        "Chromium browsers via AppleScript. Safari and Opera GX are not supported.": "Chromium-Browser über AppleScript. Safari und Opera GX werden nicht unterstützt.",
        "Appearance": "Darstellung",
        "System": "System",
        "Light": "Hell",
        "Dark": "Dunkel",
        "“System” follows the macOS setting.": "„System“ folgt der Einstellung von macOS.",
        "Language": "Sprache",
        "Start": "Start",
        "Launch at login": "Beim Anmelden starten",
        "About": "Über",
        "Check for updates": "Nach Updates suchen",
        "Checking …": "Suche …",
        "Up to date": "Auf dem neuesten Stand",
        "Last checked: %@": "Zuletzt geprüft: %@",
        "Automatically check for updates": "Automatisch nach Updates suchen",
        "Checks GitHub once a day for a new release. GitHub sees your IP address and the app version.":
            "Fragt einmal täglich bei GitHub nach einem neuen Release. GitHub sieht dabei deine IP-Adresse und die App-Version.",
        "Could not check for updates.": "Update-Prüfung fehlgeschlagen.",
        // Setup guide
        "Welcome to HA Desktop Control": "Willkommen bei HA Desktop Control",
        "A few permissions are needed so your Mac can react to Home Assistant. This window updates by itself.":
            "Damit dein Mac auf Home Assistant reagieren kann, braucht die App ein paar Freigaben. Dieses Fenster aktualisiert sich selbst.",
        "Setup guide …": "Einrichtungsassistent …",
        "Connect to your MQTT broker": "Mit deinem MQTT-Broker verbinden",
        "Not connected yet": "Noch nicht verbunden",
        "Open MQTT settings": "MQTT-Einstellungen öffnen",
        "Accessibility access": "Zugriff über Bedienungshilfen",
        "Lets the app leave full screen and minimize windows.": "Damit die App den Vollbildmodus verlassen und Fenster minimieren kann.",
        "Allowed": "Erlaubt",
        "Not allowed yet": "Noch nicht erlaubt",
        "Open Accessibility settings": "Bedienungshilfen-Einstellungen öffnen",
        "Browser control": "Browser-Steuerung",
        "Start your browser, then enable View › Developer › “Allow JavaScript from Apple Events”. macOS asks for Automation access the first time media is paused.":
            "Starte deinen Browser und schalte Ansicht › Entwickler › „JavaScript von Apple Events erlauben“ ein. macOS fragt beim ersten Pausieren nach dem Automation-Zugriff.",
        "Automation": "Automation",
        "JavaScript from Apple Events": "JavaScript von Apple Events",
        "allowed": "erlaubt",
        "not allowed yet": "noch nicht erlaubt",
        "on": "an",
        "off": "aus",
        "not running": "läuft nicht",
        "open a window to check": "Fenster öffnen zum Prüfen",
        "No browser is running. Start one to check its permissions.": "Kein Browser läuft. Starte einen, um seine Freigaben zu prüfen.",
        "Open Automation settings": "Automation-Einstellungen öffnen",
        "Create your first trigger": "Ersten Auslöser anlegen",
        "Add a trigger and copy the generated Home Assistant automation.": "Lege einen Auslöser an und kopiere die erzeugte Home-Assistant-Automation.",
        "Open triggers": "Auslöser öffnen",
        "Done": "Fertig",
        // Popup
        "Popup": "Popup",
        "Show popups": "Popups anzeigen",
        "Display time: %@ seconds": "Anzeigedauer: %@ Sekunden",
        "Sound": "Ton",
        "Silent": "Stumm",
        "Preview": "Anhören",
        "Pause video while the popup is shown": "Video pausieren, solange das Popup sichtbar ist",
        "Video resumes when the popup closes. Home Assistant can override sound and pause for each popup.":
            "Das Video läuft weiter, wenn das Popup schließt. Home Assistant kann Ton und Pause pro Popup überschreiben.",
        "Show test popup": "Test-Popup anzeigen",
        "Test popup": "Test-Popup",
        "Doorbell": "Klingel",
        "Camera image": "Kamerabild",
        "Home Assistant address, used only to load the camera image of a popup. The image link comes from your automation with a short-lived token, so no password is stored here. HTTPS needs a valid certificate.":
            "Adresse von Home Assistant, nur zum Laden des Kamerabilds eines Popups. Der Bildlink kommt mit einem kurzlebigen Token aus deiner Automation, hier wird also kein Passwort gespeichert. HTTPS braucht ein gültiges Zertifikat.",
        "Home Assistant automation: popup with camera image": "Home-Assistant-Automation: Popup mit Kamerabild",
        "Trigger entity": "Auslösende Entität",
        "Camera entity": "Kamera-Entität",
        "Home Assistant automation: reaction to a button click": "Home-Assistant-Automation: Reaktion auf einen Button-Klick",
        "Popup id": "Popup-ID",
        "Action id": "Aktions-ID",
        "Add `sticky`, `level` (info, warning, critical), `id`, `url` and up to three `actions` with `id` and `label` to the popup message. The click is sent to this topic.":
            "Ergänze in der Popup-Nachricht `sticky`, `level` (info, warning, critical), `id`, `url` und bis zu drei `actions` mit `id` und `label`. Der Klick wird an dieses Topic gesendet.",
        "Open live view": "Live-Ansicht öffnen",
        "Respect Do Not Disturb": "„Nicht stören“ beachten",
        "Skips popups while a Focus is on, except critical ones. macOS asks for permission once.":
            "Überspringt Popups, solange ein Fokus aktiv ist, außer kritische. macOS fragt einmalig nach der Freigabe.",
        // Mac
        "Mac": "Mac",
        "Sensors": "Sensoren",
        "Camera and microphone in use (yes or no only), idle time and screen lock are sent to Home Assistant.":
            "Kamera und Mikrofon in Benutzung (nur Ja oder Nein), Inaktivität und Bildschirmsperre gehen an Home Assistant.",
        "Share the name of the frontmost app": "Namen der aktiven App weitergeben",
        "Off by default. It shows which app you are using.": "Standardmäßig aus. Es zeigt, welche App du gerade nutzt.",
        "Control from Home Assistant": "Steuerung durch Home Assistant",
        "Sleep": "Ruhezustand",
        "Display off": "Display aus",
        "Lock screen": "Bildschirm sperren",
        "Each command is off by default and shows up in Home Assistant as a button only while it is on.":
            "Jeder Befehl ist standardmäßig aus und erscheint nur dann als Button in Home Assistant, wenn er an ist.",
        "Commands": "Befehle",
        "Allow commands": "Befehle erlauben",
        "Home Assistant can only press the button of a command listed here. Nothing from MQTT is put into the command line. Commands run with your user rights and are stopped after 30 seconds.":
            "Home Assistant kann nur den Button eines hier aufgeführten Befehls drücken. Aus MQTT wird nichts in die Befehlszeile eingesetzt. Befehle laufen mit deinen Benutzerrechten und werden nach 30 Sekunden abgebrochen.",
        "Shell command": "Shell-Befehl",
        "Shortcut": "Kurzbefehl",
        "Name": "Name",
        "Command line": "Befehlszeile",
        "Shortcut name": "Name des Kurzbefehls",
        "Add command": "Befehl hinzufügen",
        "Add this command?": "Diesen Befehl hinzufügen?",
        "It runs with your user rights whenever Home Assistant presses its button:":
            "Er läuft mit deinen Benutzerrechten, sobald Home Assistant seinen Button drückt:",
        "Cancel": "Abbrechen",
        "Optional fields in the message: duration (seconds), sound (true, false or a system sound name) and pause (true or false).":
            "Optionale Felder in der Nachricht: duration (Sekunden), sound (true, false oder Name eines Systemtons) und pause (true oder false)."
    ]
}
