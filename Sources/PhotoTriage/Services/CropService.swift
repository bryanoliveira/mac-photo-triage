import Foundation
import AppKit
import CoreImage
import CoreGraphics
import ImageIO

/// Crop aspect ratio presets
enum CropPreset: String, CaseIterable, Identifiable {
    case free = "Free"
    case square = "1:1"
    case fourThree = "4:3"
    case threeTwo = "3:2"
    case sixteenNine = "16:9"
    case fiveFour = "5:4"
    case twoThree = "2:3"
    case nineSixteen = "9:16"

    var id: String { rawValue }

    /// Aspect ratio (width / height)
    var ratio: CGFloat? {
        switch self {
        case .free: return nil
        case .square: return 1.0
        case .fourThree: return 4.0 / 3.0
        case .threeTwo: return 3.0 / 2.0
        case .sixteenNine: return 16.0 / 9.0
        case .fiveFour: return 5.0 / 4.0
        case .twoThree: return 2.0 / 3.0
        case .nineSixteen: return 9.0 / 16.0
        }
    }
}

/// Represents a crop region
struct CropRect: Equatable {
    var x: CGFloat
    var y: CGFloat
    var width: CGFloat
    var height: CGFloat

    var cgRect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }

    var aspectRatio: CGFloat {
        width / height
    }

    /// Constrain to aspect ratio
    mutating func constrain(to ratio: CGFloat?, within bounds: CGSize) {
        guard let ratio = ratio else { return }

        // Adjust height to match ratio
        let newHeight = width / ratio
        if newHeight <= bounds.height {
            height = newHeight
        } else {
            // Adjust width instead
            height = bounds.height
            width = height * ratio
        }

        // Ensure within bounds
        x = max(0, min(x, bounds.width - width))
        y = max(0, min(y, bounds.height - height))
    }

    /// Create a crop rect that fills the image with given aspect ratio
    static func fill(imageSize: CGSize, aspectRatio: CGFloat?) -> CropRect {
        guard let ratio = aspectRatio else {
            return CropRect(x: 0, y: 0, width: imageSize.width, height: imageSize.height)
        }

        let imageRatio = imageSize.width / imageSize.height

        if imageRatio > ratio {
            // Image is wider, constrain by height
            let height = imageSize.height
            let width = height * ratio
            let x = (imageSize.width - width) / 2
            return CropRect(x: x, y: 0, width: width, height: height)
        } else {
            // Image is taller, constrain by width
            let width = imageSize.width
            let height = width / ratio
            let y = (imageSize.height - height) / 2
            return CropRect(x: 0, y: y, width: width, height: height)
        }
    }
}

