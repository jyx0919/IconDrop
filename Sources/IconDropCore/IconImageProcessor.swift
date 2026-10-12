import AppKit
import CoreGraphics
import ImageIO

public enum IconImageError: Error, LocalizedError {
    case invalidScale
    case unreadableImage
    case emptyImage
    case cannotRender

    public var errorDescription: String? {
        switch self {
        case .invalidScale: "图案大小必须在 10% 到 100% 之间。"
        case .unreadableImage: "无法读取图片。"
        case .emptyImage: "图片没有可见内容。"
        case .cannotRender: "无法生成文件夹图标。"
        }
    }
}

/// Produces a square, transparent icon with consistent visible-content size.
public struct IconImageProcessor {
    public static let canvasSize = 512
    public static let defaultContentScale = 0.78

    public init() {}

    public func makeIcon(from imageURL: URL, contentScale: Double = defaultContentScale) throws -> NSImage {
        guard (0.1...1.0).contains(contentScale) else { throw IconImageError.invalidScale }
        guard let source = CGImageSourceCreateWithURL(imageURL as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 2048,
              ] as CFDictionary) else {
            throw IconImageError.unreadableImage
        }

        let size = Self.canvasSize
        let bytesPerRow = size * 4
        var pixels = [UInt8](repeating: 0, count: size * bytesPerRow)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue

        let fittedImage: CGImage = try pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress, width: size, height: size,
                bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                space: colorSpace, bitmapInfo: bitmapInfo
            ) else { throw IconImageError.cannotRender }
            context.interpolationQuality = .high
            let fit = min(Double(size) / Double(image.width), Double(size) / Double(image.height))
            let width = Double(image.width) * fit
            let height = Double(image.height) * fit
            context.draw(image, in: CGRect(
                x: (Double(size) - width) / 2,
                y: (Double(size) - height) / 2,
                width: width, height: height
            ))
            guard let output = context.makeImage() else { throw IconImageError.cannotRender }
            return output
        }

        var minX = size, minY = size, maxX = -1, maxY = -1
        for y in 0..<size {
            for x in 0..<size where pixels[y * bytesPerRow + x * 4 + 3] > 8 {
                minX = min(minX, x)
                minY = min(minY, y)
                maxX = max(maxX, x)
                maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY else { throw IconImageError.emptyImage }

        let visibleWidth = Double(maxX - minX + 1)
        let visibleHeight = Double(maxY - minY + 1)
        let factor = Double(size) * contentScale / max(visibleWidth, visibleHeight)
        let drawRect = CGRect(
            x: (Double(size) - visibleWidth * factor) / 2 - Double(minX) * factor,
            y: (Double(size) - visibleHeight * factor) / 2 - Double(minY) * factor,
            width: Double(size) * factor,
            height: Double(size) * factor
        )

        guard let outputContext = CGContext(
            data: nil, width: size, height: size,
            bitsPerComponent: 8, bytesPerRow: bytesPerRow,
            space: colorSpace, bitmapInfo: bitmapInfo
        ) else { throw IconImageError.cannotRender }
        outputContext.interpolationQuality = .high
        outputContext.draw(fittedImage, in: drawRect)
        guard let output = outputContext.makeImage() else { throw IconImageError.cannotRender }
        return NSImage(cgImage: output, size: NSSize(width: size, height: size))
    }
}
