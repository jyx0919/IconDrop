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
        case .cannotReadIconState: "无法安全读取文件夹原有的自定义图标；文件夹未被修改。"
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

        // NSWorkspace can return the generic folder artwork immediately after setIcon.
        // Finder stores the actual custom image as an icns resource in Icon\r.
        let forkURL = folderURL.appendingPathComponent("Icon\r")
            .appendingPathComponent("..namedfork/rsrc")
        guard let fork = try? Data(contentsOf: forkURL),
              let iconData = Self.iconData(in: fork),
              let image = NSImage(data: iconData) else {
            throw OriginalIconError.cannotReadIconState
        }
        return image
    }

    private static func iconData(in fork: Data) -> Data? {
        guard let dataOffset = uint32(fork, at: 0),
              let mapOffset = uint32(fork, at: 4),
              let dataLength = uint32(fork, at: 8),
              let mapLength = uint32(fork, at: 12),
              dataOffset + dataLength <= fork.count,
              mapLength >= 28, mapOffset + mapLength <= fork.count,
              let typeListOffset = uint16(fork, at: mapOffset + 24) else { return nil }

        let typeList = mapOffset + typeListOffset
        guard let typeCountMinusOne = uint16(fork, at: typeList) else { return nil }
        for typeIndex in 0...typeCountMinusOne {
            let entry = typeList + 2 + typeIndex * 8
            guard entry + 8 <= mapOffset + mapLength,
                  let resourceCountMinusOne = uint16(fork, at: entry + 4),
                  let referenceOffset = uint16(fork, at: entry + 6) else { return nil }
            guard fork[entry] == 0x69, fork[entry + 1] == 0x63,
                  fork[entry + 2] == 0x6e, fork[entry + 3] == 0x73 else { continue }

            for resourceIndex in 0...resourceCountMinusOne {
                let reference = typeList + referenceOffset + resourceIndex * 12
                guard reference + 12 <= mapOffset + mapLength,
                      let attributesAndOffset = uint32(fork, at: reference + 4) else { return nil }
                let resourceStart = dataOffset + (attributesAndOffset & 0x00ff_ffff)
                guard let resourceLength = uint32(fork, at: resourceStart),
                      resourceStart + 4 + resourceLength <= dataOffset + dataLength else { return nil }
                let payload = fork[(resourceStart + 4)..<(resourceStart + 4 + resourceLength)]
                if payload.starts(with: Data("icns".utf8)) { return Data(payload) }
            }
        }
        return nil
    }

    private static func uint16(_ data: Data, at offset: Int) -> Int? {
        guard offset >= 0, offset + 2 <= data.count else { return nil }
        return Int(data[offset]) << 8 | Int(data[offset + 1])
    }

    private static func uint32(_ data: Data, at offset: Int) -> Int? {
        guard offset >= 0, offset + 4 <= data.count else { return nil }
        return Int(data[offset]) << 24 | Int(data[offset + 1]) << 16
            | Int(data[offset + 2]) << 8 | Int(data[offset + 3])
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
