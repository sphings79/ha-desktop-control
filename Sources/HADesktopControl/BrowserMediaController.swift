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
