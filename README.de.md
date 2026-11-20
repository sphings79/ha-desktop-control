<div align="center">

<img src="docs/app-icon.png" alt="HA Desktop Control App-Icon: ein Fenster mit Pause-Symbol" width="140">

# HA Desktop Control

**Pausiert YouTube, Netflix & Co. und minimiert Browserfenster auf deinem Mac, wenn ein Home-Assistant-Tür- oder Fensterkontakt öffnet.**

Eine native macOS-Menüleisten-App, die Home Assistant über MQTT zuhört.

[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue?logo=apple)](#voraussetzungen)
[![Swift 6](https://img.shields.io/badge/Swift-6-orange?logo=swift)](Package.swift)
[![Home Assistant](https://img.shields.io/badge/Home%20Assistant-MQTT%20Discovery-41BDF5?logo=homeassistant&logoColor=white)](#einrichtung-in-home-assistant)
[![Neuestes Release](https://img.shields.io/github/v/release/sphings79/ha-desktop-control?label=Release)](https://github.com/sphings79/ha-desktop-control/releases/latest)
[![Lizenz: MIT](https://img.shields.io/badge/Lizenz-MIT-green)](LICENSE)
[![Buy Me a Coffee](https://img.shields.io/badge/Buy%20me%20a%20coffee-sphings-FFDD00?logo=buymeacoffee&logoColor=black)](https://buymeacoffee.com/sphings)

[English](README.md) · **Deutsch**

</div>

---

## Was die App macht

Du öffnest eine Tür oder ein Fenster, und dein Mac reagiert: Das Video, das du gerade schaust, stoppt, und das Browserfenster, in dem es lief, verschwindet. Schließt der Kontakt wieder, kommt alles genau so zurück, wie es war.

HA Desktop Control verbindet deinen Mac über **MQTT** mit **Home Assistant**. Ein Tür-, Fenster- oder anderer `binary_sensor` meldet `open` oder `closed`. Die App pausiert dann Medien im Browser und minimiert, blendet aus oder beendet auf Wunsch weitere Programme. Rückgängig macht sie nur, was sie selbst getan hat.

**Typische Anwendungen**

- Netflix, YouTube, Disney+ oder Prime Video am Mac pausieren, wenn jemand die Bürotür öffnet.
- Das Videofenster verstecken, wenn ein Fensterkontakt öffnet, und beim Schließen zurückholen.
- Den Bildschirm im Homeoffice automatisch abschirmen, wenn jemand hereinkommt (Privatsphäre).
- Jede Home-Assistant-Automation, die Wiedergabe oder Fenster unter macOS steuern soll.

## Funktionen

- **Browser-Videos pausieren und fortsetzen** in Chromium-Browsern (Brave, Vivaldi, Chrome) per AppleScript, auch im Vollbild.
- **Das Browserfenster minimieren, in dem das Video lief** (nicht alle Fenster), nachdem der Vollbildmodus verlassen wurde.
- **Programme ausblenden, minimieren oder beenden**, pro Kontakt einstellbar, mit optionalem Zurückholen.
- **Regeln pro Kontakt:** verschiedene Türen und Fenster lösen verschiedene Aktionen aus.
- **Sicheres Rückgängigmachen:** Es wird nur wiederhergestellt, was die App selbst pausiert oder minimiert hat. Drückst du zwischendurch selbst Play, wird nichts doppelt angefasst.
- **Verzögerung beim Zurückholen** nach dem Schließen des letzten Kontakts (Standard 10 s). Erneutes Öffnen bricht sie ab.
- **Mehrere Kontakte gleichzeitig:** Zurückgeholt wird erst, wenn der letzte geschlossen ist.
- **Home Assistant MQTT Discovery:** Der Mac erscheint als Gerät mit Schalter, Status-Sensor, „Läuft gerade“-Sensor und zwei Buttons.
- **Retained Kontaktzustände:** Die App kennt den aktuellen Zustand nach einem Neustart oder einer Wiederverbindung sofort.
- **Native Menüleisten-App** in Swift/SwiftUI mit Einstellungsfenster, Start bei der Anmeldung und dem Broker-Passwort im macOS-Schlüsselbund.
- **TLS (ab 1.2)** und automatische Wiederverbindung mit wachsender Wartezeit.

## So funktioniert es

```
Tür-/Fensterkontakt ──► Home Assistant ──► MQTT-Broker ──► HA Desktop Control (macOS)
   binary_sensor          Automation        retained            │
                          mqtt.publish      open | closed       ├─ <video>/<audio> in Browser-Tabs pausieren
                                                                ├─ das Fenster mit dem Video minimieren
                                                                └─ Programme ausblenden / minimieren / beenden
```

## Unterstützte Browser und Dienste

| Browser | Status |
|---|---|
| Brave | getestet |
| Vivaldi | getestet (YouTube) |
| Google Chrome | gleiche AppleScript-Schnittstelle wie Brave, hier nicht getestet |
| Safari | noch nicht unterstützt |
| Opera GX | nicht möglich: Im AppleScript-Wörterbuch ist das Ausführen von JavaScript abgeschaltet |

Getestet mit YouTube, Netflix, Disney+ und Prime Video in Brave, auch im Vollbild. RTL+ ist ungetestet. Das Pausieren arbeitet mit den `<video>`- und `<audio>`-Elementen der Seite, daher funktionieren andere Streamingseiten meist ebenfalls.

> **Vollbild:** Ein Video im Vollbild wird zuerst verlassen, damit das Fenster minimiert werden kann. Browser erlauben Video-Vollbild nur nach einem echten Klick, deshalb kann die App es nicht wiederherstellen. Das Fenster kommt ohne Vollbild zurück.

## Voraussetzungen

- macOS 14 (Sonoma) oder neuer, getestet unter macOS 27 mit Apple Silicon
- Xcode / Swift-6-Toolchain zum Bauen aus dem Quelltext
- Home Assistant mit der **MQTT-Integration** und ein MQTT-Broker (z. B. Mosquitto)
- In jedem Browser: **Ansicht › Entwickler › JavaScript von Apple Events erlauben**

## Installation

### Variante 1: Release herunterladen

1. Lade `HADesktopControl-<version>-macos-arm64.zip` vom [neuesten Release](https://github.com/sphings79/ha-desktop-control/releases/latest) herunter, entpacke es und verschiebe **HADesktopControl.app** nach `/Programme`.
2. Die App ist **nicht notarisiert** (Ad-hoc-Signatur). Beim ersten Start per Rechtsklick auf **Öffnen** gehen oder ausführen:
   ```sh
   xattr -dr com.apple.quarantine /Applications/HADesktopControl.app
   ```

Voraussetzung: Apple Silicon (arm64) und macOS 14+.

### Variante 2: aus dem Quelltext bauen

```sh
git clone https://github.com/sphings79/ha-desktop-control.git
cd ha-desktop-control
swift test                      # optional: Unit-Tests ausführen
./scripts/build_app.sh          # erzeugt build/HADesktopControl.app
ditto build/HADesktopControl.app /Applications/HADesktopControl.app
open /Applications/HADesktopControl.app
```

**Tipp:** Signiere mit einem festen Zertifikat, sonst fragt macOS nach jedem Neubau erneut nach den Berechtigungen:

```sh
SIGN_IDENTITY="<Zertifikatsname oder Hash>" ./scripts/build_app.sh
```

Ein kostenloses *Apple Development*-Zertifikat aus Xcode reicht (`security find-identity -v -p codesigning`).

## Einrichtung

1. App starten. In der Menüleiste erscheint ein Fenster-Symbol.
2. **Einstellungen › MQTT:** Host, Port, Benutzer und Passwort eintragen, eine **Geräte-ID** wählen (z. B. `mac_mini`) und auf *Speichern & verbinden* klicken.
3. **Einstellungen › Übersicht:** Die Berechtigung **Bedienungshilfen** erteilen (nötig, um den Vollbildmodus zu verlassen und Fenster zu minimieren).
4. Im Browser **JavaScript von Apple Events erlauben** einschalten. macOS fragt beim ersten Pausieren nach der **Automation**-Freigabe.
5. **Einstellungen › Kontakte:** Einen Kontakt hinzufügen (der Name ist der letzte Teil des Topics) und seine Aktionen wählen.

### Einrichtung in Home Assistant

Die App legt das MQTT-Discovery-Gerät automatisch an. Für jeden Kontakt legst du eine Automation an, die den Zustand **retained** veröffentlicht:

```yaml
alias: Desktop control - Bürotür
mode: queued
max_exceeded: silent
triggers:
  - trigger: state
    entity_id: binary_sensor.buerotuer_kontakt
  - trigger: homeassistant
    event: start
  - trigger: mqtt
    topic: homeassistant/status
    payload: online
actions:
  - choose:
      - conditions:
          - condition: state
            entity_id: binary_sensor.buerotuer_kontakt
            state: "on"
        sequence:
          - action: mqtt.publish
            data:
              topic: ha-desktop-control/mac_mini/contact/buerotuer
              payload: open
              retain: true
      - conditions:
          - condition: state
            entity_id: binary_sensor.buerotuer_kontakt
            state: "off"
        sequence:
          - action: mqtt.publish
            data:
              topic: ha-desktop-control/mac_mini/contact/buerotuer
              payload: closed
              retain: true
```

Ersetze Entität, Geräte-ID (`mac_mini`) und Kontaktname (`buerotuer`). Weitere Beispiele liegen in [`ha/`](ha/).

## MQTT-Topics

Präfix: `ha-desktop-control/<device_id>`

| Topic | Richtung | Payload | Retained |
|---|---|---|---|
| `…/contact/<source>` | HA → App | `open` / `closed` (auch `on` / `off`) | ja |
| `…/enabled/set` | HA → App | `ON` / `OFF` | nein |
| `…/cmd/pause_media` | HA → App | `PRESS` | nein |
| `…/cmd/restore` | HA → App | `PRESS` | nein |
| `…/availability` | App → HA | `online` / `offline` (Last Will) | ja |
| `…/enabled` | App → HA | `ON` / `OFF` | ja |
| `…/status` | App → HA | `idle` / `paused_by_contact` | ja |
| `…/now_playing` | App → HA | Tab-Titel oder `none` | ja |

## Aktionen pro Kontakt

| Aktion | Wirkung |
|---|---|
| Video pausieren | Pausiert alle laufenden Medienelemente in den eingestellten Browsern |
| Video-Fenster minimieren | Minimiert die Browserfenster, in denen ein Video pausiert wurde |
| Programme | Wendet die Regeln der Seite *Programme* an: minimieren, ausblenden oder beenden |

Unbekannte Kontakte pausieren standardmäßig nur das Video.

## Datenschutz und Sicherheit

- Die App spricht nur mit **deinem eigenen MQTT-Broker**. Es gibt keinen Cloud-Dienst und keine Telemetrie.
- Das Broker-Passwort liegt im **macOS-Schlüsselbund**, nie in der Konfigurationsdatei.
- Die Konfigurationsdatei (`~/Library/Application Support/ha-desktop-control/config.json`) enthält keine Geheimnisse.
- Der Sensor „Läuft gerade“ sendet den Titel des spielenden Browser-Tabs an deinen Broker.
- Nutze TLS am Broker, wenn er über dein vertrauenswürdiges Netz hinaus erreichbar ist.

## Fehlersuche

| Problem | Prüfen |
|---|---|
| Video wird nicht pausiert | *JavaScript von Apple Events erlauben* im Browser; Automation-Freigabe für HA Desktop Control unter Systemeinstellungen › Datenschutz & Sicherheit |
| Fenster wird nicht minimiert | Bedienungshilfen-Freigabe (die Übersicht zeigt den Status) |
| Freigabe nach einem Update weg | Mit festem Zertifikat signieren, siehe [Installation](#installation) |
| Kein Gerät in Home Assistant | MQTT-Integration aktiv, Discovery-Präfix `homeassistant`, Verbindungsstatus im Menü prüfen |
| Beim Kontakt passiert nichts | Das Topic muss `ha-desktop-control/<device_id>/contact/<name>` lauten. Der Name braucht eine Regel, sonst gilt *Video pausieren* |

## FAQ

**Kann ich Home-Assistant-Mediaplayer vom Mac aus steuern?** Nein, diese App arbeitet andersherum: Home Assistant steuert den Mac.

**Funktioniert es mit Spotify oder Apple Music?** Noch nicht. Die App zielt auf Videos im Browser über die Medienelemente der Seite.

**Gibt es das für Windows oder Linux?** Nein, nur für macOS. Der Kern (MQTT, Regeln) ist von der Plattform getrennt, ein Port wäre später möglich.

**Warum MQTT und kein Webhook?** Mit retained Nachrichten holt der Mac nach einem Neustart den aktuellen Kontaktzustand nach, und du brauchst nur den Broker, den du für Home Assistant ohnehin betreibst.

## Entwicklung

```sh
swift build
swift test          # 24 Unit-Tests: Regel-Engine, Topics, Konfiguration, MQTT-Bridge
```

Das Projekt besteht aus `DesktopControlCore` (Regeln, Topics, Discovery, MQTT-Bridge; plattformunabhängig) und `HADesktopControl` (macOS: AppleScript, Bedienungshilfen, Oberfläche). Entwurf und Testergebnisse stehen in [`PLAN.md`](PLAN.md).

MQTT läuft über [MQTT-Nio](https://github.com/swift-server-community/mqtt-nio) (Apache-2.0).

## Das Projekt unterstützen

Wenn HA Desktop Control dir einen zu spät pausierten Filmabend erspart:

- ⭐ **Gib dem Repository einen Stern**, damit andere es leichter finden.
- ☕ **[Spendier mir einen Kaffee](https://buymeacoffee.com/sphings)**, wenn du die Weiterentwicklung unterstützen willst.

Issues und Ideen sind willkommen.

## Lizenz

[MIT](LICENSE) © sphings79
