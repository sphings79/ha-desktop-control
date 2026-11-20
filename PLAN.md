# ha-desktop-control – Plan (Entwurf zur Freigabe)

Stand: 2026-11-21. Umgesetzt; Abweichungen und Ergebnisse der Tests sind unten eingetragen.

## Ziel

Menüleisten-App für macOS (Mac Mini M4). Empfängt per MQTT Kontaktzustände aus Home Assistant
(Fenster-/Türkontakt offen/zu). Bei "offen":

1. Medienwiedergabe im Browser pausieren (YouTube, Netflix, Disney+, RTL+).
2. Konfigurierte Programme/Browserfenster minimieren, ausblenden oder beenden.

Bei "alle zu": nur das zurückholen, was die App selbst getan hat (Fenster wiederherstellen,
Wiedergabe fortsetzen, optional beendete Programme neu starten).

Die App meldet Status per MQTT Discovery an HA zurück.

## Abgrenzung (nicht Teil des Projekts)

- Windows/Linux-Port (nur Idee; Architektur hält die Tür offen).
- Steuerung von Nicht-Browser-Playern (Music, Spotify, VLC).
- Spaces-/Multi-Monitor-Sonderlogik.
- Zeitfenster/Ruhezeiten (macht HA).
- Schreiben auf die HA ohne separate Freigabe.

## Architektur

Swift, SwiftUI-MenuBarExtra, kein Dock-Icon (`LSUIElement`), Start als Login-Item.

```
Core (plattformneutral, später portierbar)
  - MQTT-Anbindung, Discovery, Topic-Schema
  - Regel-Engine (Quelle -> Aktionen), Zustandsverwaltung (offene Quellen, Undo-Journal)
  - Konfiguration (JSON)
Platform/macOS (hinter Protokollen)
  - MediaController   : Browser-Tabs pausieren/fortsetzen
  - WindowController  : minimieren/ausblenden/beenden/wiederherstellen
  - Secrets           : macOS-Schlüsselbund
UI
  - Menüleiste: Status, globaler An/Aus-Schalter, letzte Aktion
  - Einstellungsfenster: Broker, Regeln, Browser, Programme
```

### Medien (Browser)

- Chrome, Brave, Vivaldi (Chromium): AppleScript `execute javascript` im Tab.
- Safari: AppleScript `do JavaScript` im Tab.
- Voraussetzung: "JavaScript von Apple-Events erlauben" pro Browser (einmalig manuell).
- Ablauf: alle Tabs aller Fenster durchsuchen, `<video>`/`<audio>` mit `!paused` finden,
  `pause()` aufrufen, Tab-Identität (Browser, Fenster-ID, Tab-ID) im Journal merken.
  Fortsetzen: nur genau diese Tabs, nur wenn sie noch existieren und pausiert sind.
- Nur Pause/Play per Element, kein globaler Tastendruck-Toggle (kein versehentliches Starten).
- Nicht unterstützt: Opera GX. Der `execute`-Befehl ist im AppleScript-Wörterbuch auskommentiert
  und wird auch als Roh-Ereignis abgelehnt. Eine Browser-Erweiterung wäre die Alternative,
  ist aber nicht Teil dieses Projekts.
- Spike-Ergebnis Brave: YouTube, Netflix, Disney+ und Prime Video lassen sich pausieren und
  fortsetzen (mit und ohne Vollbild, Prime Video Vollbild noch offen). Pro Tab können mehrere
  Medienelemente existieren (Disney+: 2), daher alle prüfen und nur spielende anfassen.
- Vivaldi (YouTube, ohne Vollbild): Pause/Fortsetzen funktioniert, gleiches Verfahren wie Brave.
- Safari: vorerst zurückgestellt (nicht getestet, bleibt im Plan als späterer Schritt).
- Risiko: DRM-Player (Netflix/Disney+/RTL+) und Shadow-DOM/iframes -> im Spike prüfen.

### Fenster

- Accessibility API (AX). Einmalige Freigabe "Bedienungshilfen".
- Aktionen pro Programm: `minimize` | `hide` | `quit`.
- Vollbild: Vollbild verlassen (`AXFullScreen=false`), auf Ende der Animation warten,
  dann minimieren. Beim Zurückholen: wiederherstellen, Vollbild erneut setzen.
- Spike-Ergebnis (Brave, YouTube): Das Video-Vollbild (Element-Vollbild) lässt sich nicht
  wiederherstellen, der Browser verlangt dafür einen echten Klick. Entscheidung: Fenster kommt
  **ohne Vollbild** zurück (Standard). Optionaler Schalter "Fenster-Vollbild wiederherstellen"
  pro Programm später.
- Nach jedem Vollbild-Wechsel das Fenster neu suchen: macOS zeigt währenddessen kurz mehrere
  Fenster derselben App, alte Fensterverweise werden ungültig.
- Journal speichert pro Fenster: App, Fenster, war-Vollbild, war-minimiert.
- `quit`: optional "beim Schließen neu starten" pro Programm.

### Logik

- Zustand: Menge offener Quellen. Reaktion erst beim Übergang 0 -> 1 (Aktionen), Rückholen
  erst beim Übergang 1 -> 0 (nach konfigurierbarer Verzögerung, Standard 10 s).
