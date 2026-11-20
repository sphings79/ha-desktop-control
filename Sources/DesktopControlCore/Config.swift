import Foundation

/// Chromium-based browsers that expose `execute javascript` via AppleScript.
public enum BrowserKind: String, Codable, CaseIterable, Sendable {
    case brave, vivaldi, chrome

    public var bundleId: String {
        switch self {
        case .brave: return "com.brave.Browser"
        case .vivaldi: return "com.vivaldi.Vivaldi"
        case .chrome: return "com.google.Chrome"
        }
    }

    public var displayName: String {
        switch self {
        case .brave: return "Brave"
        case .vivaldi: return "Vivaldi"
        case .chrome: return "Chrome"
        }
    }
}

public enum SourceAction: String, Codable, Sendable {
    case pauseMedia = "pause_media"
    /// Minimize the browser windows in which media was paused (needs `pauseMedia` first).
    case minimizePausedWindows = "minimize_paused_windows"
    case windows

    /// Fixed execution order, independent of the order in the config.
    var rank: Int {
        switch self {
        case .pauseMedia: return 0
        case .minimizePausedWindows: return 1
        case .windows: return 2
        }
    }
}

public enum WindowAction: String, Codable, CaseIterable, Sendable {
    case minimize, hide, quit
}

public struct AppRule: Codable, Equatable, Identifiable, Sendable {
    public var bundleId: String
    public var name: String
    public var action: WindowAction
    /// Undo the action when all contacts are closed (unminimize / unhide / relaunch).
    public var restore: Bool

    public var id: String { bundleId }

    public init(bundleId: String, name: String, action: WindowAction, restore: Bool = true) {
        self.bundleId = bundleId
        self.name = name
        self.action = action
        self.restore = restore
    }
}

public struct SourceRule: Codable, Equatable, Sendable {
    public var actions: [SourceAction]

    public init(actions: [SourceAction]) {
        self.actions = actions
    }
}

public struct BrokerConfig: Codable, Equatable, Sendable {
    public var host: String
    public var port: Int
    public var tls: Bool
    public var username: String

    public init(host: String = "", port: Int = 1883, tls: Bool = false, username: String = "") {
        self.host = host
        self.port = port
        self.tls = tls
        self.username = username
    }
}

public struct AppConfig: Codable, Equatable, Sendable {
    public var broker: BrokerConfig
    public var deviceId: String
    public var resumeDelaySeconds: Double
    /// Contact source name -> rule. Sources not listed use `AppConfig.fallbackActions`.
    public var sources: [String: SourceRule]
    public var browsers: [BrowserKind]
    public var apps: [AppRule]

    /// Actions for contact sources that have no explicit rule.
    public static let fallbackActions: [SourceAction] = [.pauseMedia]

    public init(
        broker: BrokerConfig = BrokerConfig(),
        deviceId: String = "mac",
        resumeDelaySeconds: Double = 10,
        sources: [String: SourceRule] = [:],
        browsers: [BrowserKind] = [.brave, .vivaldi, .chrome],
        apps: [AppRule] = []
    ) {
        self.broker = broker
        self.deviceId = deviceId
        self.resumeDelaySeconds = resumeDelaySeconds
        self.sources = sources
        self.browsers = browsers
        self.apps = apps
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppConfig()
        broker = try c.decodeIfPresent(BrokerConfig.self, forKey: .broker) ?? d.broker
        deviceId = try c.decodeIfPresent(String.self, forKey: .deviceId) ?? d.deviceId
        resumeDelaySeconds = try c.decodeIfPresent(Double.self, forKey: .resumeDelaySeconds) ?? d.resumeDelaySeconds
        sources = try c.decodeIfPresent([String: SourceRule].self, forKey: .sources) ?? d.sources
        browsers = try c.decodeIfPresent([BrowserKind].self, forKey: .browsers) ?? d.browsers
        apps = try c.decodeIfPresent([AppRule].self, forKey: .apps) ?? d.apps
    }

    public func actions(forSource source: String) -> [SourceAction] {
        sources[source]?.actions ?? AppConfig.fallbackActions
    }
}

/// Loads and saves the JSON configuration. The broker password is never stored here.
public struct ConfigStore {
    public let url: URL

    public init(url: URL = ConfigStore.defaultURL) {
        self.url = url
    }

    public static var defaultURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("ha-desktop-control", isDirectory: true)
            .appendingPathComponent("config.json")
    }

    public func load() -> AppConfig {
        guard let data = try? Data(contentsOf: url),
              let config = try? JSONDecoder().decode(AppConfig.self, from: data) else {
            return AppConfig()
        }
        return config
    }

    public func save(_ config: AppConfig) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(config).write(to: url, options: .atomic)
    }
}
