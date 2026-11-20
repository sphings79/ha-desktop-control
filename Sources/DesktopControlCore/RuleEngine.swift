import Foundation

/// Decides what to do when contact sources open and close.
///
/// - First action per episode only: media is paused once, windows are handled once.
/// - Restore happens when the last source closes (after `resumeDelaySeconds`),
///   and only for what this engine did itself (the journal).
/// - All state changes run through one serial queue, so overlapping events cannot interleave.
@MainActor
public final class RuleEngine {
    public enum Status: String, Sendable {
        case idle
        case pausedByContact = "paused_by_contact"
    }

    public struct Snapshot: Equatable, Sendable {
        public var status: Status
        public var enabled: Bool
        public var openSources: [String]

        public init(status: Status, enabled: Bool, openSources: [String]) {
            self.status = status
            self.enabled = enabled
            self.openSources = openSources
        }
    }

    private struct Journal {
        var mediaDone = false
        var media: [PausedMedia] = []
        var minimizedDone = false
        var minimizedWindows: [PausedMedia] = []
        var windowsDone = false
        var windows: [WindowJournalEntry] = []
    }

    public var config: AppConfig
    public var onChange: ((Snapshot) -> Void)?

    public private(set) var status: Status = .idle
    public private(set) var enabled = true
    public private(set) var openSources: Set<String> = []

    private var journal = Journal()
    private let media: MediaControlling
    private let windowControl: WindowControlling
    private let sleep: (TimeInterval) async throws -> Void

    private var restoreTask: Task<Void, Never>?
    private var restoreGeneration = 0
    private var lastQueued: Task<Void, Never> = Task {}
    private var lastSnapshot: Snapshot?

    public init(
        config: AppConfig,
        media: MediaControlling,
        windows: WindowControlling,
        sleep: @escaping (TimeInterval) async throws -> Void = { seconds in
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        }
    ) {
        self.config = config
        self.media = media
        self.windowControl = windows
        self.sleep = sleep
    }

    public var snapshot: Snapshot {
        Snapshot(status: status, enabled: enabled, openSources: openSources.sorted())
    }

    // MARK: - Public API

    public func setContact(source: String, open: Bool) async {
        await enqueue { await self.handleContact(source: source, open: open) }
    }

    public func setEnabled(_ value: Bool) async {
        await enqueue {
            guard value != self.enabled else { return }
            self.enabled = value
            if !value, self.status == .pausedByContact {
                self.cancelRestore()
                await self.restoreAll()
            }
            self.publish()
        }
    }

    /// Manual "pause media" command from HA. Ignores open sources; ends with a manual restore
    /// or when all contacts close later.
    public func manualPause() async {
        await enqueue {
            guard self.enabled, !self.journal.mediaDone else { return }
            self.cancelRestore()
            self.journal.media = await self.media.pausePlaying()
            self.journal.mediaDone = true
            self.status = .pausedByContact
            self.publish()
        }
    }

    public func manualRestore() async {
        await enqueue {
            self.cancelRestore()
            await self.restoreAll()
            self.publish()
        }
    }

    // MARK: - Internals

    private func enqueue(_ operation: @escaping @MainActor () async -> Void) async {
        let previous = lastQueued
        let task = Task { @MainActor in
            await previous.value
            await operation()
        }
        lastQueued = task
        await task.value
    }

    private func handleContact(source: String, open: Bool) async {
        if open {
            guard openSources.insert(source).inserted else { return } // repeated retained message
            cancelRestore()
            await applyActions(for: source)
        } else {
            guard openSources.remove(source) != nil else { return }
            if openSources.isEmpty, status == .pausedByContact {
                await scheduleRestore()
            }
        }
        publish()
    }

    private func applyActions(for source: String) async {
        guard enabled else { return }
        for action in config.actions(forSource: source).sorted(by: { $0.rank < $1.rank }) {
            switch action {
            case .pauseMedia:
                guard !journal.mediaDone else { continue }
                journal.media = await media.pausePlaying()
                journal.mediaDone = true
            case .minimizePausedWindows:
                guard !journal.minimizedDone else { continue }
                journal.minimizedWindows = await media.minimizeWindows(of: journal.media)
                journal.minimizedDone = true
            case .windows:
                guard !journal.windowsDone else { continue }
                for rule in config.apps {
                    if let entry = await windowControl.apply(rule) {
                        journal.windows.append(entry)
                    }
                }
                journal.windowsDone = true
            }
            status = .pausedByContact
        }
    }

    private func scheduleRestore() async {
        let delay = config.resumeDelaySeconds
        if delay <= 0 {
            await restoreAll()
            return
        }
        restoreGeneration += 1
        let generation = restoreGeneration
        restoreTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do { try await self.sleep(delay) } catch { return }
            if Task.isCancelled { return }
            await self.enqueue {
                guard generation == self.restoreGeneration, self.openSources.isEmpty else { return }
                await self.restoreAll()
                self.publish()
            }
        }
    }

    private func cancelRestore() {
        restoreGeneration += 1
        restoreTask?.cancel()
        restoreTask = nil
    }

    private func restoreAll() async {
        let done = journal
        journal = Journal()
        status = .idle
        for entry in done.windows where entry.rule.restore {
            await windowControl.restore(entry)
        }
        if done.minimizedDone {
            await media.restoreWindows(done.minimizedWindows)
        }
        if done.mediaDone {
            await media.resume(done.media)
        }
    }

    private func publish() {
        let current = snapshot
        guard current != lastSnapshot else { return }
        lastSnapshot = current
        onChange?(current)
    }
}