/// Service for applying crops to JPEG images
actor CropService {
    /// Backup directory name
    private nonisolated let backupDirName = ".photo-triage-originals"

    /// Apply a 90-degree rotation to a JPEG image and save it to disk.
    /// The dimensions swap (portrait ↔ landscape). The original is backed up on first edit.
    func applyRotation(to url: URL, clockwise: Bool) async throws -> URL {
        guard url.isJPEG else { throw CropError.rawNotSupported }

        try backupOriginal(url: url)

        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw CropError.loadFailed
        }

        let rotated = try rotate90(cgImage, clockwise: clockwise)
        let nsImage = NSImage(cgImage: rotated, size: NSSize(width: rotated.width, height: rotated.height))
        try saveJPEG(image: nsImage, to: url)
        return url
    }

    /// Rotate a CGImage by exactly 90°, swapping width and height.
    private func rotate90(_ image: CGImage, clockwise: Bool) throws -> CGImage {
        let w = image.width, h = image.height
        // New canvas dimensions swap: width becomes h, height becomes w
        guard let ctx = CGContext(
            data: nil,
            width: h,
            height: w,
            bitsPerComponent: image.bitsPerComponent,
            bytesPerRow: 0,
            space: image.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: image.bitmapInfo.rawValue
        ) else { throw CropError.cropFailed }

        if clockwise {
            // CW visual: translate to (0, w) then rotate -π/2 in y-up context
            ctx.translateBy(x: 0, y: CGFloat(w))
            ctx.rotate(by: -.pi / 2)
        } else {
            // CCW visual: translate to (h, 0) then rotate +π/2 in y-up context
            ctx.translateBy(x: CGFloat(h), y: 0)
            ctx.rotate(by: .pi / 2)
        }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h)))

        guard let result = ctx.makeImage() else { throw CropError.cropFailed }
        return result
    }

    /// Apply crop (and optional fine rotation) to a JPEG image.
    /// The rotation is baked in before cropping — both operations are applied as a single step.
    /// - Parameters:
    ///   - url: Destination URL (always written here; original is backed up on first edit)
    ///   - cropRect: Crop region in image coordinates (pre-rotation)
    ///   - rotation: Fine rotation in degrees to apply before cropping (default 0)
    ///   - sourceURL: If provided, load pixels from here instead of `url` (e.g. the backup/original
    ///     when recropping a previously-cropped image). The backup of `url` is still created first.
    /// - Returns: URL of saved image (same as `url`; original is backed up)
    func applyCrop(to url: URL, cropRect: CropRect, rotation: Double = 0, sourceURL: URL? = nil) async throws -> URL {
        // Only JPEG supported for crop (RAW kept pristine)
        guard url.isJPEG else {
            throw CropError.rawNotSupported
        }

        // Backup the current file at `url` (no-op if backup already exists)
        try backupOriginal(url: url)

        // Load from sourceURL when recropping from original, otherwise from url.
        // CGImageSourceCreateImageAtIndex gives native pixel dimensions (no DPI scaling), but
        // ignores the EXIF orientation tag. We apply orientation first so that the crop rect
        // (drawn in display space by CropOverlay, which applies the same transform) aligns
        // correctly with the pixel data written to disk.
        let loadURL = sourceURL ?? url
        guard let source = CGImageSourceCreateWithURL(loadURL as CFURL, nil),
              let raw = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw CropError.loadFailed
        }
        let orientation = source.exifOrientation
        var cgImage = raw.applyingExifOrientation(orientation) ?? raw

        // Apply fine rotation first (keeps original canvas size, clips tiny corners)
        if abs(rotation) > 0.001 {
            cgImage = try rotateImage(cgImage, byDegrees: rotation)
        }

        // CGImage.cropping(to:) uses upper-left origin (matching JPEG file storage order),
        // so CropRect coordinates map directly — no Y-flip needed.
        let cropCGRect = cropRect.cgRect

        guard let croppedCGImage = cgImage.cropping(to: cropCGRect) else {
            throw CropError.cropFailed
        }

        let croppedNSImage = NSImage(cgImage: croppedCGImage, size: NSSize(
            width: croppedCGImage.width,
            height: croppedCGImage.height
        ))

        try saveJPEG(image: croppedNSImage, to: url)

        return url
    }

    /// Rotate a CGImage by the given degrees, keeping the original canvas dimensions.
    /// For small angles (horizon correction), the clipped corners are negligible.
    private func rotateImage(_ image: CGImage, byDegrees degrees: Double) throws -> CGImage {
        let radians = CGFloat(degrees * .pi / 180.0)
        let w = image.width
        let h = image.height

        guard let ctx = CGContext(
            data: nil,
            width: w,
            height: h,
            bitsPerComponent: image.bitsPerComponent,
            bytesPerRow: 0,
            space: image.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: image.bitmapInfo.rawValue
        ) else { throw CropError.cropFailed }

        // Rotate around the centre; CoreGraphics Y-axis is flipped so negate angle
        ctx.translateBy(x: CGFloat(w) / 2, y: CGFloat(h) / 2)
        ctx.rotate(by: -radians)
        ctx.translateBy(x: -CGFloat(w) / 2, y: -CGFloat(h) / 2)
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))

        guard let rotated = ctx.makeImage() else { throw CropError.cropFailed }
        return rotated
    }

    /// Restore original from backup
    func restoreOriginal(for url: URL) throws {
        let backupURL = backupURL(for: url)

        guard FileManager.default.fileExists(atPath: backupURL.path) else {
            throw CropError.noBackup
        }

        try FileManager.default.removeItem(at: url)
        try FileManager.default.copyItem(at: backupURL, to: url)
    }

    /// Check if backup exists
    func hasBackup(for url: URL) -> Bool {
        FileManager.default.fileExists(atPath: backupURL(for: url).path)
    }

    // MARK: - Private

    nonisolated func backupURL(for url: URL) -> URL {
        let folder = url.deletingLastPathComponent()
        let backupDir = folder.appendingPathComponent(backupDirName)
        return backupDir.appendingPathComponent(url.lastPathComponent)
    }

    private func backupOriginal(url: URL) throws {
        let backup = backupURL(for: url)
        let backupDir = backup.deletingLastPathComponent()

        // Create backup directory
        try FileManager.default.createDirectory(
            at: backupDir,
            withIntermediateDirectories: true
        )

        // Copy if not already backed up
        if !FileManager.default.fileExists(atPath: backup.path) {
            try FileManager.default.copyItem(at: url, to: backup)
        }
    }

    private func saveJPEG(image: NSImage, to url: URL) throws {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.9]) else {
            throw CropError.saveFailed
        }

        try jpegData.write(to: url)
    }
}

/// Crop operation errors
enum CropError: Error, LocalizedError {
    case rawNotSupported
    case loadFailed
    case cropFailed
    case saveFailed
    case noBackup

    var errorDescription: String? {
        switch self {
        case .rawNotSupported:
            return "Cropping is only supported for JPEG images. RAW files are kept pristine."
        case .loadFailed:
            return "Failed to load the image."
        case .cropFailed:
            return "Failed to apply the crop."
        case .saveFailed:
            return "Failed to save the cropped image."
        case .noBackup:
            return "No backup found for this image."
        }
    }
}
