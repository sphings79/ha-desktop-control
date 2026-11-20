import Foundation

/// One browser tab whose media was paused by the app.
public struct PausedMedia: Codable, Equatable, Sendable {
    public var browser: BrowserKind
    public var windowId: Int
    public var tabId: Int

    public init(browser: BrowserKind, windowId: Int, tabId: Int) {
        self.browser = browser
        self.windowId = windowId
        self.tabId = tabId
    }
}

/// What the app did to one application, so it can be undone.
public struct WindowJournalEntry: Codable, Equatable, Sendable {
    public var rule: AppRule
    /// Titles of windows that were minimized (minimize action only).
    public var minimizedWindowTitles: [String]

    public init(rule: AppRule, minimizedWindowTitles: [String] = []) {
        self.rule = rule
        self.minimizedWindowTitles = minimizedWindowTitles
    }
}

public protocol MediaControlling: AnyObject {
    /// Pauses every playing media element and returns the affected tabs.
    func pausePlaying() async -> [PausedMedia]
    /// Resumes media in the given tabs, but only elements this app paused.
    func resume(_ items: [PausedMedia]) async
    /// Minimizes the browser windows that contain the given tabs (leaving full screen first).
    /// Returns the windows that were minimized, as items with `tabId` 0.
    func minimizeWindows(of items: [PausedMedia]) async -> [PausedMedia]
    /// Un-minimizes windows returned by `minimizeWindows`.
    func restoreWindows(_ items: [PausedMedia]) async
}

public protocol WindowControlling: AnyObject {
    /// Applies the rule. Returns nil if the app is not running or nothing was done.
    func apply(_ rule: AppRule) async -> WindowJournalEntry?
    func restore(_ entry: WindowJournalEntry) async
}

public struct MQTTMessage: Equatable, Sendable {
    public var topic: String
    public var payload: String
    public var retain: Bool

    public init(topic: String, payload: String, retain: Bool = false) {
        self.topic = topic
        self.payload = payload
        self.retain = retain
    }
}

public protocol MQTTTransport: AnyObject {
    var onMessage: ((MQTTMessage) -> Void)? { get set }
    /// Called with `true` after a successful (re)connect and `false` when the connection drops.
    var onConnectionChange: ((Bool) -> Void)? { get set }

    func connect(broker: BrokerConfig, password: String?, clientId: String, will: MQTTMessage) async throws
    func subscribe(_ topics: [String]) async throws
    func publish(_ message: MQTTMessage) async throws
    func disconnect() async
}
