import Foundation
import AppKit
import CoreImage
import CoreGraphics

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
    private let backupDirName = ".photo-triage-originals"

    /// Apply crop to a JPEG image
    /// - Parameters:
    ///   - url: Image URL
    ///   - cropRect: Crop region in image coordinates
    /// - Returns: URL of cropped image (same as input, original backed up)
    func applyCrop(to url: URL, cropRect: CropRect) async throws -> URL {
        // Only JPEG supported for crop (RAW kept pristine)
        guard url.isJPEG else {
            throw CropError.rawNotSupported
        }

        // Backup original
        try backupOriginal(url: url)

        // Load image
        guard let image = NSImage(contentsOf: url) else {
            throw CropError.loadFailed
        }

        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw CropError.loadFailed
        }

        // Apply crop
        let cropCGRect = CGRect(
            x: cropRect.x,
            y: CGFloat(cgImage.height) - cropRect.y - cropRect.height,  // Flip Y
            width: cropRect.width,
            height: cropRect.height
        )

        guard let croppedCGImage = cgImage.cropping(to: cropCGRect) else {
            throw CropError.cropFailed
        }

        // Save cropped image
        let croppedNSImage = NSImage(cgImage: croppedCGImage, size: NSSize(
            width: croppedCGImage.width,
            height: croppedCGImage.height
        ))

        try saveJPEG(image: croppedNSImage, to: url)

        return url
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

    private func backupURL(for url: URL) -> URL {
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
