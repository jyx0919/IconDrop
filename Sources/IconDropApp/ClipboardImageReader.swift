import AppKit

enum ClipboardImageSource {
    case file(URL)
    case image(NSImage)
}

enum ClipboardImageError: Error, LocalizedError {
    case multipleFiles
    case noImage
    case cannotSave

    var errorDescription: String? {
        switch self {
        case .multipleFiles: "剪贴板里有多个文件，请一次只复制一张图片。"
        case .noImage: "剪贴板里没有可用的图片。"
        case .cannotSave: "无法准备剪贴板中的图片。"
        }
    }
}

struct ClipboardImageReader {
    func read(from pasteboard: NSPasteboard) throws -> ClipboardImageSource {
        let urls = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] ?? []
        if !urls.isEmpty {
            guard urls.count == 1 else { throw ClipboardImageError.multipleFiles }
            return .file(urls[0])
        }
        if let image = NSImage(pasteboard: pasteboard) { return .image(image) }
        for type in [NSPasteboard.PasteboardType.png, .tiff] {
            if let data = pasteboard.data(forType: type), let image = NSImage(data: data) {
                return .image(image)
            }
        }
        throw ClipboardImageError.noImage
    }

    func save(_ image: NSImage, in directory: URL) throws -> URL {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let png = NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:]) else {
            throw ClipboardImageError.cannotSave
        }
        let folder = directory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let url = folder.appendingPathComponent("粘贴的图片.png")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try png.write(to: url, options: .atomic)
            return url
        } catch {
            try? FileManager.default.removeItem(at: folder)
            throw ClipboardImageError.cannotSave
        }
    }
}
