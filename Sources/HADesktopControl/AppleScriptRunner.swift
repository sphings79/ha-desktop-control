import Foundation

/// Runs AppleScript source on one serial queue (NSAppleScript is not thread safe).
final class AppleScriptRunner: @unchecked Sendable {
    struct ScriptError: Error, CustomStringConvertible {
        let message: String
        let number: Int
        var description: String { "AppleScript error \(number): \(message)" }
    }

    private let queue = DispatchQueue(label: "ha-desktop-control.applescript")

    func run(_ source: String) async -> Result<String, ScriptError> {
        await withCheckedContinuation { continuation in
            queue.async {
                guard let script = NSAppleScript(source: source) else {
                    continuation.resume(returning: .failure(ScriptError(message: "compile failed", number: -1)))
                    return
                }
                var errorInfo: NSDictionary?
                let result = script.executeAndReturnError(&errorInfo)
                if let errorInfo {
                    let message = errorInfo[NSAppleScript.errorMessage] as? String ?? "unknown"
                    let number = errorInfo[NSAppleScript.errorNumber] as? Int ?? 0
                    continuation.resume(returning: .failure(ScriptError(message: message, number: number)))
                } else {
                    continuation.resume(returning: .success(result.stringValue ?? ""))
                }
            }
        }
    }
}
