import AppKit
import DesktopControlCore

/// `HADesktopControl --selftest-media`: pauses playing browser media, waits 5 s, resumes, exits.
/// Triggers the Automation permission prompt for this app's own identity.
enum SelfTest {
    static func runMediaAndExit() -> Never {
        let controller = BrowserMediaController(browsers: { BrowserKind.allCases })
        var errors: [String] = []
        controller.onError = { errors.append($0) }
        let done = DispatchSemaphore(value: 0)
        Task.detached {
            let paused = await controller.pausePlaying()
            print("paused: \(paused)")
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            await controller.resume(paused)
            print("resumed")
            let playing = await controller.nowPlaying()
            print("now playing: \(playing)")
            errors.forEach { print("error: \($0)") }
            done.signal()
        }
        done.wait()
        exit(0)
    }
}
