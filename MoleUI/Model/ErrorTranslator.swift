import Foundation

/// 错误翻译器：将 CLI 错误翻译成用户友好的提示
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

    /// 翻译 CLI 错误
    static func translate(
        error: Error,
        context: String? = nil
    ) -> UserFriendlyError {
        // 1. 处理已知的错误类型
        if let cliError = error as? CLIExecutor.ExecutionError {
            return translateCLIError(cliError, context: context)
        }

        // 2. 处理系统错误
        if let nsError = error as NSError? {
            return translateSystemError(nsError, context: context)
        }

        // 3. 默认错误
        return UserFriendlyError(
            title: "操作失败",
            message: "遇到了一个未知错误",
            suggestion: "请重试，如果问题持续存在，请联系支持",
            nextSteps: ["重试操作", "检查系统日志", "联系支持"],
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
            return UserFriendlyError(
                title: "操作超时",
                message: "操作执行时间过长，已自动取消",
                suggestion: "这可能是因为需要清理的文件太多，或者系统负载较高",
                nextSteps: [
                    "尝试清理更小的范围",
                    "关闭其他占用资源的应用",
                    "稍后再试",
                ],
                technicalDetails: "Execution timeout",
                severity: .warning
            )

        case .cancelled:
            return UserFriendlyError(
                title: "操作已取消",
                message: "您已取消了当前操作",
                suggestion: nil,
                nextSteps: ["重新开始操作"],
                technicalDetails: "User cancelled",
                severity: .info
            )

        case let .commandNotFound(cmd):
            return UserFriendlyError(
                title: "找不到命令",
                message: "无法找到 \(cmd) 命令",
                suggestion: "Mole CLI 可能没有正确安装",
                nextSteps: [
                    "重新安装应用",
                    "检查应用权限",
                    "联系支持",
                ],
                technicalDetails: "Command not found: \(cmd)",
                severity: .critical
            )

        case let .nonZeroExit(code, stderr):
            return translateExitCode(code, stderr: stderr, context: context)

        case let .invalidOutput(msg):
            return UserFriendlyError(
                title: "输出解析失败",
                message: "无法理解命令的输出结果",
                suggestion: "这可能是 Mole CLI 版本不兼容",
                nextSteps: [
                    "更新应用到最新版本",
                    "重试操作",
                    "联系支持",
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
        // 分析 stderr 内容
        let stderrLower = stderr.lowercased()

        // 权限错误
        if stderrLower.contains("permission denied") ||
            stderrLower.contains("operation not permitted")
        {
            return UserFriendlyError(
                title: "权限不足",
                message: "没有足够的权限执行此操作",
                suggestion: "某些系统文件需要管理员权限才能清理",
                nextSteps: [
                    "点击「使用管理员权限」按钮",
                    "或者跳过需要权限的文件",
                ],
                technicalDetails: "Exit code: \(code)\n\(stderr)",
                severity: .warning
            )
        }

        // 磁盘空间不足
        if stderrLower.contains("no space left") ||
            stderrLower.contains("disk full")
        {
            return UserFriendlyError(
                title: "磁盘空间不足",
                message: "磁盘空间已满，无法完成操作",
                suggestion: "请先清理一些文件以释放空间",
                nextSteps: [
                    "清理垃圾桶",
                    "删除大文件",
                    "移动文件到外部存储",
                ],
                technicalDetails: "Exit code: \(code)\n\(stderr)",
                severity: .critical
            )
        }

        // 文件不存在
        if stderrLower.contains("no such file") ||
            stderrLower.contains("not found")
        {
            return UserFriendlyError(
                title: "文件不存在",
                message: "要操作的文件或目录不存在",
                suggestion: "文件可能已被删除或移动",
                nextSteps: [
                    "刷新列表",
                    "重新扫描",
                    "跳过此文件",
                ],
                technicalDetails: "Exit code: \(code)\n\(stderr)",
                severity: .warning
            )
        }

        // 文件正在使用
        if stderrLower.contains("resource busy") ||
            stderrLower.contains("file is in use")
        {
            return UserFriendlyError(
                title: "文件正在使用",
                message: "某些文件正在被其他程序使用",
                suggestion: "请关闭相关应用后重试",
                nextSteps: [
                    "关闭相关应用",
                    "重启电脑",
                    "跳过正在使用的文件",
                ],
                technicalDetails: "Exit code: \(code)\n\(stderr)",
                severity: .warning
            )
        }

        // SIP 保护
        if stderrLower.contains("system integrity protection") ||
            stderrLower.contains("sip")
        {
            return UserFriendlyError(
                title: "系统保护",
                message: "此文件受 macOS 系统完整性保护 (SIP)",
                suggestion: "这是 macOS 的安全机制，不建议清理这些文件",
                nextSteps: [
                    "跳过受保护的文件",
                    "了解更多关于 SIP 的信息",
                ],
                technicalDetails: "Exit code: \(code)\n\(stderr)",
                severity: .info
            )
        }

        // 网络错误
        if stderrLower.contains("network") ||
            stderrLower.contains("connection")
        {
            return UserFriendlyError(
                title: "网络错误",
                message: "网络连接出现问题",
                suggestion: "请检查您的网络连接",
                nextSteps: [
                    "检查网络连接",
                    "重试操作",
                    "使用离线模式",
                ],
                technicalDetails: "Exit code: \(code)\n\(stderr)",
                severity: .warning
            )
        }

        // 默认错误
        return UserFriendlyError(
            title: "操作失败",
            message: context ?? "执行命令时出现错误",
            suggestion: "请查看详细信息了解具体原因",
            nextSteps: [
                "重试操作",
                "查看技术详情",
                "联系支持",
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
        switch error.domain {
        case NSCocoaErrorDomain:
            return translateCocoaError(error, context: context)

        case NSPOSIXErrorDomain:
            return translatePOSIXError(error, context: context)

        default:
            return UserFriendlyError(
                title: "系统错误",
                message: error.localizedDescription,
                suggestion: "这是一个系统级错误",
                nextSteps: ["重试操作", "重启应用", "联系支持"],
                technicalDetails: "\(error.domain): \(error.code)",
                severity: .error
            )
        }
    }

    private static func translateCocoaError(
        _ error: NSError,
        context _: String?
    ) -> UserFriendlyError {
        switch error.code {
        case NSFileReadNoPermissionError, NSFileWriteNoPermissionError:
            return UserFriendlyError(
                title: "权限不足",
                message: "没有权限访问此文件",
                suggestion: "请检查文件权限设置",
                nextSteps: ["使用管理员权限", "修改文件权限", "跳过此文件"],
                technicalDetails: error.localizedDescription,
                severity: .warning
            )

        case NSFileNoSuchFileError:
            return UserFriendlyError(
                title: "文件不存在",
                message: "找不到指定的文件",
                suggestion: "文件可能已被删除",
                nextSteps: ["刷新列表", "重新扫描"],
                technicalDetails: error.localizedDescription,
                severity: .warning
            )

        default:
            return UserFriendlyError(
                title: "文件操作失败",
                message: error.localizedDescription,
                suggestion: nil,
                nextSteps: ["重试操作"],
                technicalDetails: "Cocoa error: \(error.code)",
                severity: .error
            )
        }
    }

    private static func translatePOSIXError(
        _ error: NSError,
        context _: String?
    ) -> UserFriendlyError {
        let errno = Int32(error.code)

        switch errno {
        case EACCES, EPERM:
            return UserFriendlyError(
                title: "权限被拒绝",
                message: "没有权限执行此操作",
                suggestion: "需要管理员权限",
                nextSteps: ["使用管理员权限", "修改权限"],
                technicalDetails: "POSIX error: \(errno)",
                severity: .warning
            )

        case ENOENT:
            return UserFriendlyError(
                title: "文件不存在",
                message: "找不到文件或目录",
                suggestion: "路径可能不正确",
                nextSteps: ["检查路径", "刷新列表"],
                technicalDetails: "POSIX error: \(errno)",
                severity: .warning
            )

        case ENOSPC:
            return UserFriendlyError(
                title: "磁盘空间不足",
                message: "设备上没有剩余空间",
                suggestion: "请释放一些磁盘空间",
                nextSteps: ["清理垃圾桶", "删除大文件"],
                technicalDetails: "POSIX error: \(errno)",
                severity: .critical
            )

        default:
            return UserFriendlyError(
                title: "系统错误",
                message: error.localizedDescription,
                suggestion: nil,
                nextSteps: ["重试操作"],
                technicalDetails: "POSIX error: \(errno)",
                severity: .error
            )
        }
    }
}

// MARK: - SwiftUI Integration

import SwiftUI

struct ErrorView: View {
    let error: ErrorTranslator.UserFriendlyError
    let onDismiss: () -> Void
    let onRetry: (() -> Void)?

    var body: some View {
        VStack(spacing: 20) {
            // 图标
            Image(systemName: iconName)
                .font(.system(size: 48))
                .foregroundColor(iconColor)

            // 标题
            Text(error.title)
                .font(.headline)

            // 消息
            Text(error.message)
                .font(.body)
                .multilineTextAlignment(.center)

            // 建议
            if let suggestion = error.suggestion {
                Text(suggestion)
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            // 下一步操作
            if !error.nextSteps.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("建议操作：")
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    ForEach(error.nextSteps, id: \.self) { step in
                        HStack {
                            Image(systemName: "checkmark.circle")
                                .foregroundColor(.blue)
                            Text(step)
                                .font(.callout)
                        }
                    }
                }
                .padding()
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(8)
            }

            // 技术详情（可展开）
            if let details = error.technicalDetails {
                DisclosureGroup("技术详情") {
                    Text(details)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .textSelection(.enabled)
                        .padding()
                }
            }

            // 按钮
            HStack(spacing: 12) {
                Button("关闭") {
                    onDismiss()
                }

                if let onRetry = onRetry {
                    Button("重试") {
                        onRetry()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding()
        .frame(width: 500)
    }

    private var iconName: String {
        switch error.severity {
        case .info: return "info.circle"
        case .warning: return "exclamationmark.triangle"
        case .error: return "xmark.circle"
        case .critical: return "exclamationmark.octagon"
        }
    }

    private var iconColor: Color {
        switch error.severity {
        case .info: return .blue
        case .warning: return .orange
        case .error: return .red
        case .critical: return .red
        }
    }
}
