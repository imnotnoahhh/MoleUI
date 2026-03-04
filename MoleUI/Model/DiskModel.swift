import Foundation
import Observation

struct DirEntry: Identifiable, Sendable {
    let id: String // full path
    let name: String
    let path: URL
    let sizeBytes: UInt64
    let isDirectory: Bool
    let children: Int // number of immediate children (0 for files)

    init(name: String, path: URL, sizeBytes: UInt64, isDirectory: Bool, children: Int) {
        self.id = path.path
        self.name = name
        self.path = path
        self.sizeBytes = sizeBytes
        self.isDirectory = isDirectory
        self.children = children
    }
}

struct ScanProgress: Sendable {
    let currentPath: String
    let itemsScanned: Int
    let bytesScanned: UInt64
}

// MARK: - Model

import AppKit

@Observable @MainActor
final class DiskModel {
    var entries: [DirEntry] = []
    var currentPath: URL
    var pathStack: [URL] = []
    var isScanning = false
    var progress: ScanProgress?
    var totalSize: UInt64 = 0
    var errorMessage: String?

    private var scanTask: Task<Void, Never>?

    // MARK: - Cache

    private struct CachedScan {
        let entries: [DirEntry]
        let totalSize: UInt64
        var dirty: Bool = false
    }

    private var cache: [String: CachedScan] = [:]

    init() {
        self.currentPath = FileManager.default.homeDirectoryForCurrentUser
    }

    // MARK: - Navigation

    func scan(directory: URL) {
        scanTask?.cancel()
        isScanning = true
        errorMessage = nil
        progress = ScanProgress(currentPath: directory.path, itemsScanned: 0, bytesScanned: 0)

        scanTask = Task {
            do {
                let result = try await performScan(directory: directory)
                guard !Task.isCancelled else { return }
                self.entries = result.entries
                self.totalSize = result.totalSize
                self.currentPath = directory
                self.isScanning = false
                self.progress = nil
                // Write to cache
                cache[directory.path] = CachedScan(
                    entries: result.entries, totalSize: result.totalSize
                )
            } catch is CancellationError {
                // scan was cancelled
            } catch {
                guard !Task.isCancelled else { return }
                self.errorMessage = error.localizedDescription
                self.isScanning = false
                self.progress = nil
            }
        }
    }

    /// Restore from cache if available and clean; otherwise scan.
    private func loadOrScan(directory: URL) {
        if let cached = cache[directory.path], !cached.dirty {
            scanTask?.cancel()
            entries = cached.entries
            totalSize = cached.totalSize
            currentPath = directory
            isScanning = false
            progress = nil
        } else {
            scan(directory: directory)
        }
    }

    func navigateTo(directory: URL) {
        pathStack.append(currentPath)
        loadOrScan(directory: directory)
    }

    func navigateBack() {
        guard let previous = pathStack.popLast() else { return }
        loadOrScan(directory: previous)
    }

    func navigateToRoot() {
        pathStack.removeAll()
        loadOrScan(directory: FileManager.default.homeDirectoryForCurrentUser)
    }

    func navigateToBreadcrumb(index: Int) {
        guard index < pathStack.count else { return }
        let target = pathStack[index]
        pathStack = Array(pathStack.prefix(index))
        loadOrScan(directory: target)
    }

    // MARK: - Actions

    func deleteEntry(_ entry: DirEntry) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            NSWorkspace.shared.recycle([entry.path]) { _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
        // Mark current path and all ancestors dirty
        invalidateCache(for: currentPath)
        scan(directory: currentPath)
    }

    private func invalidateCache(for url: URL) {
        var path = url
        let home = FileManager.default.homeDirectoryForCurrentUser
        while path.path.count >= home.path.count {
            cache[path.path]?.dirty = true
            path = path.deletingLastPathComponent()
        }
    }

    func revealInFinder(_ entry: DirEntry) {
        NSWorkspace.shared.activateFileViewerSelecting([entry.path])
    }

    // MARK: - Private Scan Implementation

    private struct ScanResult {
        let entries: [DirEntry]
        let totalSize: UInt64
    }

    /// JSON response from mole analyze --json
    private struct AnalyzeJSONResponse: Codable {
        let path: String
        let entries: [AnalyzeEntry]
        let totalSize: Int64
        let totalFiles: Int64

        struct AnalyzeEntry: Codable {
            let name: String
            let path: String
            let size: Int64
            let isDir: Bool

            enum CodingKeys: String, CodingKey {
                case name, path, size
                case isDir = "is_dir"
            }
        }

        enum CodingKeys: String, CodingKey {
            case path, entries
            case totalSize = "total_size"
            case totalFiles = "total_files"
        }
    }

    private func performScan(directory: URL) async throws -> ScanResult {
        guard let binary = CLIExecutor.findMoleBinary() else {
            throw NSError(
                domain: "DiskModel",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "找不到 mole 可执行文件"]
            )
        }

        let executor = CLIExecutor()
        let command = "\"\(binary.path)\" analyze --json \"\(directory.path)\""

        let response: AnalyzeJSONResponse = try await executor.executeAndParseJSON(
            command: command,
            options: CLIExecutor.ExecutionOptions(
                timeout: 120,
                captureStderr: true,
                parseProgress: false,
                dryRun: false
            ),
            decoder: JSONDecoder()
        )

        let entries = response.entries
            .map { entry in
                DirEntry(
                    name: entry.name,
                    path: URL(fileURLWithPath: entry.path),
                    sizeBytes: UInt64(entry.size),
                    isDirectory: entry.isDir,
                    children: 0
                )
            }
            .sorted { $0.sizeBytes > $1.sizeBytes }

        return ScanResult(
            entries: entries,
            totalSize: UInt64(response.totalSize)
        )
    }
}
