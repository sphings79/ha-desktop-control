import Foundation

/// Settings of the desktop popup (for example a doorbell with a camera snapshot).
public struct PopupConfig: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var durationSeconds: Double
    /// Name of a macOS system sound; empty means silent.
    public var sound: String
    /// Pause playing media while the popup is shown (and resume afterwards).
    public var pauseMedia: Bool
    /// Skip popups while a macOS Focus (Do Not Disturb) is on. Critical popups still show.
    public var respectDoNotDisturb: Bool

    public static let fallbackSound = "Glass"

    public init(enabled: Bool = true, durationSeconds: Double = 30, sound: String = PopupConfig.fallbackSound,
                pauseMedia: Bool = false, respectDoNotDisturb: Bool = false) {
        self.enabled = enabled
        self.durationSeconds = durationSeconds
        self.sound = sound
        self.pauseMedia = pauseMedia
        self.respectDoNotDisturb = respectDoNotDisturb
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = PopupConfig()
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? d.enabled
        durationSeconds = try c.decodeIfPresent(Double.self, forKey: .durationSeconds) ?? d.durationSeconds
        sound = try c.decodeIfPresent(String.self, forKey: .sound) ?? d.sound
        pauseMedia = try c.decodeIfPresent(Bool.self, forKey: .pauseMedia) ?? d.pauseMedia
        respectDoNotDisturb = try c.decodeIfPresent(Bool.self, forKey: .respectDoNotDisturb) ?? d.respectDoNotDisturb
    }
}

/// Crop of the camera image, same meaning as `crop` / `crop_aspect_ratio` of the Home Assistant
/// integration advanced_snapshot: `[x, y, width, height]` in pixels of the original image.
/// With an aspect ratio the height is calculated from the width and the given height is ignored.
public struct ImageCrop: Equatable, Sendable {
    public var x: Int, y: Int, width: Int
    public var height: Int?
    public var aspect: (Int, Int)?

    public init(x: Int, y: Int, width: Int, height: Int? = nil, aspect: (Int, Int)? = nil) {
        self.x = x; self.y = y; self.width = width; self.height = height; self.aspect = aspect
    }

    public static func == (a: ImageCrop, b: ImageCrop) -> Bool {
        a.x == b.x && a.y == b.y && a.width == b.width && a.height == b.height
            && a.aspect?.0 == b.aspect?.0 && a.aspect?.1 == b.aspect?.1
    }

