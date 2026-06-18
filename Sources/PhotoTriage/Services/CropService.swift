import Foundation
import AppKit
import CoreImage
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

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

/// Saved edit parameters persisted alongside the original backup so that re-entering
/// Edit mode can restore the exact crop rect, horizon rotation, and tone adjustments.
struct CropMetadata: Codable {
    let cropX: CGFloat
    let cropY: CGFloat
    let cropWidth: CGFloat
    let cropHeight: CGFloat
    let rotation: Double
    let adjustments: ImageAdjustments?  // nil in sidecars written before adjustments were added
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
              let raw = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw CropError.loadFailed
        }

        // CGImageSourceCreateImageAtIndex ignores the EXIF orientation tag, so camera files that
        // store a rotation in metadata (rather than baked-upright pixels) would otherwise rotate
        // from the wrong starting orientation. Bake the display orientation in first; writeJPEG
        // then saves with orientation reset to Up.
        let cgImage = raw.applyingExifOrientation(source.exifOrientation) ?? raw

        let rotated = try rotate90(cgImage, clockwise: clockwise)
        try writeJPEG(rotated, to: url, metadataFrom: backupURL(for: url),
                      editNote: "Rotated 90° \(clockwise ? "clockwise" : "counter-clockwise")")
        try? FileManager.default.removeItem(at: sidecarURL(for: url))
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

    /// Apply crop, fine rotation, and tone adjustments to a JPEG image in a single pass.
    /// Pipeline: EXIF orientation → tone adjustments → fine rotation → crop.
    /// - Parameters:
    ///   - url: Destination URL (always written here; original is backed up on first edit)
    ///   - cropRect: Crop region in image coordinates (display space after EXIF orientation)
    ///   - rotation: Fine rotation in degrees to apply before cropping (default 0)
    ///   - adjustments: Tone adjustments baked via CoreImage (default = identity)
    ///   - sourceURL: If provided, load pixels from here instead of `url` (e.g. the backup/original
    ///     when re-editing a previously-edited image). The backup of `url` is still created first.
    /// - Returns: URL of saved image (same as `url`; original is backed up)
    func applyCrop(to url: URL, cropRect: CropRect, rotation: Double = 0,
                   adjustments: ImageAdjustments = .init(), sourceURL: URL? = nil) async throws -> URL {
        // Only JPEG supported (RAW kept pristine)
        guard url.isJPEG else {
            throw CropError.rawNotSupported
        }

        // Backup the current file at `url` (no-op if backup already exists)
        try backupOriginal(url: url)

        // Load from sourceURL when re-editing from original, otherwise from url.
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

        // Apply tone adjustments via CoreImage (before geometric operations)
        if !adjustments.isIdentity {
            let ciImage = CIImage(cgImage: cgImage)
            let adjusted = adjustments.applyingCI(to: ciImage)
            let ciContext = CIContext(options: [.useSoftwareRenderer: false])
            if let rendered = ciContext.createCGImage(adjusted, from: adjusted.extent) {
                cgImage = rendered
            }
        }

        // Apply fine rotation (keeps original canvas size, clips tiny corners)
        if abs(rotation) > 0.001 {
            cgImage = try rotateImage(cgImage, byDegrees: rotation)
        }

        // CGImage.cropping(to:) uses upper-left origin (matching JPEG file storage order),
        // so CropRect coordinates map directly — no Y-flip needed.
        guard let croppedCGImage = cgImage.cropping(to: cropRect.cgRect) else {
            throw CropError.cropFailed
        }

        try writeJPEG(croppedCGImage, to: url, metadataFrom: backupURL(for: url),
                      editNote: editNote(cropRect: cropRect, rotation: rotation, adjustments: adjustments))

        let meta = CropMetadata(cropX: cropRect.x, cropY: cropRect.y,
                                cropWidth: cropRect.width, cropHeight: cropRect.height,
                                rotation: rotation, adjustments: adjustments)
        if let data = try? JSONEncoder().encode(meta) {
            try? data.write(to: sidecarURL(for: url))
        }

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
        try? FileManager.default.removeItem(at: sidecarURL(for: url))
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

    nonisolated func sidecarURL(for url: URL) -> URL {
        backupURL(for: url).appendingPathExtension("json")
    }

    /// Read saved crop metadata for `url`, or nil if none exists.
    nonisolated func cropMetadata(for url: URL) -> CropMetadata? {
        guard let data = try? Data(contentsOf: sidecarURL(for: url)) else { return nil }
        return try? JSONDecoder().decode(CropMetadata.self, from: data)
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

    /// Write `image` as JPEG to `url`, carrying the EXIF/TIFF/GPS metadata from `metadataFrom`
    /// (the pristine original) so camera/lens/exposure/capture info survives the edit.
    ///
    /// The edit bakes display-upright, cropped/rotated pixels, so the saved file's orientation is
    /// reset to `.up` to prevent viewers from re-applying the original tag. The TIFF DateTime
    /// (modify time) is bumped to now and the editor stamps `Software`/`UserComment`, while the
    /// original capture date (`DateTimeOriginal`/`DateTimeDigitized`) is left untouched. After the
    /// file is written, the original's filesystem creation date is restored from the backup so
    /// Finder and photo importers keep showing when the shot was taken; the filesystem modification
    /// date is left at "now" to reflect that the file was edited.
    private func writeJPEG(_ image: CGImage, to url: URL, metadataFrom metadataURL: URL?,
                           editNote: String?) throws {
        // Start from the original's full property set (EXIF, TIFF, GPS, IPTC, …) when available.
        var props: [CFString: Any] = [:]
        if let metadataURL,
           let src = CGImageSourceCreateWithURL(metadataURL as CFURL, nil),
           let original = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] {
            props = original
        }

        // Encode quality and orientation. Pixels are already display-upright + cropped, so the
        // stored dimensions and orientation must reflect the new image, not the original.
        props[kCGImageDestinationLossyCompressionQuality] = 0.9
        props[kCGImagePropertyOrientation] = CGImagePropertyOrientation.up.rawValue
        props[kCGImagePropertyPixelWidth] = image.width
        props[kCGImagePropertyPixelHeight] = image.height

        let now = exifDateString(Date())

        // TIFF: orientation/dimensions mirror the top-level keys; DateTime tracks modify time.
        var tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
        tiff[kCGImagePropertyTIFFOrientation] = CGImagePropertyOrientation.up.rawValue
        tiff[kCGImagePropertyTIFFDateTime] = now
        tiff[kCGImagePropertyTIFFSoftware] = Self.editorSignature
        props[kCGImagePropertyTIFFDictionary] = tiff

        // EXIF: keep original capture timestamps; record the edit in UserComment.
        var exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        exif[kCGImagePropertyExifPixelXDimension] = image.width
        exif[kCGImagePropertyExifPixelYDimension] = image.height
        if let editNote {
            exif[kCGImagePropertyExifUserComment] = "Edited with \(Self.editorSignature): \(editNote)"
        }
        props[kCGImagePropertyExifDictionary] = exif

        guard let dest = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.jpeg.identifier as CFString, 1, nil
        ) else {
            throw CropError.saveFailed
        }
        CGImageDestinationAddImage(dest, image, props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else {
            throw CropError.saveFailed
        }

        // Rewriting the file in place stamps it with the current filesystem creation date, which is
        // what Finder's "Created" column (and most photo importers) surface — not the EXIF capture
        // date. Restore the original's creation date from the pristine backup so an edited photo
        // keeps showing when it was actually taken. The modification date is deliberately left at
        // "now": the file genuinely changed, and the edit itself is recorded in TIFF Software /
        // EXIF UserComment.
        if let metadataURL,
           let originalAttrs = try? FileManager.default.attributesOfItem(atPath: metadataURL.path),
           let created = originalAttrs[.creationDate] as? Date {
            try? FileManager.default.setAttributes([.creationDate: created], ofItemAtPath: url.path)
        }
    }

    /// Editor name stamped into TIFF Software / EXIF UserComment.
    private static let editorSignature = "Photo Triage"

    /// Format a date as an EXIF/TIFF datetime string ("yyyy:MM:dd HH:mm:ss").
    private nonisolated func exifDateString(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy:MM:dd HH:mm:ss"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: date)
    }

    /// Build a human-readable summary of a crop edit for the UserComment tag.
    private nonisolated func editNote(cropRect: CropRect, rotation: Double,
                                      adjustments: ImageAdjustments) -> String {
        var parts = ["cropped to \(Int(cropRect.width.rounded()))×\(Int(cropRect.height.rounded()))"]
        if abs(rotation) > 0.001 {
            parts.append(String(format: "rotated %.2f°", rotation))
        }
        if !adjustments.isIdentity {
            parts.append("tone adjustments applied")
        }
        return parts.joined(separator: ", ")
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
