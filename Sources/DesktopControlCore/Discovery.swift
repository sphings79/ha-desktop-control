import Foundation

/// Optional parts of the discovery set; everything is off unless enabled.
public struct DiscoveryOptions: Equatable, Sendable {
    public var audioOutputs: [String]?
    public var sensors = false
    public var activeApp = false
    public var macControl = MacControlConfig()
    public var commands: [CustomCommand] = []

    public init(audioOutputs: [String]? = nil, sensors: Bool = false, activeApp: Bool = false,
                macControl: MacControlConfig = MacControlConfig(), commands: [CustomCommand] = []) {
        self.audioOutputs = audioOutputs
        self.sensors = sensors
        self.activeApp = activeApp
        self.macControl = macControl
        self.commands = commands
    }
}

/// Home Assistant MQTT Discovery messages for the device.
public enum Discovery {
    public static func messages(topics: Topics, deviceName: String, audioOutputs: [String]?) -> [MQTTMessage] {
        messages(topics: topics, deviceName: deviceName, options: DiscoveryOptions(audioOutputs: audioOutputs))
    }

    public static func messages(topics: Topics, deviceName: String, options: DiscoveryOptions) -> [MQTTMessage] {
        let audioOutputs = options.audioOutputs
        let device: [String: Any] = [
            "identifiers": ["ha_desktop_control_\(topics.deviceId)"],
            "name": deviceName,
            "manufacturer": "sphings79",
            "model": "ha-desktop-control"
        ]
        let availability: [String: Any] = [
            "availability_topic": topics.availability,
            "payload_available": "online",
            "payload_not_available": "offline"
        ]

        func entity(_ component: String, _ objectId: String, _ fields: [String: Any]) -> MQTTMessage {
            var payload = fields
            payload["unique_id"] = "\(topics.deviceId)_\(objectId)"
            payload["device"] = device
            payload["has_entity_name"] = true
            for (key, value) in availability { payload[key] = value }
            let topic = "\(Topics.discoveryPrefix)/\(component)/\(topics.deviceId)/\(objectId)/config"
            return MQTTMessage(topic: topic, payload: json(payload), retain: true)
        }

        var result = [
            entity("switch", "enabled", [
                "name": "Steuerung aktiv",
                "state_topic": topics.enabledState,
                "command_topic": topics.enabledSet,
                "payload_on": "ON",
                "payload_off": "OFF",
                "icon": "mdi:window-open-variant"
            ]),
            entity("sensor", "status", [
                "name": "Status",
                "state_topic": topics.status,
                "device_class": "enum",
                "options": ["idle", "paused_by_contact"],
                "icon": "mdi:motion-pause"
            ]),
            entity("sensor", "now_playing", [
                "name": "Läuft gerade",
                "state_topic": topics.nowPlaying,
                "icon": "mdi:play-circle-outline"
            ]),
            entity("button", "pause_media", [
                "name": "Medien pausieren",
                "command_topic": topics.command("pause_media"),
                "payload_press": "PRESS",
                "icon": "mdi:pause"
            ]),
            entity("button", "restore", [
                "name": "Wiederherstellen",
                "command_topic": topics.command("restore"),
                "payload_press": "PRESS",
                "icon": "mdi:restore"
            ])
        ]
        if let outputs = audioOutputs {
            result += [
                entity("select", "audio_output", [
                    "name": "Ausgabegerät",
                    "state_topic": topics.audioOutput,
                    "command_topic": topics.audioSet("output"),
                    "options": outputs,
                    "icon": "mdi:speaker"
                ]),
                entity("sensor", "audio_output_type", [
                    "name": "Ausgabetyp",
                    "state_topic": topics.audioOutputType,
                    "device_class": "enum",
                    "options": AudioOutputKind.allCases.map(\.rawValue),
                    "icon": "mdi:headphones"
                ]),
                entity("number", "audio_volume", [
                    "name": "Lautstärke",
                    "state_topic": topics.audioVolume,
                    "command_topic": topics.audioSet("volume"),
                    "min": 0,
                    "max": 100,
                    "step": 1,
                    "unit_of_measurement": "%",
                    "icon": "mdi:volume-high"
                ]),
                entity("switch", "audio_muted", [
                    "name": "Stumm",
                    "state_topic": topics.audioMuted,
                    "command_topic": topics.audioSet("muted"),
                    "payload_on": "ON",
                    "payload_off": "OFF",
                    "icon": "mdi:volume-off"
                ])
            ]
        }
        if options.sensors {
            result += [
                entity("binary_sensor", "camera_in_use", [
                    "name": "Kamera in Benutzung",
                    "state_topic": topics.sensor("camera_in_use"),
                    "payload_on": "ON", "payload_off": "OFF",
                    "icon": "mdi:webcam"
                ]),
                entity("binary_sensor", "microphone_in_use", [
                    "name": "Mikrofon in Benutzung",
                    "state_topic": topics.sensor("microphone_in_use"),
                    "payload_on": "ON", "payload_off": "OFF",
                    "icon": "mdi:microphone"
                ]),
                entity("binary_sensor", "screen_locked", [
                    "name": "Bildschirm gesperrt",
                    "state_topic": topics.sensor("screen_locked"),
                    "payload_on": "ON", "payload_off": "OFF",
                    "icon": "mdi:monitor-lock"
                ]),
                entity("sensor", "idle_seconds", [
                    "name": "Inaktiv seit",
                    "state_topic": topics.sensor("idle_seconds"),
                    "device_class": "duration",
                    "unit_of_measurement": "s",
                    "state_class": "measurement",
                    "icon": "mdi:timer-sand"
                ])
            ]
            if options.activeApp {
                result.append(entity("sensor", "active_app", [
                    "name": "Aktive App",
                    "state_topic": topics.sensor("active_app"),
                    "icon": "mdi:application"
                ]))
            }
        }
        let mac = options.macControl
        if mac.sleep {
            result.append(entity("button", "mac_sleep", [
                "name": "Ruhezustand", "command_topic": topics.command("mac_sleep"),
                "payload_press": "PRESS", "icon": "mdi:sleep"]))
        }
        if mac.displayOff {
            result.append(entity("button", "mac_display_off", [
                "name": "Display aus", "command_topic": topics.command("mac_display_off"),
                "payload_press": "PRESS", "icon": "mdi:monitor-off"]))
        }
        if mac.lock {
            result.append(entity("button", "mac_lock", [
                "name": "Bildschirm sperren", "command_topic": topics.command("mac_lock"),
                "payload_press": "PRESS", "icon": "mdi:lock"]))
        }
        if !options.commands.isEmpty {
            for command in options.commands {
                result.append(entity("button", "run_\(command.id)", [
                    "name": command.name,
                    "command_topic": topics.command("run_\(command.id)"),
                    "payload_press": "PRESS",
                    "icon": "mdi:console"
                ]))
            }
            result.append(entity("sensor", "last_command", [
                "name": "Letzter Befehl",
                "state_topic": topics.lastCommand,
                "json_attributes_topic": topics.lastCommandAttributes,
                "icon": "mdi:console-line"
            ]))
        }
        return result
    }

    static func json(_ object: [String: Any]) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data("{}".utf8)
        return String(decoding: data, as: UTF8.self)
    }
}