    /// nil if the values are unusable, so the caller shows the whole image instead.
    public static func parse(crop: Any?, aspect: Any?) -> ImageCrop? {
        guard let list = crop as? [Any], list.count == 3 || list.count == 4 else { return nil }
        let numbers = list.compactMap { item -> Int? in
            guard let number = item as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
            return Int(exactly: number.doubleValue.rounded())
        }
        guard numbers.count == list.count, numbers[0] >= 0, numbers[1] >= 0, numbers[2] > 0 else { return nil }
        var ratio: (Int, Int)?
        if let text = aspect as? String {
            let parts = text.split(separator: ":")
            guard text.range(of: #"^\d{1,4}:\d{1,4}$"#, options: .regularExpression) != nil,
                  let w = Int(parts[0]), let h = Int(parts[1]), w > 0, h > 0 else { return nil }
            ratio = (w, h)
        } else if aspect != nil {
            return nil
        }
        return ImageCrop(x: numbers[0], y: numbers[1], width: numbers[2],
                         height: numbers.count == 4 ? numbers[3] : nil, aspect: ratio)
    }

    /// The pixel rectangle to cut out of an image of the given size; nil if it does not fit.
    public func rect(imageWidth: Int, imageHeight: Int) -> (x: Int, y: Int, width: Int, height: Int)? {
        let h: Int
        if let aspect { h = width * aspect.1 / aspect.0 } else if let height { h = height } else { return nil }
        guard h > 0, x + width <= imageWidth, y + h <= imageHeight else { return nil }
        return (x, y, width, h)
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

    public enum Level: String, Sendable {
        case info, warning, critical
    }

    public struct Action: Equatable, Sendable {
        public var id: String
        public var label: String
        public init(id: String, label: String) { self.id = id; self.label = label }
    }

    public var title: String
    public var image: String?
    public var duration: Double?
    public var sound: Sound
    public var pause: Bool?
    /// A new popup with the same id replaces the open one.
    public var id: String?
    public var level: Level
    /// Opens this address (on the Home Assistant host) from a button, e.g. a live view.
    public var url: String?
    /// Stays until it is closed or an action button is clicked.
    public var sticky: Bool
    public var actions: [Action]
    /// Shows only this part of the image in the popup (the large view can show everything).
    public var crop: ImageCrop?

    public static let maxActions = 3

    public static let allowedImagePrefixes = ["/api/camera_proxy/", "/local/"]
    public static let durationRange: ClosedRange<Double> = 3...300

    public init(title: String = "", image: String? = nil, duration: Double? = nil, sound: Sound = .setting,
                pause: Bool? = nil, id: String? = nil, level: Level = .info, url: String? = nil,
                sticky: Bool = false, actions: [Action] = [], crop: ImageCrop? = nil) {
        self.title = title
        self.image = image
        self.duration = duration
        self.sound = sound
        self.pause = pause
        self.id = id
        self.level = level
        self.url = url
        self.sticky = sticky
        self.actions = actions
        self.crop = crop
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
        if let id = object["id"] as? String, id.range(of: #"^[A-Za-z0-9_-]{1,60}$"#, options: .regularExpression) != nil {
            request.id = id
        }
        if let level = object["level"] as? String, let parsed = Level(rawValue: level) { request.level = parsed }
        if let url = object["url"] as? String, !url.isEmpty { request.url = url }
        if let sticky = object["sticky"] as? Bool { request.sticky = sticky }
        request.crop = ImageCrop.parse(crop: object["crop"], aspect: object["crop_aspect_ratio"])
        if let list = object["actions"] as? [[String: Any]] {
            request.actions = list.compactMap { entry in
                guard let id = entry["id"] as? String, let label = entry["label"] as? String,
                      id.range(of: #"^[A-Za-z0-9_-]{1,40}$"#, options: .regularExpression) != nil,
                      !label.isEmpty else { return nil }
                return Action(id: id, label: String(label.prefix(30)))
            }
            request.actions = Array(request.actions.prefix(maxActions))
        }
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

    /// `url` resolved against the Home Assistant address; only the same host and port are allowed.
    public func openURL(base: String) -> URL? {
        guard let url, let baseURL = URL(string: base.trimmingCharacters(in: .whitespaces)),
              let scheme = baseURL.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = baseURL.host else { return nil }
        let target: URL?
        if url.hasPrefix("/") && !url.hasPrefix("//") {
            target = URL(string: url, relativeTo: baseURL)?.absoluteURL
        } else {
            target = URL(string: url)
        }
        guard let target, target.scheme?.lowercased() == scheme, target.host == host, target.port == baseURL.port else { return nil }
        return target
    }

    /// Seconds until the popup closes by itself; nil for sticky popups.
    public func autoCloseSeconds(config: PopupConfig) -> Double? {
        sticky ? nil : displaySeconds(config: config)
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

    /// Home Assistant automation that reacts to a click on a popup action button.
    public static func popupActionYAML(deviceId: String, popupId: String = "window-kids", action: String = "ignore") -> String {
        let valid = #"^[A-Za-z0-9_-]{1,60}$"#
        let popupId = popupId.range(of: valid, options: .regularExpression) != nil ? popupId : "window-kids"
        let action = action.range(of: valid, options: .regularExpression) != nil ? action : "ignore"
        return """
        alias: Desktop popup - \(popupId) / \(action)
        description: Runs when "\(action)" is clicked in the popup "\(popupId)" on the Mac.
        mode: queued
        triggers:
          - trigger: mqtt
            topic: \(Topics(deviceId: deviceId).action)
        conditions:
          - condition: template
            value_template: >-
              {{ trigger.payload_json.id == '\(popupId)' and trigger.payload_json.action == '\(action)' }}
        actions:
          - action: logbook.log
            data:
              name: Desktop popup
              message: Button \(action) was clicked in \(popupId)

        """
    }
}
