import Foundation

/// Optional sensor settings. Everything that reveals what you do stays off by default.
public struct SensorConfig: Codable, Equatable, Sendable {
    /// Publish the name of the frontmost app.
    public var activeApp: Bool

    public init(activeApp: Bool = false) { self.activeApp = activeApp }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        activeApp = try c.decodeIfPresent(Bool.self, forKey: .activeApp) ?? false
    }
}

/// Which power/lock commands Home Assistant may send. All off by default.
public struct MacControlConfig: Codable, Equatable, Sendable {
    public var sleep: Bool
    public var displayOff: Bool
    public var lock: Bool

    public init(sleep: Bool = false, displayOff: Bool = false, lock: Bool = false) {
        self.sleep = sleep
        self.displayOff = displayOff
        self.lock = lock
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sleep = try c.decodeIfPresent(Bool.self, forKey: .sleep) ?? false
        displayOff = try c.decodeIfPresent(Bool.self, forKey: .displayOff) ?? false
        lock = try c.decodeIfPresent(Bool.self, forKey: .lock) ?? false
    }
}

/// A command the user defined in the app. Home Assistant can only press its button by name;
/// nothing from MQTT is ever put into the command line.
public struct CustomCommand: Codable, Equatable, Identifiable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Sendable {
        case shell
        case shortcut
    }

    public var id: String
    public var name: String
    public var kind: Kind
    /// Shell: the command line (run with `/bin/zsh -c`). Shortcut: the name of the macOS Shortcut.
    public var command: String

    public init(id: String, name: String, kind: Kind, command: String) {
        self.id = id
        self.name = name
        self.kind = kind
        self.command = command
    }

    public static let maxCommandLength = 2000

    /// `id` for a new command: slug of the name, unique among `existing`.
    public static func makeId(name: String, existing: [CustomCommand]) -> String {
        let base = Topics.slug(name)
        var candidate = base
        var counter = 2
        while existing.contains(where: { $0.id == candidate }) {
            candidate = "\(base)_\(counter)"
            counter += 1
        }
        return candidate
    }

    public var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && name.count <= 40
            && !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && command.count <= Self.maxCommandLength
            && id.range(of: "^[a-z0-9_]{1,60}$", options: .regularExpression) != nil
    }
}

public struct CommandResult: Equatable, Sendable {
    public enum Status: String, Sendable { case ok, error, timeout, busy }
    public var status: Status
    public init(_ status: Status) { self.status = status }
}

public protocol CommandRunning: AnyObject {
    func run(_ command: CustomCommand) async -> CommandResult
}

public protocol MacControlling: AnyObject {
    @discardableResult func sleepSystem() -> Bool
    @discardableResult func displayOff() -> Bool
    @discardableResult func lockScreen() -> Bool
}

public struct SensorSnapshot: Equatable, Sendable {
    public var cameraInUse: Bool
    public var microphoneInUse: Bool
    public var screenLocked: Bool
    public var idleSeconds: Int
    public var activeApp: String?

    public init(cameraInUse: Bool = false, microphoneInUse: Bool = false, screenLocked: Bool = false, idleSeconds: Int = 0, activeApp: String? = nil) {
        self.cameraInUse = cameraInUse
        self.microphoneInUse = microphoneInUse
        self.screenLocked = screenLocked
        self.idleSeconds = idleSeconds
        self.activeApp = activeApp
    }
}

public protocol SensorReading: AnyObject {
    func read(includeActiveApp: Bool) -> SensorSnapshot
}
