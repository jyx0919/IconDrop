import AppKit
import XCTest
@testable import IconDropCore

final class IconDropCoreTests: XCTestCase {
    func testBackgroundRemovalMakesBackdropTransparentButKeepsSubject() throws {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }

        let imageURL = temporary.appendingPathComponent("subject.png")
        let context = try XCTUnwrap(CGContext(
            data: nil, width: 512, height: 512, bitsPerComponent: 8,
            bytesPerRow: 512 * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 512, height: 512))
        context.setFillColor(NSColor.systemRed.cgColor)
        context.fillEllipse(in: CGRect(x: 108, y: 108, width: 296, height: 296))
        let png = try XCTUnwrap(NSBitmapImageRep(cgImage: XCTUnwrap(context.makeImage())).representation(using: .png, properties: [:]))
        try png.write(to: imageURL)

        let processor = IconImageProcessor()
        let original = try processor.makeIcon(from: imageURL)
        let removed = try processor.makeIcon(from: imageURL, removingBackground: true)
        XCTAssertGreaterThan(try alpha(at: CGPoint(x: 100, y: 100), in: original), 0.9)
        XCTAssertLessThan(try alpha(at: CGPoint(x: 100, y: 100), in: removed), 0.1)
        XCTAssertGreaterThan(try alpha(at: CGPoint(x: 256, y: 256), in: removed), 0.9)
    }

    func testVisibleContentHasConsistentSizeAcrossSourceImages() throws {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }

        let small = temporary.appendingPathComponent("small.png")
        let large = temporary.appendingPathComponent("large.png")
        try makePNG(at: small, squareSize: 40)
        try makePNG(at: large, squareSize: 180)

        let processor = IconImageProcessor()
        let smallBounds = try alphaBounds(of: processor.makeIcon(from: small))
        let largeBounds = try alphaBounds(of: processor.makeIcon(from: large))

        XCTAssertLessThanOrEqual(abs(smallBounds.width - largeBounds.width), 4)
        XCTAssertLessThanOrEqual(abs(smallBounds.height - largeBounds.height), 4)
        XCTAssertEqual(smallBounds.width, 399, accuracy: 5)
        XCTAssertEqual(smallBounds.midX, 256, accuracy: 3)
        XCTAssertEqual(smallBounds.midY, 256, accuracy: 3)
    }

    func testBatchHandlesSeparateImagesAndDuplicateFolderWithoutOverwritingTwice() throws {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let first = temporary.appendingPathComponent("first", isDirectory: true)
        let second = temporary.appendingPathComponent("second", isDirectory: true)
        try FileManager.default.createDirectory(at: first, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: second, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }

        let image = temporary.appendingPathComponent("image.png")
        try makePNG(at: image, squareSize: 100)
        let writer = RecordingWriter()
        let store = OriginalIconStore(directoryURL: temporary.appendingPathComponent("backups"))
        let service = FolderIconService(writer: writer, originalIconReader: StubOriginalIconReader(), originalIconStore: store)
        var progress: [(Int, Int)] = []
        let results = service.apply([
            IconAssignment(imageURL: image, folderURLs: [first, second]),
            IconAssignment(imageURL: image, folderURLs: [first]),
        ], onProgress: { progress.append(($0, $1)) })

        XCTAssertEqual(results.count, 3)
        XCTAssertTrue(results[0].succeeded)
        XCTAssertTrue(results[1].succeeded)
        XCTAssertEqual(results[2].error as? FolderIconError, .duplicateFolder)
        XCTAssertEqual(writer.calls, [first, second])
        XCTAssertEqual(progress.map { $0.0 }, [1, 2, 3])
        XCTAssertEqual(progress.map { $0.1 }, [3, 3, 3])
        XCTAssertTrue(store.hasBackup(for: first))
        XCTAssertTrue(store.hasBackup(for: second))
    }

    func testRestoreDefaultSendsNilIcon() throws {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }

        let writer = RecordingWriter()
        let store = OriginalIconStore(directoryURL: temporary.appendingPathComponent("backups"))
        let results = FolderIconService(writer: writer, originalIconReader: StubOriginalIconReader(), originalIconStore: store).restoreDefaultIcon(for: [temporary])
        XCTAssertTrue(results[0].succeeded)
        XCTAssertEqual(writer.calls, [temporary])
        XCTAssertEqual(writer.nilIconCalls, 1)
    }

    func testOriginalCustomIconSurvivesAnotherEditAndServiceRestart() throws {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let folder = temporary.appendingPathComponent("folder", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }

        let oldImageURL = temporary.appendingPathComponent("old.png")
        let newImageURL = temporary.appendingPathComponent("new.png")
        try makePNG(at: oldImageURL, squareSize: 40)
        try makePNG(at: newImageURL, squareSize: 180)
        let originalIcon = try XCTUnwrap(NSImage(contentsOf: oldImageURL))
        let store = OriginalIconStore(directoryURL: temporary.appendingPathComponent("backups"))
        let writer = RecordingWriter()
        let reader = StubOriginalIconReader(icon: originalIcon)

        let firstService = FolderIconService(writer: writer, originalIconReader: reader, originalIconStore: store)
        XCTAssertTrue(firstService.apply([IconAssignment(imageURL: newImageURL, folderURLs: [folder])])[0].succeeded)
        XCTAssertTrue(firstService.apply([IconAssignment(imageURL: newImageURL, folderURLs: [folder])])[0].succeeded)
        XCTAssertEqual(reader.readCount, 1)

        let restartedService = FolderIconService(writer: writer, originalIconReader: reader, originalIconStore: store)
        XCTAssertTrue(restartedService.restoreOriginalIcon(for: [folder])[0].succeeded)
        XCTAssertNotNil(writer.images.last!)
        XCTAssertFalse(store.hasBackup(for: folder))
    }

    func testWorkspaceReaderCapturesActualFinderCustomArtwork() throws {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let folder = temporary.appendingPathComponent("folder", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }

        let originalURL = temporary.appendingPathComponent("original.png")
        try makePNG(at: originalURL, squareSize: 180)
        let original = try XCTUnwrap(NSImage(contentsOf: originalURL))
        XCTAssertTrue(NSWorkspace.shared.setIcon(original, forFile: folder.path, options: []))

        let captured = try XCTUnwrap(WorkspaceOriginalIconReader().customIcon(for: folder))
        let cgImage = try XCTUnwrap(captured.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        let pixel = try XCTUnwrap(bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 2))
        let center = try XCTUnwrap(pixel.usingColorSpace(.deviceRGB))
        XCTAssertGreaterThan(center.redComponent, center.greenComponent + 0.3)
    }

    func testLegacyCustomBackupBlocksRestoreAndFurtherEdits() throws {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let folder = temporary.appendingPathComponent("folder", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }

        let imageURL = temporary.appendingPathComponent("image.png")
        try makePNG(at: imageURL, squareSize: 100)
        let image = try XCTUnwrap(NSImage(contentsOf: imageURL))
        let store = OriginalIconStore(directoryURL: temporary.appendingPathComponent("backups"))
        try store.saveIfMissing(image, for: folder)
        let backupURL = try removeVersionFromBackup(in: store)
        let originalBackup = try Data(contentsOf: backupURL)
        let writer = RecordingWriter()
        let service = FolderIconService(writer: writer, originalIconReader: StubOriginalIconReader(), originalIconStore: store)

        XCTAssertEqual(service.restoreOriginalIcon(for: [folder])[0].error as? OriginalIconError, .unverifiedLegacyBackup)
        XCTAssertEqual(service.apply([IconAssignment(imageURL: imageURL, folderURLs: [folder])])[0].error as? OriginalIconError, .unverifiedLegacyBackup)
        XCTAssertTrue(writer.calls.isEmpty)
        XCTAssertEqual(try Data(contentsOf: backupURL), originalBackup)
    }

    func testLegacyDefaultBackupCanStillBeRestored() throws {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }

        let store = OriginalIconStore(directoryURL: temporary.appendingPathComponent("backups"))
        try store.saveIfMissing(nil, for: temporary)
        _ = try removeVersionFromBackup(in: store)
        let writer = RecordingWriter()
        let service = FolderIconService(writer: writer, originalIconReader: StubOriginalIconReader(), originalIconStore: store)

        XCTAssertTrue(service.restoreOriginalIcon(for: [temporary])[0].succeeded)
        XCTAssertEqual(writer.nilIconCalls, 1)
        XCTAssertFalse(store.hasBackup(for: temporary))
    }

    func testMissingBackupNeverClearsAnIcon() throws {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }

        let writer = RecordingWriter()
        let store = OriginalIconStore(directoryURL: temporary.appendingPathComponent("backups"))
        let result = FolderIconService(writer: writer, originalIconReader: StubOriginalIconReader(), originalIconStore: store).restoreOriginalIcon(for: [temporary])[0]
        XCTAssertEqual(result.error as? OriginalIconError, .noBackup)
        XCTAssertTrue(writer.calls.isEmpty)
    }

    func testCorruptBackupStopsAnotherEdit() throws {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let folder = temporary.appendingPathComponent("folder", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }

        let image = temporary.appendingPathComponent("image.png")
        try makePNG(at: image, squareSize: 100)
        let store = OriginalIconStore(directoryURL: temporary.appendingPathComponent("backups"))
        let writer = RecordingWriter()
        let service = FolderIconService(writer: writer, originalIconReader: StubOriginalIconReader(), originalIconStore: store)
        XCTAssertTrue(service.apply([IconAssignment(imageURL: image, folderURLs: [folder])])[0].succeeded)

        let backupURL = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: store.directoryURL, includingPropertiesForKeys: nil).first)
        try Data("broken".utf8).write(to: backupURL)
        let second = service.apply([IconAssignment(imageURL: image, folderURLs: [folder])])[0]
        XCTAssertEqual(second.error as? OriginalIconError, .invalidBackup)
        XCTAssertEqual(writer.calls.count, 1)
    }

    private func removeVersionFromBackup(in store: OriginalIconStore) throws -> URL {
        let backupURL = try XCTUnwrap(FileManager.default.contentsOfDirectory(
            at: store.directoryURL, includingPropertiesForKeys: nil
        ).first)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: backupURL)) as? [String: Any])
        XCTAssertEqual(json.removeValue(forKey: "formatVersion") as? Int, 2)
        try JSONSerialization.data(withJSONObject: json).write(to: backupURL)
        return backupURL
    }

    private func makePNG(at url: URL, squareSize: Int) throws {
        let size = 200
        let context = try XCTUnwrap(CGContext(
            data: nil, width: size, height: size, bitsPerComponent: 8,
            bytesPerRow: size * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(NSColor.systemRed.cgColor)
        context.fill(CGRect(x: (size - squareSize) / 2, y: (size - squareSize) / 2, width: squareSize, height: squareSize))
        let image = try XCTUnwrap(context.makeImage())
        let png = try XCTUnwrap(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
        try png.write(to: url)
    }

    private func alphaBounds(of image: NSImage) throws -> CGRect {
        let cgImage = try XCTUnwrap(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let representation = NSBitmapImageRep(cgImage: cgImage)
        var minX = 512, minY = 512, maxX = -1, maxY = -1
        for y in 0..<512 {
            for x in 0..<512 where (representation.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.03 {
                minX = min(minX, x)
                minY = min(minY, y)
                maxX = max(maxX, x)
                maxY = max(maxY, y)
            }
        }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    private func alpha(at point: CGPoint, in image: NSImage) throws -> CGFloat {
        let cgImage = try XCTUnwrap(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        return try XCTUnwrap(NSBitmapImageRep(cgImage: cgImage).colorAt(x: Int(point.x), y: Int(point.y))).alphaComponent
    }
}

private final class RecordingWriter: FolderIconWriting, @unchecked Sendable {
    var calls: [URL] = []
    var images: [NSImage?] = []
    var nilIconCalls = 0

    func setIcon(_ image: NSImage?, for folderURL: URL) -> Bool {
        calls.append(folderURL)
        images.append(image)
        if image == nil { nilIconCalls += 1 }
        return true
    }
}

private final class StubOriginalIconReader: OriginalIconReading, @unchecked Sendable {
    let icon: NSImage?
    var readCount = 0

    init(icon: NSImage? = nil) { self.icon = icon }

    func customIcon(for folderURL: URL) throws -> NSImage? {
        readCount += 1
        return icon
    }
}
