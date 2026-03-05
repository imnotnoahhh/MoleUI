import Foundation

/// Error translator: Translates CLI errors into user-friendly messages
enum ErrorTranslator {
    struct UserFriendlyError {
        let title: String
        let message: String
        let suggestion: String?
        let nextSteps: [String]
        let technicalDetails: String?
        let severity: Severity

        enum Severity {
            case info
            case warning
            case error
            case critical
        }
    }

    /// Translate CLI error
    static func translate(
        error: Error,
        context: String? = nil
    ) -> UserFriendlyError {
        // 1. Handle known error types
        if let cliError = error as? CLIExecutor.ExecutionError {
            return translateCLIError(cliError, context: context)
        }

        // 2. Handle system errors
        if let nsError = error as NSError? {
            return translateSystemError(nsError, context: context)
        }

        // 3. Default error
        return UserFriendlyError(
            title: "Operation Failed",
            message: "An unknown error occurred",
            suggestion: "Please try again. If the problem persists, contact support",
            nextSteps: ["Retry operation", "Check system logs", "Contact support"],
            technicalDetails: error.localizedDescription,
            severity: .error
        )
    }

    // MARK: - CLI Error Translation

    private static func translateCLIError(
        _ error: CLIExecutor.ExecutionError,
        context: String?
    ) -> UserFriendlyError {
        switch error {
        case .timeout:
            UserFriendlyError(
                title: "Operation Timeout",
                message: "Operation took too long and was automatically cancelled",
                suggestion: "This may be due to too many files to clean or high system load",
                nextSteps: [
                    "Try cleaning a smaller scope",
                    "Close other resource-intensive apps",
                    "Try again later",
                ],
                technicalDetails: "Execution timeout",
                severity: .warning
            )

        case .cancelled:
            UserFriendlyError(
                title: "Operation Cancelled",
                message: "You have cancelled the current operation",
                suggestion: nil,
                nextSteps: ["Restart operation"],
                technicalDetails: "User cancelled",
                severity: .info
            )

        case .commandNotFound(let cmd):
            UserFriendlyError(
                title: "Command Not Found",
                message: "Cannot find \(cmd) command",
                suggestion: "Mole CLI may not be properly installed",
                nextSteps: [
                    "Reinstall the app",
                    "Check app permissions",
                    "Contact support",
                ],
                technicalDetails: "Command not found: \(cmd)",
                severity: .critical
            )

        case .nonZeroExit(let code, let stderr):
            translateExitCode(code, stderr: stderr, context: context)

        case .invalidOutput(let msg):
            UserFriendlyError(
                title: "Output Parsing Failed",
                message: "Cannot understand command output",
                suggestion: "This may be due to Mole CLI version incompatibility",
                nextSteps: [
                    "Update app to latest version",
                    "Retry operation",
                    "Contact support",
                ],
                technicalDetails: msg,
                severity: .error
            )
        }
    }

    // MARK: - Exit Code Translation

    private static func translateExitCode(
        _ code: Int32,
        stderr: String,
        context: String?
    ) -> UserFriendlyError {
        // Analyze stderr content
        let stderrLower = stderr.lowercased()

        // Permission errors
        if stderrLower.contains("permission denied") ||
            stderrLower.contains("operation not permitted")
        {
            return UserFriendlyError(
                title: "Permission Denied",
                message: "Insufficient permissions to perform this operation",
                suggestion: "Some system files require administrator privileges to clean",
                nextSteps: [
                    "Click 'Use Administrator Privileges' button",
                    "Or skip files that require permissions",
                ],
                technicalDetails: "Exit code: \(code)\n\(stderr)",
                severity: .warning
            )
        }

        // Default error
        return UserFriendlyError(
            title: "Operation Failed",
            message: context ?? "An error occurred while executing command",
            suggestion: "Please check details for more information",
            nextSteps: [
                "Retry operation",
                "View technical details",
                "Contact support",
            ],
            technicalDetails: "Exit code: \(code)\n\(stderr)",
            severity: .error
        )
    }

    // MARK: - System Error Translation

    private static func translateSystemError(
        _ error: NSError,
        context: String?
    ) -> UserFriendlyError {
        UserFriendlyError(
            title: "System Error",
            message: error.localizedDescription,
            suggestion: "This is a system-level error",
            nextSteps: ["Retry operation", "Restart app", "Contact support"],
            technicalDetails: "\(error.domain): \(error.code)",
            severity: .error
        )
    }
}
