import AppKit
import SwiftUI

@main
enum Entry {
    static func main() {
        // `--snapshots <dir>` renders the settings pages with sample data into PNG files and exits.
        // It runs before any AppModel exists, so it never touches the real config or the broker.
        let args = CommandLine.arguments
        if let index = args.firstIndex(of: "--snapshots"), index + 1 < args.count {
            MainActor.assumeIsolated { SnapshotRunner.run(into: args[index + 1]) }
        } else {
            HADesktopControlApp.main()
        }
    }
}
