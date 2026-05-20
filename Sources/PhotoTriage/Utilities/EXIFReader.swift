import Foundation
import ImageIO
import CoreGraphics

/// EXIF metadata extracted from an image
struct EXIFMetadata: Equatable, Sendable {
    var captureDate: Date?
    var focalLength: Double?
    var aperture: Double?
    var shutterSpeed: String?
    var iso: Int?
    var cameraModel: String?
    var lensMake: String?
    var lensModel: String?
    var imageWidth: Int?
    var imageHeight: Int?
    var orientation: Int?

    /// Human-readable aperture string (e.g., "f/2.8")
    var apertureString: String? {
        guard let aperture = aperture else { return nil }
        return String(format: "f/%.1f", aperture)
    }

    /// Human-readable focal length string (e.g., "50mm")
    var focalLengthString: String? {
        guard let focalLength = focalLength else { return nil }
        if focalLength == floor(focalLength) {
            return String(format: "%.0fmm", focalLength)
        }
        return String(format: "%.1fmm", focalLength)
    }

    /// Human-readable ISO string (e.g., "ISO 400")
    var isoString: String? {
        guard let iso = iso else { return nil }
        return "ISO \(iso)"
    }

    /// Summary string for overlay display
    var summaryString: String {
        var parts: [String] = []
        if let focal = focalLengthString { parts.append(focal) }
        if let ap = apertureString { parts.append(ap) }
        if let shutter = shutterSpeed { parts.append(shutter) }
        if let iso = isoString { parts.append(iso) }
        return parts.joined(separator: " • ")
    }

    /// Camera info string
    var cameraString: String? {
        cameraModel
    }

    /// Lens info string
    var lensString: String? {
        if let model = lensModel {
            return model
        }
        return lensMake
    }
}

/// Reads EXIF metadata from image files
enum EXIFReader {
    /// Read EXIF metadata from an image URL
    static func read(from url: URL) -> EXIFMetadata {
        var metadata = EXIFMetadata()

        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return metadata
        }

        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] else {
            return metadata
        }

        // Basic image properties
        metadata.imageWidth = properties[kCGImagePropertyPixelWidth as String] as? Int
        metadata.imageHeight = properties[kCGImagePropertyPixelHeight as String] as? Int
        metadata.orientation = properties[kCGImagePropertyOrientation as String] as? Int

        // EXIF dictionary
        if let exif = properties[kCGImagePropertyExifDictionary as String] as? [String: Any] {
            // Capture date
            if let dateString = exif[kCGImagePropertyExifDateTimeOriginal as String] as? String {
                metadata.captureDate = parseEXIFDate(dateString)
            }

            // Focal length
            metadata.focalLength = exif[kCGImagePropertyExifFocalLength as String] as? Double

            // Aperture (FNumber)
            metadata.aperture = exif[kCGImagePropertyExifFNumber as String] as? Double

            // Shutter speed (exposure time)
            if let exposureTime = exif[kCGImagePropertyExifExposureTime as String] as? Double {
                metadata.shutterSpeed = formatShutterSpeed(exposureTime)
            }

            // ISO
            if let isoArray = exif[kCGImagePropertyExifISOSpeedRatings as String] as? [Int],
               let iso = isoArray.first {
                metadata.iso = iso
            }

            // Lens model
            metadata.lensModel = exif[kCGImagePropertyExifLensModel as String] as? String
            metadata.lensMake = exif[kCGImagePropertyExifLensMake as String] as? String
        }

        // TIFF dictionary (camera info)
        if let tiff = properties[kCGImagePropertyTIFFDictionary as String] as? [String: Any] {
            if let make = tiff[kCGImagePropertyTIFFMake as String] as? String,
               let model = tiff[kCGImagePropertyTIFFModel as String] as? String {
                // Clean up model string (often includes make already)
                if model.lowercased().contains(make.lowercased()) {
                    metadata.cameraModel = model
                } else {
                    metadata.cameraModel = "\(make) \(model)"
                }
            } else if let model = tiff[kCGImagePropertyTIFFModel as String] as? String {
                metadata.cameraModel = model
            }
        }

        return metadata
    }

    /// Parse EXIF date string format: "YYYY:MM:DD HH:MM:SS"
    private static func parseEXIFDate(_ string: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.date(from: string)
    }

    /// Format shutter speed as fraction (e.g., "1/250")
    private static func formatShutterSpeed(_ seconds: Double) -> String {
        if seconds >= 1 {
            if seconds == floor(seconds) {
                return String(format: "%.0fs", seconds)
            }
            return String(format: "%.1fs", seconds)
        }

        let denominator = 1.0 / seconds
        if denominator >= 1 {
            return String(format: "1/%.0f", denominator)
        }
        return String(format: "%.2fs", seconds)
    }
}
