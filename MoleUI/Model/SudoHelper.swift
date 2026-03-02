import Foundation

/// Executes commands with administrator privileges via macOS osascript.
enum SudoHelper {
    /// Run a command with admin privileges using osascript "do shell script ... with administrator privileges".
    static func runWithAdmin(_ command: String) async throws -> String {
        let escaped = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        let script = "do shell script \"\(escaped)\" with administrator privileges"
        return try await CLIExecutor.run(
            "osascript -e '\(script)'"
        )
    }
}
