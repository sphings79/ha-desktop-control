import AppKit
import DesktopControlCore

/// Pauses and resumes `<video>`/`<audio>` elements in Chromium-based browsers via AppleScript.
/// Requires "Allow JavaScript from Apple Events" in each browser's Developer menu.
final class BrowserMediaController: MediaControlling {
    private let runner = AppleScriptRunner()
    private let browsers: () -> [BrowserKind]
    var onError: ((String) -> Void)?

    // Elements paused by this app carry data-hdc="1" so resume never starts anything else.
    private static let jsPause =
        "(function(){var n=0;document.querySelectorAll('video,audio').forEach(function(x){if(!x.paused&&!x.ended){x.pause();x.setAttribute('data-hdc','1');n++}});return String(n)})()"
    private static let jsResume =
        "(function(){var n=0;document.querySelectorAll('video,audio').forEach(function(x){if(x.getAttribute('data-hdc')==='1'){if(x.paused&&!x.ended){x.play();n++}x.removeAttribute('data-hdc')}});return String(n)})()"
    private static let jsPlaying =
        "(function(){return String([].slice.call(document.querySelectorAll('video,audio')).filter(function(x){return !x.paused&&!x.ended}).length)})()"

    init(browsers: @escaping () -> [BrowserKind]) {
        self.browsers = browsers
    }

    private func runningBrowsers() -> [BrowserKind] {
        browsers().filter {
            !NSRunningApplication.runningApplications(withBundleIdentifier: $0.bundleId).isEmpty
        }
    }

    func pausePlaying() async -> [PausedMedia] {
        var paused: [PausedMedia] = []
        for browser in runningBrowsers() {
            let script = """
            tell application id "\(browser.bundleId)"
                set out to ""
                repeat with w in windows
                    set wid to id of w
                    repeat with t in tabs of w
                        try
                            set r to execute t javascript "\(Self.jsPause)"
                            if r is not "0" then set out to out & wid & ":" & (id of t) & ";"
                        end try
                    end repeat
                end repeat
                return out
            end tell
            """
            switch await runner.run(script) {
            case .success(let text):
                for pair in text.split(separator: ";") {
                    let ids = pair.split(separator: ":").compactMap { Int($0) }
                    if ids.count == 2 {
                        paused.append(PausedMedia(browser: browser, windowId: ids[0], tabId: ids[1]))
                    }
                }
            case .failure(let error):
                onError?("\(browser.displayName): \(error)")
            }
        }
        return paused
    }

    func resume(_ items: [PausedMedia]) async {
        for item in items {
            let script = """
            tell application id "\(item.browser.bundleId)"
                try
                    set t to tab id \(item.tabId) of window id \(item.windowId)
                    return execute t javascript "\(Self.jsResume)"
                end try
            end tell
            """
            if case .failure(let error) = await runner.run(script) {
                onError?("\(item.browser.displayName): \(error)")
            }
        }
    }

    // MARK: - Window minimizing

    /// Minimizes each browser window that holds a paused tab. A full-screen window cannot be
    /// minimized, so full screen is left first (found by matching the window's bounds via AX).
    func minimizeWindows(of items: [PausedMedia]) async -> [PausedMedia] {
        var seen = Set<String>()
        var minimized: [PausedMedia] = []
        for item in items {
            let key = "\(item.browser.rawValue):\(item.windowId)"
            guard seen.insert(key).inserted else { continue }

            if let bounds = await windowBounds(item) {
                await leaveFullScreen(browser: item.browser, bounds: bounds)
            }
            let script = """
            tell application id "\(item.browser.bundleId)"
                try
                    set w to window id \(item.windowId)
                    if minimized of w is false then
                        set minimized of w to true
                        return "ok"
                    end if
                end try
                return ""
            end tell
            """
            switch await runner.run(script) {
            case .success(let result) where result == "ok":
                minimized.append(PausedMedia(browser: item.browser, windowId: item.windowId, tabId: 0))
            case .success:
                break
            case .failure(let error):
                onError?("\(item.browser.displayName): \(error)")
            }
        }
        return minimized
    }

    func restoreWindows(_ items: [PausedMedia]) async {
        for item in items {
            let script = """
            tell application id "\(item.browser.bundleId)"
                try
                    set minimized of window id \(item.windowId) to false
                end try
            end tell
            """
            if case .failure(let error) = await runner.run(script) {
                onError?("\(item.browser.displayName): \(error)")
            }
        }
    }

    private struct Bounds { var left, top, right, bottom: Double }

    private func windowBounds(_ item: PausedMedia) async -> Bounds? {
        let script = """
        tell application id "\(item.browser.bundleId)"
            try
                set b to bounds of window id \(item.windowId)
                return (item 1 of b as text) & "," & (item 2 of b as text) & "," & (item 3 of b as text) & "," & (item 4 of b as text)
            end try
            return ""
        end tell
        """
        guard case .success(let text) = await runner.run(script) else { return nil }
        let parts = text.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard parts.count == 4 else { return nil }
        return Bounds(left: parts[0], top: parts[1], right: parts[2], bottom: parts[3])
    }

    /// Sets AXFullScreen=false on the browser window matching `bounds` and waits for the
    /// transition. Falls back to the only full-screen window of the browser if no bounds match.
    private func leaveFullScreen(browser: BrowserKind, bounds: Bounds) async {
        guard AXWindowController.isTrusted,
              let app = NSRunningApplication.runningApplications(withBundleIdentifier: browser.bundleId).first
        else { return }

        let fullScreen = AXWindowController.windows(of: app)
            .filter { AXWindowController.bool($0, "AXFullScreen") == true }
        guard !fullScreen.isEmpty else { return }
        let match = fullScreen.first { Self.frame(of: $0).map { Self.matches($0, bounds) } ?? false }
            ?? (fullScreen.count == 1 ? fullScreen[0] : nil)
        guard let target = match else { return }

        AXUIElementSetAttributeValue(target, "AXFullScreen" as CFString, kCFBooleanFalse)
        for _ in 0..<30 { // up to 6 s
            let stillFull = AXWindowController.windows(of: app)
                .contains { AXWindowController.bool($0, "AXFullScreen") == true }
            if !stillFull { break }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        try? await Task.sleep(nanoseconds: 700_000_000) // let the transition animation finish
    }

    private static func frame(of window: AXUIElement) -> CGRect? {
        var position: CFTypeRef?
        var size: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &position) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &size) == .success,
              let position, let size else { return nil }
        var point = CGPoint.zero
        var dimension = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &point),
              AXValueGetValue(size as! AXValue, .cgSize, &dimension) else { return nil }
        return CGRect(origin: point, size: dimension)
    }

    private static func matches(_ frame: CGRect, _ bounds: Bounds) -> Bool {
        abs(frame.minX - bounds.left) < 4 && abs(frame.minY - bounds.top) < 4
            && abs(frame.maxX - bounds.right) < 4 && abs(frame.maxY - bounds.bottom) < 4
    }

    /// "Brave: <tab title>" for the first tab with playing media, or "" if nothing plays.
    func nowPlaying() async -> String {
        for browser in runningBrowsers() {
            let script = """
            tell application id "\(browser.bundleId)"
                repeat with w in windows
                    repeat with t in tabs of w
                        try
                            set r to execute t javascript "\(Self.jsPlaying)"
                            if r is not "0" then return title of t
                        end try
                    end repeat
                end repeat
                return ""
            end tell
            """
            if case .success(let title) = await runner.run(script), !title.isEmpty {
                return String("\(browser.displayName): \(title)".prefix(250))
            }
        }
        return ""
    }
}
