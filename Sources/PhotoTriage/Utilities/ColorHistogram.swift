import Foundation
import CoreGraphics
import ImageIO

enum ColorHistogram {
    static let buckets = 16
    static let channels = 3  // R, G, B
    static let dataSize = buckets * channels * MemoryLayout<Float32>.size  // 192 bytes

    struct Analysis {
        let histogram: Data
        let imageSize: CGSize
    }

    /// Compute color histogram and image dimensions from a URL using a small thumbnail.
    static func analyze(from url: URL) -> Analysis? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }

        // Read pixel dimensions without decoding (very fast)
        let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let pixelW = props?[kCGImagePropertyPixelWidth] as? Int ?? 0
        let pixelH = props?[kCGImagePropertyPixelHeight] as? Int ?? 0
        guard pixelW > 0, pixelH > 0 else { return nil }
        let imageSize = CGSize(width: pixelW, height: pixelH)

        // Decode a 64×64 thumbnail for histogram
        let opts: [CFString: Any] = [
            kCGImageSourceThumbnailMaxPixelSize: 64,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, opts as CFDictionary) else {
            return nil
        }

        let w = cgImage.width
        let h = cgImage.height
        guard w > 0, h > 0 else { return nil }

        var pixelData = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(
            data: &pixelData,
            width: w, height: h,
            bitsPerComponent: 8,
            bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))

        var hist = [Float32](repeating: 0, count: buckets * channels)
        let pixelCount = w * h
        for i in 0..<pixelCount {
            let base = i * 4
            let rBucket = min(buckets - 1, Int(pixelData[base])     * buckets / 256)
            let gBucket = min(buckets - 1, Int(pixelData[base + 1]) * buckets / 256)
            let bBucket = min(buckets - 1, Int(pixelData[base + 2]) * buckets / 256)
            hist[rBucket] += 1
            hist[buckets + gBucket] += 1
            hist[buckets * 2 + bBucket] += 1
        }

        let total = Float32(pixelCount)
        for i in 0..<hist.count { hist[i] /= total }

        let histogram = hist.withUnsafeBytes { Data($0) }
        return Analysis(histogram: histogram, imageSize: imageSize)
    }

    /// L1 distance between two normalized histograms, result in [0, 1].
    /// Max L1 per channel is 2.0, so max total across 3 channels is 6.0.
    static func distance(_ a: Data, _ b: Data) -> Double {
        guard a.count == dataSize, b.count == dataSize else { return 1.0 }
        let count = buckets * channels
        return a.withUnsafeBytes { aPtr in
            b.withUnsafeBytes { bPtr in
                let aF = aPtr.bindMemory(to: Float32.self)
                let bF = bPtr.bindMemory(to: Float32.self)
                var sum = 0.0
                for i in 0..<count {
                    sum += Double(abs(aF[i] - bF[i]))
                }
                return min(sum / (2.0 * Double(channels)), 1.0)
            }
        }
    }
}
