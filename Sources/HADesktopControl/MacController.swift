import AppKit
import DesktopControlCore
import Foundation

/// Sleep, display off and lock screen. Only reached for commands the user switched on.
final class MacController: MacControlling {
    @discardableResult
    func sleepSystem() -> Bool { pmset("sleepnow") }

    @discardableResult
    func displayOff() -> Bool { pmset("displaysleepnow") }

    /// Uses the lock call the macOS menu uses (private symbol, looked up at runtime); if it is
    /// missing, the display is switched off, which locks when "require password" is immediate.
    @discardableResult
    func lockScreen() -> Bool {
        if let lock = Self.lockSymbol {
            lock()
            return true
        }
        return displayOff()
    }

    static var lockSymbol: (@convention(c) () -> Int32)? {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/login.framework/login", RTLD_LAZY),
              let symbol = dlsym(handle, "SACLockScreenImmediate") else { return nil }
        return unsafeBitCast(symbol, to: (@convention(c) () -> Int32).self)
    }

    private func pmset(_ argument: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = [argument]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            return true
        } catch {
            return false
        }
    }
}
