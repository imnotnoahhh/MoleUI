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

    private func performScan(directory: URL) async throws -> ScanResult {
        let fm = FileManager.default
        let contents = try fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .totalFileAllocatedSizeKey],
            options: []
        )

        let sized: [(URL, Bool)] = contents.compactMap { url in
            guard let vals = try? url.resourceValues(forKeys: [.isDirectoryKey]) else {
                return nil
            }
            return (url, vals.isDirectory ?? false)
        }

        // Calculate sizes in parallel for top-level children
        let results = try await withThrowingTaskGroup(
            of: (URL, Bool, UInt64, Int).self
        ) { group in
            for (url, isDir) in sized {
                group.addTask {
                    try Task.checkCancellation()
                    let taskFM = FileManager()
                    if isDir {
                        let size = Self.directorySize(at: url)
                        let childCount = (try? taskFM.contentsOfDirectory(
                            at: url,
                            includingPropertiesForKeys: nil,
                            options: [.skipsSubdirectoryDescendants]
                        ).count) ?? 0
                        return (url, true, size, childCount)
                    } else {
                        let vals = try url.resourceValues(
                            forKeys: [.totalFileAllocatedSizeKey, .fileSizeKey]
                        )
                        let size = UInt64(vals.totalFileAllocatedSize ?? vals.fileSize ?? 0)
                        return (url, false, size, 0)
                    }
                }
            }

            var collected: [(URL, Bool, UInt64, Int)] = []
            for try await item in group {
                collected.append(item)
            }
            return collected
        }

        let entries = results
            .map { url, isDir, size, children in
                DirEntry(
                    name: url.lastPathComponent,
                    path: url,
                    sizeBytes: size,
                    isDirectory: isDir,
                    children: children
                )
            }
            .sorted { $0.sizeBytes > $1.sizeBytes }
            .prefix(50)

        let total = results.reduce(UInt64(0)) { $0 + $1.2 }
        return ScanResult(entries: Array(entries), totalSize: total)
    }

    // MARK: - Helpers

    private nonisolated static func directorySize(at url: URL) -> UInt64 {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileSizeKey],
            options: [.skipsPackageDescendants],
            errorHandler: nil
        ) else {
            return 0
        }

        var total: UInt64 = 0
        for case let fileURL as URL in enumerator {
            guard let vals = try? fileURL.resourceValues(
                forKeys: [.totalFileAllocatedSizeKey, .fileSizeKey]
            ) else {
                continue
            }
            total += UInt64(vals.totalFileAllocatedSize ?? vals.fileSize ?? 0)
        }
        return total
    }
}
