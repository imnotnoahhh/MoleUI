import Foundation
import Security

/// Executes commands with administrator privileges via macOS Authorization Services.
enum SudoHelper {
    /// Request sudo access using native macOS authorization dialog.
    /// This will show a system password dialog and cache sudo credentials.
    @MainActor
    static func requestSudoAccess() async -> Bool {
        print("🔐 SudoHelper.requestSudoAccess() called")

        // Check if we already have sudo access
        let checkTask = Process()
        checkTask.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        checkTask.arguments = ["-n", "true"]
        checkTask.standardOutput = Pipe()
        checkTask.standardError = Pipe()

        do {
            try checkTask.run()
            checkTask.waitUntilExit()
            if checkTask.terminationStatus == 0 {
                print("✅ Already have sudo access")
                return true
            }
            print("⚠️ No existing sudo access, need to request")
        } catch {
            print("⚠️ Failed to check sudo access: \(error)")
        }

        // Use osascript to prompt for password with GUI dialog
        // This will cache sudo credentials for 5 minutes
        do {
            let script = """
            do shell script "sudo -v" with administrator privileges
            """
            let osascriptTask = Process()
            osascriptTask.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            osascriptTask.arguments = ["-e", script]
            osascriptTask.standardOutput = Pipe()
            osascriptTask.standardError = Pipe()

            try osascriptTask.run()
            osascriptTask.waitUntilExit()

            let success = osascriptTask.terminationStatus == 0
            print("🔐 osascript sudo -v exit code: \(osascriptTask.terminationStatus), success: \(success)")

            if !success {
                let stderrData = (osascriptTask.standardError as? Pipe)?.fileHandleForReading.readDataToEndOfFile()
                if let stderrData, let stderr = String(data: stderrData, encoding: .utf8) {
                    print("❌ osascript stderr: \(stderr)")
                }
            }

            return success
        } catch {
            print("❌ Failed to run osascript: \(error)")
            return false
        }
    }

    /// Run a command with admin privileges using osascript "do shell script ... with administrator privileges".
    static func runWithAdmin(_ command: String) async throws -> String {
        print("🔐 runWithAdmin called with command: \(command)")

        // Find where the mole executable ends (look for "/mole ")
        // The command format is: /path/to/mole subcommand args
        guard let moleRange = command.range(of: "/mole ") else {
            throw NSError(
                domain: "SudoHelper",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Invalid command format: expected '/mole ' in command"]
            )
        }

        // Split at the space after "mole"
        let executableEnd = moleRange.upperBound
        let executable = String(command[..<executableEnd].dropLast()) // Remove trailing space
        let arguments = String(command[executableEnd...])

        print("📝 Executable: \(executable)")
        print("📝 Arguments: \(arguments)")

        // Create a temporary script file with properly quoted executable
        let tempScript = NSTemporaryDirectory() + "mole_admin_\(UUID().uuidString).sh"
        print("📝 Creating temp script at: \(tempScript)")

        // Write command to temp file with shebang and quoted executable
        let scriptContent = "#!/bin/bash\n\"\(executable)\" \(arguments)"
        try scriptContent.write(toFile: tempScript, atomically: true, encoding: .utf8)
        defer {
            try? FileManager.default.removeItem(atPath: tempScript)
        }

        // Make it executable
        print("🔧 Making script executable")
        _ = try await CLIExecutor.run("chmod +x '\(tempScript)'")

        // Run via osascript
        let script = "do shell script \"'\(tempScript)'\" with administrator privileges"
        print("🚀 Running osascript: \(script)")
        let result = try await CLIExecutor.run("osascript -e '\(script)'")
        print("✅ Command completed successfully")
        return result
    }
}
