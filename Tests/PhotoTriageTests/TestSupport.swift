import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// Helpers shared by tests that need real image files on disk.
enum TestImages {
    struct WriteError: Error {}

    /// Write a solid-colour JPEG, optionally with an EXIF capture date and orientation tag.
    @discardableResult
    static func makeJPEG(at url: URL, width: Int = 64, height: Int = 48,
                         gray: CGFloat = 0.5, captureDate: String? = nil, orientation: Int? = nil) throws -> URL {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
            throw WriteError()
        }
        ctx.setFillColor(CGColor(red: gray, green: gray, blue: gray, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        // A distinctive corner so edits/rotations are detectable
        ctx.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: height - 8, width: 8, height: 8))
        guard let image = ctx.makeImage(),
              let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw WriteError()
        }
        var props: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 0.9]
        if let captureDate {
            props[kCGImagePropertyExifDictionary] = [kCGImagePropertyExifDateTimeOriginal: captureDate]
        }
        if let orientation {
            props[kCGImagePropertyOrientation] = orientation
        }
        CGImageDestinationAddImage(dest, image, props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw WriteError() }
        return url
    }

    /// Create a fresh temporary directory.
    static func makeTempDirectory(_ name: String = "PhotoTriageTests") throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
