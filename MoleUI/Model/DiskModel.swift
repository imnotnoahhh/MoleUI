import Foundation
import Observation

struct DirEntry: Identifiable {
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

struct ScanProgress {
    let currentPath: String
    let itemsScanned: Int
    let bytesScanned: UInt64
}

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

    private struct CachedScan {
        let entries: [DirEntry]
        let totalSize: UInt64
        let timestamp: Date
        let modificationDate: Date?
        var dirty: Bool = false
    }

    private var cache: [String: CachedScan] = [:]
    private let cacheValidityDuration: TimeInterval = 300

    var lastScanTime: Date?

    init() {
        self.currentPath = FileManager.default.homeDirectoryForCurrentUser
    }

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

                let modDate = try? FileManager.default.attributesOfItem(atPath: directory.path)[.modificationDate] as? Date

                cache[directory.path] = CachedScan(
                    entries: result.entries,
                    totalSize: result.totalSize,
                    timestamp: Date(),
                    modificationDate: modDate
                )
                lastScanTime = Date()
            } catch is CancellationError {
                // Scan was cancelled.
            } catch {
                guard !Task.isCancelled else { return }
                self.errorMessage = error.localizedDescription
                self.isScanning = false
                self.progress = nil
            }
        }
    }

    private func loadOrScan(directory: URL) {
        if let cached = cache[directory.path], !cached.dirty {
            let cacheAge = Date().timeIntervalSince(cached.timestamp)
            let isCacheValid = cacheAge < cacheValidityDuration

            var isDirectoryUnmodified = true
            if let cachedModDate = cached.modificationDate,
               let currentModDate = try? FileManager.default.attributesOfItem(atPath: directory.path)[.modificationDate] as? Date
            {
                isDirectoryUnmodified = cachedModDate == currentModDate
            }

            if isCacheValid, isDirectoryUnmodified {
                scanTask?.cancel()
                entries = cached.entries
                totalSize = cached.totalSize
                currentPath = directory
                isScanning = false
                progress = nil
                return
            }
        }

        scan(directory: directory)
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

    func refresh() {
        cache.removeValue(forKey: currentPath.path)
        scan(directory: currentPath)
    }

    func clearCache() {
        cache.removeAll()
    }

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
        invalidateCache(for: currentPath)
        scan(directory: currentPath)
    }

    private func invalidateCache(for url: URL) {
        var path = url
        let home = FileManager.default.homeDirectoryForCurrentUser
        while path.path.count >= home.path.count {
            if var cached = cache[path.path] {
                cached.dirty = true
                cache[path.path] = cached
            }
            path = path.deletingLastPathComponent()
        }
    }

    func revealInFinder(_ entry: DirEntry) {
        NSWorkspace.shared.activateFileViewerSelecting([entry.path])
    }

    private struct ScanResult {
        let entries: [DirEntry]
        let totalSize: UInt64
    }

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
        guard let binary = findAnalyzeBinary() else {
            throw NSError(
                domain: "DiskModel",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "找不到 analyze-go 可执行文件"]
            )
        }

        let response = try await runAnalyzeJSON(binary: binary, directory: directory)

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

    private func findAnalyzeBinary() -> URL? {
        let fm = FileManager.default

        #if DEBUG
            let projectPath = URL(fileURLWithPath: #file)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Resources/mole/bin/analyze-go")

            if fm.isExecutableFile(atPath: projectPath.path) {
                return projectPath
            }
        #endif

        if let bundlePath = Bundle.main.path(forResource: "analyze-go", ofType: nil, inDirectory: "mole/bin") {
            let url = URL(fileURLWithPath: bundlePath)
            if fm.isExecutableFile(atPath: url.path) {
                return url
            }
        }

        return nil
    }

    private func runAnalyzeJSON(binary: URL, directory: URL) async throws -> AnalyzeJSONResponse {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = binary
            process.arguments = ["-json", directory.path]
            process.environment = ProcessInfo.processInfo.environment

            let stdout = Pipe()
            let stderr = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr

            process.terminationHandler = { process in
                let stdoutData = stdout.fileHandleForReading.readDataToEndOfFile()
                let stderrData = stderr.fileHandleForReading.readDataToEndOfFile()

                if process.terminationStatus != 0 {
                    let message = String(data: stderrData, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    let error = NSError(
                        domain: "DiskModel",
                        code: Int(process.terminationStatus),
                        userInfo: [
                            NSLocalizedDescriptionKey: message?.isEmpty == false ? message! : "磁盘扫描失败",
                        ]
                    )
                    continuation.resume(throwing: error)
                    return
                }

                do {
                    let response = try JSONDecoder().decode(AnalyzeJSONResponse.self, from: stdoutData)
                    continuation.resume(returning: response)
                } catch {
                    continuation.resume(throwing: error)
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
