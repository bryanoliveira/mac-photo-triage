import Foundation

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
