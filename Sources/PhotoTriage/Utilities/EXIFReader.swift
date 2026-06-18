import Foundation
import ImageIO
import CoreGraphics

/// EXIF metadata extracted from an image
struct EXIFMetadata: Equatable, Sendable {
    // Camera & lens
    var cameraModel: String?
    var lensMake: String?
    var lensModel: String?

    // Exposure
    var focalLength: Double?
    var focalLength35mm: Double?
    var aperture: Double?
    var shutterSpeed: String?
    var iso: Int?
    var exposureCompensation: Double?
    var flash: Bool?

    // Image geometry
    var imageWidth: Int?
    var imageHeight: Int?
    var orientation: Int?

    // File info (populated from the URL at read time)
    var filename: String?
    var fileSize: Int64?

    // Date
    var captureDate: Date?

    // MARK: - Formatted strings

    var apertureString: String? {
        guard let a = aperture else { return nil }
        return String(format: "f/%.1f", a)
    }

    var focalLengthString: String? {
        guard let f = focalLength else { return nil }
        return f == floor(f) ? String(format: "%.0fmm", f) : String(format: "%.1fmm", f)
    }

    var isoString: String? {
        guard let iso else { return nil }
        return "ISO \(iso)"
    }

    var exposureCompensationString: String? {
        guard let ev = exposureCompensation, abs(ev) > 0.01 else { return nil }
        return String(format: "%+.1f EV", ev)
    }

    var flashString: String? {
        guard let f = flash else { return nil }
        return f ? "On" : "Off"
    }

    /// 35mm equivalent focal length, only shown when meaningfully different from actual.
    var focalLength35mmString: String? {
        guard let f35 = focalLength35mm,
              let fl = focalLength,
              abs(f35 - fl) > 1 else { return nil }
        return f35 == floor(f35) ? String(format: "%.0fmm equiv.", f35)
                                 : String(format: "%.1fmm equiv.", f35)
    }

    var resolutionString: String? {
        guard let w = imageWidth, let h = imageHeight, w > 0, h > 0 else { return nil }
        let mp = Double(w * h) / 1_000_000
        return "\(w) × \(h)  ·  \(String(format: "%.1f", mp)) MP"
    }

    var fileSizeString: String? {
        guard let size = fileSize else { return nil }
        if size >= 1_000_000 { return String(format: "%.1f MB", Double(size) / 1_000_000) }
        if size >= 1_000     { return String(format: "%.0f KB", Double(size) / 1_000) }
        return "\(size) B"
    }

    /// One-line exposure summary (focal • aperture • shutter • ISO).
    var summaryString: String {
        [focalLengthString, apertureString, shutterSpeed, isoString]
            .compactMap { $0 }
            .joined(separator: "  ·  ")
    }

    var cameraString: String? { cameraModel }

    var lensString: String? { lensModel ?? lensMake }

    /// True when the overlay has at least something useful to show.
    var hasAnyData: Bool {
        cameraModel != nil || !summaryString.isEmpty ||
        captureDate != nil || resolutionString != nil || fileSize != nil
    }
}

/// Reads EXIF metadata from image files
enum EXIFReader {
    static func read(from url: URL) -> EXIFMetadata {
        var m = EXIFMetadata()

        m.filename = url.lastPathComponent
        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
           let size = attrs[.size] as? Int64 {
            m.fileSize = size
        }

        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] else {
            return m
        }

        m.imageWidth  = props[kCGImagePropertyPixelWidth  as String] as? Int
        m.imageHeight = props[kCGImagePropertyPixelHeight as String] as? Int
        m.orientation = props[kCGImagePropertyOrientation as String] as? Int

        if let exif = props[kCGImagePropertyExifDictionary as String] as? [String: Any] {
            if let ds = exif[kCGImagePropertyExifDateTimeOriginal as String] as? String {
                m.captureDate = parseEXIFDate(ds)
            }
            m.focalLength   = exif[kCGImagePropertyExifFocalLength as String] as? Double
            m.aperture      = exif[kCGImagePropertyExifFNumber     as String] as? Double
            if let t = exif[kCGImagePropertyExifExposureTime as String] as? Double {
                m.shutterSpeed = formatShutterSpeed(t)
            }
            if let arr = exif[kCGImagePropertyExifISOSpeedRatings as String] as? [Int] {
                m.iso = arr.first
            }
            m.exposureCompensation = exif[kCGImagePropertyExifExposureBiasValue  as String] as? Double
            if let fv = exif[kCGImagePropertyExifFlash as String] as? Int {
                m.flash = (fv & 0x01) != 0
            }
            if let f35 = exif[kCGImagePropertyExifFocalLenIn35mmFilm as String] {
                m.focalLength35mm = (f35 as? Double) ?? (f35 as? Int).map(Double.init)
            }
            m.lensModel = exif[kCGImagePropertyExifLensModel as String] as? String
            m.lensMake  = exif[kCGImagePropertyExifLensMake  as String] as? String
        }

        if let tiff = props[kCGImagePropertyTIFFDictionary as String] as? [String: Any] {
            let make  = tiff[kCGImagePropertyTIFFMake  as String] as? String
            let model = tiff[kCGImagePropertyTIFFModel as String] as? String
            if let make, let model {
                m.cameraModel = model.lowercased().contains(make.lowercased()) ? model : "\(make) \(model)"
            } else {
                m.cameraModel = model
            }
        }

        return m
    }

    private static func parseEXIFDate(_ string: String) -> Date? {
        let f = DateFormatter()
        f.dateFormat = "yyyy:MM:dd HH:mm:ss"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.date(from: string)
    }

    private static func formatShutterSpeed(_ seconds: Double) -> String {
        if seconds >= 1 {
            return seconds == floor(seconds) ? String(format: "%.0fs", seconds)
                                             : String(format: "%.1fs", seconds)
        }
        let denom = 1.0 / seconds
        return denom >= 1 ? String(format: "1/%.0f", denom) : String(format: "%.4fs", seconds)
    }
}
