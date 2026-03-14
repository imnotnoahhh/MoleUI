import AppKit
import Foundation

/// Coordinates a single sudo flow for the GUI using cached sudo access
/// when available and a native password prompt otherwise.
enum SudoHelper {
    @MainActor
    static func requestSudoAccess(
        reason: String = "Mole UI needs administrator access to continue."
    ) async -> Bool {
        if hasCachedSudoAccess() {
            return true
        }

        return await requestPasswordValidation(reason: reason)
    }

    @MainActor
    static func runWithAdmin(
        _ command: String,
        reason: String = "Mole UI needs administrator access to continue."
    ) async throws -> String {
        guard await requestSudoAccess(reason: reason) else {
            throw NSError(
                domain: "SudoHelper",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Administrator privileges required"]
            )
        }

        return try await CLIExecutor.run(command)
    }

    nonisolated static func hasCachedSudoAccess() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        process.arguments = ["-n", "true"]
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    @MainActor
    private static func requestPasswordValidation(reason: String) async -> Bool {
        for attempt in 0 ..< 2 {
            let promptReason = attempt == 0
                ? reason
                : "The password was not accepted. Please try again."

            guard let password = promptForPassword(reason: promptReason) else {
                return false
            }

            let validated = await validatePassword(password)
            if validated {
                return true
            }
        }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Administrator access not granted"
        alert.informativeText = "The current action needs a valid administrator password."
        alert.addButton(withTitle: "OK")
        alert.runModal()
        return false
    }

    @MainActor
    private static func promptForPassword(reason: String) -> String? {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Administrator Password"
        alert.informativeText = reason

        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.placeholderString = "Password"
        alert.accessoryView = field
        alert.addButton(withTitle: "Continue")
        alert.addButton(withTitle: "Cancel")

        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else {
            return nil
        }

        let password = field.stringValue
        return password.isEmpty ? nil : password
    }

    private nonisolated static func validatePassword(_ password: String) async -> Bool {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
                process.arguments = ["-S", "-p", "", "-v"]

                let stdinPipe = Pipe()
                process.standardInput = stdinPipe
                process.standardOutput = Pipe()
                process.standardError = Pipe()

                do {
                    try process.run()

                    if let data = (password + "\n").data(using: .utf8) {
                        stdinPipe.fileHandleForWriting.write(data)
                    }
                    stdinPipe.fileHandleForWriting.closeFile()

                    process.waitUntilExit()
                    continuation.resume(returning: process.terminationStatus == 0 && hasCachedSudoAccess())
                } catch {
                    continuation.resume(returning: false)
                }
            }
        }
    }
}
