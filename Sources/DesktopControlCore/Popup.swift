import Foundation

/// Settings of the desktop popup (for example a doorbell with a camera snapshot).
public struct PopupConfig: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var durationSeconds: Double
    /// Name of a macOS system sound; empty means silent.
    public var sound: String
    /// Pause playing media while the popup is shown (and resume afterwards).
    public var pauseMedia: Bool

    public static let fallbackSound = "Glass"

    public init(enabled: Bool = true, durationSeconds: Double = 30, sound: String = PopupConfig.fallbackSound, pauseMedia: Bool = false) {
        self.enabled = enabled
        self.durationSeconds = durationSeconds
        self.sound = sound
        self.pauseMedia = pauseMedia
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = PopupConfig()
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? d.enabled
        durationSeconds = try c.decodeIfPresent(Double.self, forKey: .durationSeconds) ?? d.durationSeconds
        sound = try c.decodeIfPresent(String.self, forKey: .sound) ?? d.sound
        pauseMedia = try c.decodeIfPresent(Bool.self, forKey: .pauseMedia) ?? d.pauseMedia
    }
}

/// A popup request sent by Home Assistant to `<base>/popup`.
///
/// ```json
/// {"title": "Front door", "image": "/api/camera_proxy/camera.x?token=...", "duration": 30,
///  "sound": true, "pause": false}
/// ```
/// `sound`: `true` (configured sound), `false` (silent) or the name of a system sound.
/// `pause`: overrides the app setting. All fields are optional.
public struct PopupRequest: Equatable, Sendable {
    public enum Sound: Equatable, Sendable {
        case setting
        case off
        case on
        case named(String)
    }

    public var title: String
    public var image: String?
    public var duration: Double?
    public var sound: Sound
    public var pause: Bool?

    public static let allowedImagePrefixes = ["/api/camera_proxy/", "/local/"]
    public static let durationRange: ClosedRange<Double> = 3...300

    public init(title: String = "", image: String? = nil, duration: Double? = nil, sound: Sound = .setting, pause: Bool? = nil) {
        self.title = title
        self.image = image
        self.duration = duration
        self.sound = sound
        self.pause = pause
    }

    /// Returns nil for anything that is not a JSON object. An empty payload is a plain popup.
    public static func parse(_ payload: String) -> PopupRequest? {
        let text = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return PopupRequest() }
        guard let object = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any] else { return nil }

        var request = PopupRequest()
        if let title = object["title"] as? String { request.title = String(title.prefix(120)) }
        if let image = object["image"] as? String, !image.isEmpty { request.image = image }
        if let duration = object["duration"] as? Double, duration.isFinite {
            request.duration = min(durationRange.upperBound, max(durationRange.lowerBound, duration))
        }
        switch object["sound"] {
        case let flag as Bool: request.sound = flag ? .on : .off
        case let name as String where name.range(of: #"^[A-Za-z0-9 ]{1,40}$"#, options: .regularExpression) != nil:
            request.sound = .named(name)
        default: break
        }
        if let pause = object["pause"] as? Bool { request.pause = pause }
        return request
    }

    /// Resolves `image` against the configured Home Assistant address. Only camera and `/local`
    /// paths on that same host are accepted, so a message cannot make the app fetch other URLs.
    public func imageURL(base: String) -> URL? {
        guard let image, let baseURL = URL(string: base.trimmingCharacters(in: .whitespaces)),
              let scheme = baseURL.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = baseURL.host else { return nil }

        var path = image
        if image.contains("://") {
            guard let full = URL(string: image),
                  full.scheme?.lowercased() == scheme, full.host == host, full.port == baseURL.port else { return nil }
            path = full.path + (full.query.map { "?\($0)" } ?? "")
        }
        guard path.hasPrefix("/"), !path.contains(".."),
              Self.allowedImagePrefixes.contains(where: { path.hasPrefix($0) }),
              var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else { return nil }
        let pieces = path.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
        components.path = String(pieces[0])
        components.query = pieces.count > 1 ? String(pieces[1]) : nil
        return components.url
    }

    /// The system sound to play, or nil for silence.
    public func soundName(config: PopupConfig) -> String? {
        switch sound {
        case .off: return nil
        case .named(let name): return name
        case .on: return config.sound.isEmpty ? PopupConfig.fallbackSound : config.sound
        case .setting: return config.sound.isEmpty ? nil : config.sound
        }
    }

    public func shouldPause(config: PopupConfig) -> Bool { pause ?? config.pauseMedia }
    public func displaySeconds(config: PopupConfig) -> Double { duration ?? config.durationSeconds }
}

extension AutomationExample {
    /// Home Assistant automation that shows a camera snapshot popup when `entity` turns on.
    public static func popupYAML(deviceId: String, trigger: String = "input_boolean.doorbell", camera: String = "camera.front_door", title: String = "Doorbell") -> String {
        let trigger = isValidEntityId(trigger) ? trigger : "input_boolean.doorbell"
        let camera = isValidEntityId(camera) ? camera : "camera.front_door"
        let title = title.filter { $0.isLetter || $0.isNumber || $0 == " " }
        let topic = Topics(deviceId: deviceId).popup
        return """
        alias: Desktop popup - \(title.isEmpty ? "Doorbell" : title)
        description: Shows a camera snapshot popup on the Mac when \(trigger) turns on.
        mode: single
        triggers:
          - trigger: state
            entity_id: \(trigger)
            from: "off"
            to: "on"
        actions:
          - action: mqtt.publish
            data:
              topic: \(topic)
              retain: false
              payload: >-
                {{ {
                  'title': '\(title.isEmpty ? "Doorbell" : title)',
                  'image': state_attr('\(camera)', 'entity_picture'),
                  'duration': 30,
                  'sound': true
                } | tojson }}

        """
    }
}
