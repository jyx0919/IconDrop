import AppKit

public struct IconAssignment: Sendable {
    public let imageURL: URL
    public let folderURLs: [URL]
    public let removeBackground: Bool

    public init(imageURL: URL, folderURLs: [URL], removeBackground: Bool = false) {
        self.imageURL = imageURL
        self.folderURLs = folderURLs
        self.removeBackground = removeBackground
    }
}

public enum FolderIconError: Error, LocalizedError, Equatable {
    case notFolder
    case duplicateFolder
    case updateFailed
    case backupCleanupFailed

    public var errorDescription: String? {
        switch self {
        case .notFolder: "目标不是可访问的文件夹。"
        case .duplicateFolder: "同一文件夹在本批次中重复出现。"
        case .updateFailed: "无法修改文件夹图标；请检查写入权限。"
        case .backupCleanupFailed: "图标已恢复，但无法清除原图标备份。"
        }
    }
}

public struct FolderIconResult {
    public let folderURL: URL
    public let error: Error?
    public var succeeded: Bool { error == nil }
}

public protocol FolderIconWriting: Sendable {
    func setIcon(_ image: NSImage?, for folderURL: URL) -> Bool
}

public struct WorkspaceFolderIconWriter: FolderIconWriting {
    public init() {}

    public func setIcon(_ image: NSImage?, for folderURL: URL) -> Bool {
        NSWorkspace.shared.setIcon(image, forFile: folderURL.path, options: [])
    }
}

/// Applies assignments in order. Each folder can appear only once in a batch.
/// A failed folder does not prevent the remaining folders from being processed.
public struct FolderIconService: Sendable {
    private let processor: IconImageProcessor
    private let writer: any FolderIconWriting
    private let originalIconReader: any OriginalIconReading
    private let originalIconStore: OriginalIconStore

    public init(
        processor: IconImageProcessor = IconImageProcessor(),
        writer: any FolderIconWriting = WorkspaceFolderIconWriter(),
        originalIconReader: any OriginalIconReading = WorkspaceOriginalIconReader(),
        originalIconStore: OriginalIconStore = OriginalIconStore()
    ) {
        self.processor = processor
        self.writer = writer
        self.originalIconReader = originalIconReader
        self.originalIconStore = originalIconStore
    }

    public func apply(
        _ assignments: [IconAssignment],
        contentScale: Double = IconImageProcessor.defaultContentScale,
        onProgress: ((Int, Int) -> Void)? = nil
    ) -> [FolderIconResult] {
        var seen = Set<URL>()
        var results: [FolderIconResult] = []
        let totalCount = assignments.reduce(0) { $0 + $1.folderURLs.count }

        for assignment in assignments {
            let icon = Result {
                try processor.makeIcon(
                    from: assignment.imageURL,
                    contentScale: contentScale,
                    removingBackground: assignment.removeBackground
                )
            }
            for folder in assignment.folderURLs {
                let normalizedFolder = folder.standardizedFileURL.resolvingSymlinksInPath()
                let error: Error?
                if !seen.insert(normalizedFolder).inserted {
                    error = FolderIconError.duplicateFolder
                } else if (try? normalizedFolder.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory != true {
                    error = FolderIconError.notFolder
                } else {
                    switch icon {
                    case .success(let image):
                        do {
                            try saveOriginalIconIfNeeded(for: normalizedFolder)
                            error = writer.setIcon(image, for: normalizedFolder) ? nil : FolderIconError.updateFailed
                        } catch let caught {
                            error = caught
                        }
                    case .failure(let imageError):
                        error = imageError
                    }
                }
                results.append(FolderIconResult(folderURL: folder, error: error))
                onProgress?(results.count, totalCount)
            }
        }
        return results
    }

    public func restoreDefaultIcon(for folderURLs: [URL]) -> [FolderIconResult] {
        var seen = Set<URL>()
        return folderURLs.map { folder in
            let normalizedFolder = folder.standardizedFileURL.resolvingSymlinksInPath()
            let error: Error?
            if !seen.insert(normalizedFolder).inserted {
                error = FolderIconError.duplicateFolder
            } else if (try? normalizedFolder.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory != true {
                error = FolderIconError.notFolder
            } else {
                do {
                    try saveOriginalIconIfNeeded(for: normalizedFolder)
                    error = writer.setIcon(nil, for: normalizedFolder) ? nil : FolderIconError.updateFailed
                } catch let caught {
                    error = caught
                }
            }
            return FolderIconResult(folderURL: folder, error: error)
        }
    }

    /// Restores the state from before IconDrop first changed each folder.
    /// A missing backup is reported instead of silently switching to the default icon.
    public func restoreOriginalIcon(for folderURLs: [URL]) -> [FolderIconResult] {
        var seen = Set<URL>()
        return folderURLs.map { folder in
            let normalizedFolder = folder.standardizedFileURL.resolvingSymlinksInPath()
            let error: Error?
            if !seen.insert(normalizedFolder).inserted {
                error = FolderIconError.duplicateFolder
            } else if (try? normalizedFolder.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory != true {
                error = FolderIconError.notFolder
            } else {
                do {
                    let original = try originalIconStore.originalIcon(for: normalizedFolder)
                    if writer.setIcon(original, for: normalizedFolder) {
                        do {
                            try originalIconStore.removeBackup(for: normalizedFolder)
                            error = nil
                        } catch let cleanupFailure {
                            _ = cleanupFailure
                            error = FolderIconError.backupCleanupFailed
                        }
                    } else {
                        error = FolderIconError.updateFailed
                    }
                } catch let caught {
                    error = caught
                }
            }
            return FolderIconResult(folderURL: folder, error: error)
        }
    }

    private func saveOriginalIconIfNeeded(for folderURL: URL) throws {
        if originalIconStore.hasBackup(for: folderURL) {
            // A damaged backup must stop the edit instead of silently losing the original icon.
            _ = try originalIconStore.originalIcon(for: folderURL)
            return
        }
        let original = try originalIconReader.customIcon(for: folderURL)
        try originalIconStore.saveIfMissing(original, for: folderURL)
    }
}