- Öffnet während der Verzögerung eine Quelle erneut: Rückholen abbrechen.
- Regeln pro Quelle (z. B. Balkontür: nur Medien; Haustür: Medien + Programme).
- Globaler Schalter "aktiv" (Menü + HA-Entität). Aus = keine Aktionen, Zustand wird weiter verfolgt.

## MQTT

Präfix: `ha-desktop-control/<device_id>` (Standard `device_id` = Rechnername, sluggifiziert).

| Topic | Richtung | Payload | Retained |
|---|---|---|---|
| `.../availability` | App -> HA | `online` / `offline` (LWT) | ja |
| `.../contact/<source>` | HA -> App | `open` / `closed` | **ja** |
| `.../enabled/set` | HA -> App | `ON` / `OFF` | nein |
| `.../enabled` | App -> HA | `ON` / `OFF` | ja |
| `.../status` | App -> HA | `idle` / `paused_by_contact` | ja |
| `.../now_playing` | App -> HA | Titel/Browser oder `none` | ja |
| `.../cmd/<action>` | HA -> App | manuelle Aktionen (`pause_media`, `restore`) | nein |

- Discovery unter `homeassistant/...`: ein Gerät mit Schalter (aktiv), Sensoren (Status,
  Läuft gerade), Buttons (Pause, Wiederherstellen), Connectivity (availability).
- Zustandsbasiert statt Ereignisbasiert: retained `contact/<source>` hält den letzten Zustand,
  die App holt ihn nach Neustart/Reconnect selbst nach. Verpasste Ereignisse gehen nicht verloren.
- TLS optional, Benutzer/Passwort im Schlüsselbund, nie in JSON oder Repo.

## HA-Seite (nur als YAML zur Prüfung, nichts wird eingespielt)

Eine Automation pro Kontakt (oder eine mit mehreren Triggern), die den Kontaktzustand
retained auf `ha-desktop-control/<device_id>/contact/<source>` veröffentlicht
(`mqtt.publish` mit `retain: true`). Ich liefere die YAML als Datei zum Prüfen.
Einspielen erst nach deiner Freigabe. Vorher Abgleich mit dem Live-Stand per SSH.

## Konfiguration (JSON)

```json
{
  "broker": { "host": "…", "port": 1883, "tls": false, "username": "…" },
  "deviceId": "mac-mini",
  "resumeDelaySeconds": 10,
  "sources": {
    "balkontuer": { "actions": ["pause_media"] },
    "haustuer":   { "actions": ["pause_media", "windows"] }
  },
  "browsers": ["chrome", "safari", "brave", "vivaldi"],
  "apps": [
    { "bundleId": "…", "action": "minimize", "restore": true }
  ]
}
```

Das Einstellungsfenster schreibt diese Datei; Passwort nur im Schlüsselbund.

## Phasen

0. **Umgebung prüfen:** macOS-Version, Xcode/Swift-Toolchain, Broker erreichbar, Brave/Vivaldi
   AppleScript-Wörterbuch.
1. **Spike (vor dem Ausbau):** Mini-Skripte, die Pause/Fortsetzen testen in Chrome, Safari,
   Brave, Vivaldi mit YouTube, Netflix, Disney+, RTL+ – normal und im Vollbild. Dazu
   Vollbild-verlassen + Minimieren + Wiederherstellen. Ergebnis: Machbarkeitstabelle an dich.
   Wo etwas nicht geht, entscheiden wir gemeinsam, bevor ich weiterbaue.
2. **Core:** Regel-Engine, Journal, Konfiguration, Unit-Tests (reine Logik, ohne Hardware).
3. **MQTT:** Verbindung, Discovery, Topics; Bibliothek wird vor dem Einbau mit dir abgestimmt
   (Pflege/Lizenz geprüft). Test gegen deinen Broker.
4. **Plattformteil:** Media- und Window-Controller aus den Spike-Erkenntnissen.
5. **UI:** Menüleiste + Einstellungsfenster, Login-Item.
6. **HA-YAML** zur Prüfung, End-to-End-Test mit echtem Kontakt (mit deiner Freigabe).
7. **GitHub:** privates Repo `ha-desktop-control`, Topic `sphings79-maintained`,
   README, Commits auf Englisch.

## Test

- Unit-Tests für Regel-Engine/Journal (mehrere Quellen, Verzögerung, Abbruch, An/Aus).
- Manuell: Browser-Matrix aus Phase 1, Vollbild, App-Neustart bei offenem Kontakt,
  Broker-Ausfall/Reconnect, Mac-Ruhezustand.

## Offene Punkte / Risiken

- DRM-Streaming und Vollbild sind ungetestet (Phase 1 klärt das).
- Bedienungshilfen- und Apple-Events-Freigaben sind manuell und gehen nach Neubau einer
  ad-hoc-signierten App ggf. verloren. Mit stabiler Signatur/gleicher Bundle-ID vermeiden.
- Hat der Nutzer während "offen" selbst wieder Play gedrückt: Vorschlag, dann nicht
  erneut pausieren und beim Schließen nichts fortsetzen.
