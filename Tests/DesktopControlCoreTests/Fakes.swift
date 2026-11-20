import Foundation
@testable import DesktopControlCore

final class FakeMedia: MediaControlling {
    var playing: [PausedMedia] = [PausedMedia(browser: .brave, windowId: 1, tabId: 2)]
    var pauseCalls = 0
    var resumed: [[PausedMedia]] = []

    func pausePlaying() async -> [PausedMedia] {
        pauseCalls += 1
        return playing
    }

    func resume(_ items: [PausedMedia]) async {
        resumed.append(items)
    }

    var minimizeCalls: [[PausedMedia]] = []
    var restoredWindows: [[PausedMedia]] = []

    func minimizeWindows(of items: [PausedMedia]) async -> [PausedMedia] {
        minimizeCalls.append(items)
        return items.map { PausedMedia(browser: $0.browser, windowId: $0.windowId, tabId: 0) }
    }

    func restoreWindows(_ items: [PausedMedia]) async {
        restoredWindows.append(items)
    }
}

final class FakeWindows: WindowControlling {
    var running: Set<String> = []
    var applied: [String] = []
    var restored: [String] = []

    func apply(_ rule: AppRule) async -> WindowJournalEntry? {
        guard running.contains(rule.bundleId) else { return nil }
        applied.append(rule.bundleId)
        return WindowJournalEntry(rule: rule)
    }

    func restore(_ entry: WindowJournalEntry) async {
        restored.append(entry.rule.bundleId)
    }
}

/// A sleep replacement the test releases by hand. Throws on cancellation like `Task.sleep`.
final class SleepGate: @unchecked Sendable {
    private let lock = NSLock()
    private var released = 0
    private(set) var requested: [TimeInterval] = []

    func sleep(_ seconds: TimeInterval) async throws {
        lock.lock(); requested.append(seconds); lock.unlock()
        while true {
            try Task.checkCancellation()
            lock.lock()
            if released > 0 { released -= 1; lock.unlock(); return }
            lock.unlock()
            try await Task.sleep(nanoseconds: 2_000_000)
        }
    }

    func release() {
        lock.lock(); released += 1; lock.unlock()
    }
}

/// The bridge publishes from background tasks while the test reads on the main thread,
/// so every access goes through a lock (an unprotected array crashed the CI runner).
final class FakeTransport: MQTTTransport, @unchecked Sendable {
    var onMessage: ((MQTTMessage) -> Void)?
    var onConnectionChange: ((Bool) -> Void)?

    private let lock = NSLock()
    private var _published: [MQTTMessage] = []
    private var _subscribed: [String] = []
    private var _connectedClientId: String?
    private var _will: MQTTMessage?

    var published: [MQTTMessage] { lock.withLock { _published } }
    var subscribed: [String] { lock.withLock { _subscribed } }
    var connectedClientId: String? { lock.withLock { _connectedClientId } }
    var will: MQTTMessage? { lock.withLock { _will } }

    func connect(broker: BrokerConfig, password: String?, clientId: String, will: MQTTMessage) async throws {
        lock.withLock {
            _connectedClientId = clientId
            _will = will
        }
        onConnectionChange?(true)
    }

    func subscribe(_ topics: [String]) async throws { lock.withLock { _subscribed += topics } }
    func publish(_ message: MQTTMessage) async throws { lock.withLock { _published.append(message) } }
    func disconnect() async { onConnectionChange?(false) }

    func lastPayload(_ topic: String) -> String? {
        published.last(where: { $0.topic == topic })?.payload
    }
}

@MainActor
func waitUntil(timeout: TimeInterval = 2, _ condition: @MainActor () -> Bool) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if condition() { return true }
        try? await Task.sleep(nanoseconds: 5_000_000)
    }
    return condition()
}
