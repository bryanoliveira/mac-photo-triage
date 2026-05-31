import Foundation
import CoreGraphics
import ImageIO

/// File extension categories for image processing
enum FileExtensions {
    /// Supported JPEG extensions (case-insensitive matching)
    static let jpeg: Set<String> = ["jpg", "jpeg"]

    /// Supported RAW format extensions (case-insensitive matching)
    static let raw: Set<String> = [
        "cr2",  // Canon RAW 2
        "cr3",  // Canon RAW 3
        "nef",  // Nikon Electronic Format
        "arw",  // Sony Alpha RAW
        "dng",  // Digital Negative (Adobe)
        "raf",  // Fujifilm RAW
        "orf",  // Olympus RAW
        "rw2"   // Panasonic RAW
    ]

    /// All supported image extensions
    static let allSupported: Set<String> = jpeg.union(raw)

    /// Check if extension is JPEG
    static func isJPEG(_ ext: String) -> Bool {
        jpeg.contains(ext.lowercased())
    }

    /// Check if extension is RAW
    static func isRAW(_ ext: String) -> Bool {
        raw.contains(ext.lowercased())
    }

    /// Check if extension is supported
    static func isSupported(_ ext: String) -> Bool {
        allSupported.contains(ext.lowercased())
    }

    /// Get display priority (JPEG preferred over RAW)
    static func displayPriority(_ ext: String) -> Int {
        if isJPEG(ext) { return 0 }
        if isRAW(ext) { return 1 }
        return 999
    }
}

// MARK: - EXIF orientation helpers

extension CGImageSource {
    /// EXIF orientation tag from the first image in this source, defaulting to .up (no rotation).
    var exifOrientation: CGImagePropertyOrientation {
        guard let props = CGImageSourceCopyPropertiesAtIndex(self, 0, nil) as? [CFString: Any],
              let raw = props[kCGImagePropertyOrientation] as? UInt32,
              let o = CGImagePropertyOrientation(rawValue: raw) else { return .up }
        return o
    }
}

extension CGImage {
    /// Return a new image whose pixels have been rotated to match the EXIF display orientation.
    ///
    /// `CGImageSourceCreateImageAtIndex` ignores the EXIF orientation tag; use this to produce
    /// display-correct pixels before applying a crop rect that was drawn in display space.
    /// Handles orientations 1 (no-op), 3 (180°), 6 (90° CW), and 8 (90° CCW).
    /// Mirrored orientations (2, 4, 5, 7) fall back to the original image.
    func applyingExifOrientation(_ orientation: CGImagePropertyOrientation) -> CGImage? {
        guard orientation != .up else { return self }

        let w = self.width, h = self.height
        let newW: Int, newH: Int

        switch orientation {
        case .right, .left, .rightMirrored, .leftMirrored:
            newW = h; newH = w   // 90° rotations swap dimensions
        default:
            newW = w; newH = h   // 180° keeps dimensions
        }

        guard let ctx = CGContext(
            data: nil, width: newW, height: newH,
            bitsPerComponent: bitsPerComponent, bytesPerRow: 0,
            space: colorSpace ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: bitmapInfo.rawValue
        ) else { return nil }

        // CGContext origin is bottom-left (y-up). Transforms below produce the visual
        // rotation that matches what NSImage/Finder show when respecting the EXIF tag.
        switch orientation {
        case .right:   // 90° CW for display
            ctx.translateBy(x: 0, y: CGFloat(w)); ctx.rotate(by: -.pi / 2)
        case .left:    // 90° CCW for display
            ctx.translateBy(x: CGFloat(h), y: 0); ctx.rotate(by: .pi / 2)
        case .down:    // 180°
            ctx.translateBy(x: CGFloat(w), y: CGFloat(h)); ctx.rotate(by: .pi)
        default:
            return self  // mirrored orientations not handled
        }

        ctx.draw(self, in: CGRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h)))
        return ctx.makeImage()
    }
}

extension URL {
    /// The file extension without the leading dot, lowercased
    var fileExtensionLowercased: String {
        pathExtension.lowercased()
    }

    /// The filename without extension (stem)
    var stem: String {
        deletingPathExtension().lastPathComponent
    }

    /// Check if this URL represents a JPEG file
    var isJPEG: Bool {
        FileExtensions.isJPEG(pathExtension)
    }

    /// Check if this URL represents a RAW file
    var isRAW: Bool {
        FileExtensions.isRAW(pathExtension)
    }

    /// Check if this URL represents a supported image file
    var isSupportedImage: Bool {
        FileExtensions.isSupported(pathExtension)
    }
}
