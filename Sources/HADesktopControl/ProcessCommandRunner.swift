import DesktopControlCore
import Foundation

/// Runs a user-defined command with a time limit. Output is discarded; only the exit status counts.
final class ProcessCommandRunner: CommandRunning {
    static let timeout: TimeInterval = 30

    private final class Once: @unchecked Sendable {
        private let lock = NSLock()
        private var done = false
        var timedOut = false
        func first() -> Bool { lock.lock(); defer { lock.unlock() }; if done { return false }; done = true; return true }
        func markTimeout() { lock.lock(); timedOut = true; lock.unlock() }
        var wasTimeout: Bool { lock.lock(); defer { lock.unlock() }; return timedOut }
    }

    func run(_ command: CustomCommand) async -> CommandResult {
        let process = Process()
        switch command.kind {
        case .shell:
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-l", "-c", command.command]
        case .shortcut:
            process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
            process.arguments = ["run", command.command]
        }
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        let once = Once()
        return await withCheckedContinuation { continuation in
            process.terminationHandler = { finished in
                guard once.first() else { return }
                if once.wasTimeout {
                    continuation.resume(returning: CommandResult(.timeout))
                } else {
                    continuation.resume(returning: CommandResult(finished.terminationStatus == 0 ? .ok : .error))
                }
            }
            do {
                try process.run()
            } catch {
                if once.first() { continuation.resume(returning: CommandResult(.error)) }
                return
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + Self.timeout) {
                if process.isRunning {
                    once.markTimeout()
                    process.terminate()
                }
            }
        }
    }
}
