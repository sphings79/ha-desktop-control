import Foundation

/// MQTT topic layout: `ha-desktop-control/<device_id>/...`
public struct Topics: Sendable {
    public static let root = "ha-desktop-control"
    public static let discoveryPrefix = "homeassistant"

    public let deviceId: String
    public let base: String

    public init(deviceId: String) {
        self.deviceId = Topics.slug(deviceId)
        self.base = "\(Topics.root)/\(self.deviceId)"
    }

    /// Lowercase, `[a-z0-9_]` only, so the id is safe in topics and HA entity ids.
    public static func slug(_ raw: String) -> String {
        let mapped = raw.lowercased().unicodeScalars.map { scalar -> Character in
            switch scalar {
            case "a"..."z", "0"..."9": return Character(scalar)
            default: return "_"
            }
        }
        var result = String(mapped)
        while result.contains("__") { result = result.replacingOccurrences(of: "__", with: "_") }
        result = result.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        return result.isEmpty ? "mac" : result
    }

    public var availability: String { "\(base)/availability" }
    public var contactFilter: String { "\(base)/contact/+" }
    public var enabledSet: String { "\(base)/enabled/set" }
    public var enabledState: String { "\(base)/enabled" }
    public var status: String { "\(base)/status" }
    public var nowPlaying: String { "\(base)/now_playing" }
    public var commandFilter: String { "\(base)/cmd/+" }
    public var popup: String { "\(base)/popup" }
    public var audioSetFilter: String { "\(base)/audio/+/set" }
    public var audioOutput: String { "\(base)/audio/output" }
    public var audioOutputType: String { "\(base)/audio/output_type" }
    public var audioVolume: String { "\(base)/audio/volume" }
    public var audioMuted: String { "\(base)/audio/muted" }
    public func audioSet(_ name: String) -> String { "\(base)/audio/\(name)/set" }

    public func contact(_ source: String) -> String { "\(base)/contact/\(source)" }
    public func command(_ name: String) -> String { "\(base)/cmd/\(name)" }

    /// Returns the source name if `topic` is `<base>/contact/<source>`.
    public func source(fromContactTopic topic: String) -> String? {
        let prefix = "\(base)/contact/"
        guard topic.hasPrefix(prefix) else { return nil }
        let name = String(topic.dropFirst(prefix.count))
        return (name.isEmpty || name.contains("/")) ? nil : name
    }

    /// Returns `volume`, `muted` or `output` if `topic` is `<base>/audio/<name>/set`.
    public func audioSetName(fromTopic topic: String) -> String? {
        let prefix = "\(base)/audio/"
        guard topic.hasPrefix(prefix), topic.hasSuffix("/set") else { return nil }
        let name = String(topic.dropFirst(prefix.count).dropLast(4))
        return (name.isEmpty || name.contains("/")) ? nil : name
    }

    public func commandName(fromTopic topic: String) -> String? {
        let prefix = "\(base)/cmd/"
        guard topic.hasPrefix(prefix) else { return nil }
        let name = String(topic.dropFirst(prefix.count))
        return (name.isEmpty || name.contains("/")) ? nil : name
    }
}
