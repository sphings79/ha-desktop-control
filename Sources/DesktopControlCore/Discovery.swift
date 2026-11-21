import Foundation

/// Home Assistant MQTT Discovery messages for the device.
public enum Discovery {
    /// `audioOutputs` is nil when audio control is unavailable; otherwise the selectable device names.
    public static func messages(topics: Topics, deviceName: String, audioOutputs: [String]? = nil) -> [MQTTMessage] {
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
        return result
    }

    static func json(_ object: [String: Any]) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data("{}".utf8)
        return String(decoding: data, as: UTF8.self)
    }
}
