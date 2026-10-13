import AppKit
import CryptoKit
import Darwin

public enum OriginalIconError: Error, LocalizedError, Equatable {
    case cannotReadIconState
    case cannotEncodeIcon
    case cannotSaveBackup
    case noBackup
    case invalidBackup

    public var errorDescription: String? {
        switch self {
        case .cannotReadIconState: "无法读取文件夹原有的图标状态。"
        case .cannotEncodeIcon: "无法保存原有的自定义图标。"
        case .cannotSaveBackup: "无法保存原图标备份；文件夹未被修改。"
        case .noBackup: "没有找到这个文件夹的原图标备份。"
        case .invalidBackup: "原图标备份已损坏。"
        }
    }
}

public protocol OriginalIconReading: Sendable {
    /// Returns nil when the folder has no Finder custom icon.
    func customIcon(for folderURL: URL) throws -> NSImage?
}

public struct WorkspaceOriginalIconReader: OriginalIconReading {
    public init() {}

    public func customIcon(for folderURL: URL) throws -> NSImage? {
        // Finder stores its custom-icon flag in bytes 8–9 of FinderInfo.
        // URLResourceValues.customIcon is not reliable for folder icons set by NSWorkspace.
        var finderInfo = [UInt8](repeating: 0, count: 32)
        let count = folderURL.path.withCString { path in
            "com.apple.FinderInfo".withCString { name in
                getxattr(path, name, &finderInfo, finderInfo.count, 0, 0)
            }
        }
        if count < 0 {
            if errno == ENOATTR { return nil }
            throw OriginalIconError.cannotReadIconState
        }
        guard count >= 10 else { throw OriginalIconError.cannotReadIconState }
        let flags = UInt16(finderInfo[8]) << 8 | UInt16(finderInfo[9])
        guard flags & 0x0400 != 0 else { return nil }
        return NSWorkspace.shared.icon(forFile: folderURL.path)
    }
}

/// Saves the state before IconDrop first changes a folder. Backups survive app restarts.
public struct OriginalIconStore: Sendable {
    public let directoryURL: URL

    public init(directoryURL: URL? = nil) {
        if let directoryURL {
            self.directoryURL = directoryURL
        } else {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            self.directoryURL = support.appendingPathComponent("IconDrop/OriginalIcons", isDirectory: true)
        }
    }

    public func hasBackup(for folderURL: URL) -> Bool {
        FileManager.default.fileExists(atPath: backupURL(for: folderURL).path)
    }

    public func saveIfMissing(_ icon: NSImage?, for folderURL: URL) throws {
        let destination = backupURL(for: folderURL)
        if FileManager.default.fileExists(atPath: destination.path) { return }

        let png: Data?
        if let icon {
            var proposedRect = NSRect(x: 0, y: 0, width: 512, height: 512)
            guard let cgImage = icon.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil),
                  let data = NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:]) else {
                throw OriginalIconError.cannotEncodeIcon
            }
            png = data
        } else {
            png = nil
        }

        let backup = Backup(folderPath: canonicalPath(for: folderURL), originalIconPNG: png)
        do {
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(backup)
            try data.write(to: destination, options: .atomic)
        } catch {
            throw OriginalIconError.cannotSaveBackup
        }
    }

    public func originalIcon(for folderURL: URL) throws -> NSImage? {
        let destination = backupURL(for: folderURL)
        guard FileManager.default.fileExists(atPath: destination.path) else { throw OriginalIconError.noBackup }
        do {
            let backup = try JSONDecoder().decode(Backup.self, from: Data(contentsOf: destination))
            guard backup.folderPath == canonicalPath(for: folderURL) else { throw OriginalIconError.invalidBackup }
            if let png = backup.originalIconPNG {
                guard let image = NSImage(data: png) else { throw OriginalIconError.invalidBackup }
                return image
            }
            return nil
        } catch let error as OriginalIconError {
            throw error
        } catch {
            throw OriginalIconError.invalidBackup
        }
    }

    public func removeBackup(for folderURL: URL) throws {
        try FileManager.default.removeItem(at: backupURL(for: folderURL))
    }

    private func backupURL(for folderURL: URL) -> URL {
        let digest = SHA256.hash(data: Data(canonicalPath(for: folderURL).utf8))
        let name = digest.map { String(format: "%02x", $0) }.joined() + ".json"
        return directoryURL.appendingPathComponent(name)
    }

    private func canonicalPath(for folderURL: URL) -> String {
        folderURL.standardizedFileURL.resolvingSymlinksInPath().path
    }
}

private struct Backup: Codable {
    let folderPath: String
    let originalIconPNG: Data?
}
