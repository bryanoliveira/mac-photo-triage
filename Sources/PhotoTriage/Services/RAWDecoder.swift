import Foundation
import AppKit
import CoreImage
import ImageIO

/// Service for decoding RAW images to displayable format
enum RAWDecoder {
    /// Decode a RAW image file to NSImage
    static func decode(url: URL) -> NSImage? {
        // Use Core Image RAW filter for high quality decode
        guard let rawFilter = CIRAWFilter(imageURL: url) else {
            // Fallback to ImageIO
            return decodeWithImageIO(url: url)
        }

        // Apply default processing
        rawFilter.extendedDynamicRangeAmount = 0
        rawFilter.baselineExposure = 0
        rawFilter.boostAmount = 0

        guard let outputImage = rawFilter.outputImage else {
            return decodeWithImageIO(url: url)
        }

        // Convert CIImage to NSImage
        let context = CIContext()
        guard let cgImage = context.createCGImage(outputImage, from: outputImage.extent) else {
            return nil
        }

        return NSImage(cgImage: cgImage, size: NSSize(
            width: cgImage.width,
            height: cgImage.height
        ))
    }

    /// Fallback decode using ImageIO (works for most formats)
    private static func decodeWithImageIO(url: URL) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return nil
        }

        let options: [CFString: Any] = [
            kCGImageSourceShouldCache: false,
            kCGImageSourceShouldAllowFloat: true
        ]

        guard let cgImage = CGImageSourceCreateImageAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }

        return NSImage(cgImage: cgImage, size: NSSize(
            width: cgImage.width,
            height: cgImage.height
        ))
    }

    /// Generate a display-quality thumbnail from RAW
    static func generateThumbnail(url: URL, maxSize: CGFloat = 512) -> NSImage? {
        let options: [CFString: Any] = [
            kCGImageSourceThumbnailMaxPixelSize: maxSize,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]

        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }

        return NSImage(cgImage: cgImage, size: NSSize(
            width: cgImage.width,
            height: cgImage.height
        ))
    }

    /// Check if a URL is a supported RAW format
    static func isSupported(url: URL) -> Bool {
        url.isRAW
    }
}
