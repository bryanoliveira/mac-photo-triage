import AppKit
import CoreGraphics
import ImageIO

/// Analyzes an image URL and returns RGBA mask images marking clipped highlights and shadows.
/// Results are cached by URL. Heavy work runs on a background queue.
actor ClippingAnalyzer {
    static let shared = ClippingAnalyzer()

    struct ClippingMasks {
        let highlights: NSImage  // red pixels where channels >= highlightThreshold
        let shadows: NSImage     // blue pixels where channels <= shadowThreshold
    }

    private var cache: [URL: ClippingMasks] = [:]

    func masks(for url: URL) async -> ClippingMasks? {
        if let cached = cache[url] { return cached }

        let result: ClippingMasks? = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: Self.buildMasks(url: url))
            }
        }

        if let result { cache[url] = result }
        return result
    }

    func invalidate(url: URL) {
        cache.removeValue(forKey: url)
    }

    // MARK: - Background computation

    private static let highlightThreshold: UInt8 = 252
    private static let shadowThreshold: UInt8 = 3

    private static func buildMasks(url: URL) -> ClippingMasks? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }

        // Decode at reduced resolution — avoids loading a full 45MP RAW into memory
        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceThumbnailMaxPixelSize: 1024,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary) else {
            return nil
        }

        let w = cgImage.width, h = cgImage.height
        guard w > 0, h > 0 else { return nil }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)

        guard let ctx = CGContext(
            data: nil, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: w * 4,
            space: colorSpace, bitmapInfo: bitmapInfo.rawValue
        ) else { return nil }

        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let rawData = ctx.data else { return nil }

        let src = rawData.bindMemory(to: UInt8.self, capacity: w * h * 4)
        var hBuf = [UInt8](repeating: 0, count: w * h * 4)
        var sBuf = [UInt8](repeating: 0, count: w * h * 4)

        for i in 0..<(w * h) {
            let p = i * 4
            let r = src[p], g = src[p + 1], b = src[p + 2], a = src[p + 3]
            guard a > 0 else { continue }

            if r >= highlightThreshold && g >= highlightThreshold && b >= highlightThreshold {
                hBuf[p] = 255; hBuf[p + 3] = 255          // solid red
            } else if r <= shadowThreshold && g <= shadowThreshold && b <= shadowThreshold {
                sBuf[p + 2] = 255; sBuf[p + 3] = 255      // solid blue
            }
        }

        guard let hImg = makeCGImage(bytes: hBuf, width: w, height: h, colorSpace: colorSpace),
              let sImg = makeCGImage(bytes: sBuf, width: w, height: h, colorSpace: colorSpace) else {
            return nil
        }

        let size = NSSize(width: w, height: h)
        return ClippingMasks(
            highlights: NSImage(cgImage: hImg, size: size),
            shadows: NSImage(cgImage: sImg, size: size)
        )
    }

    private static func makeCGImage(bytes: [UInt8], width: Int, height: Int, colorSpace: CGColorSpace) -> CGImage? {
        let data = Data(bytes)
        guard let provider = CGDataProvider(data: data as CFData) else { return nil }
        return CGImage(
            width: width, height: height,
            bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil, shouldInterpolate: true, intent: .defaultIntent
        )
    }
}
