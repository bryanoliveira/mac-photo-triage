import Foundation
import CoreGraphics

/// 256-bin tone histogram (per RGB channel plus Rec.709 luminance) for the Edit sidebar.
/// Unrelated to `ColorHistogram`, which is a coarse 16-bucket signature used for similarity.
struct Histogram: Equatable {
    var red = [Int](repeating: 0, count: 256)
    var green = [Int](repeating: 0, count: 256)
    var blue = [Int](repeating: 0, count: 256)
    var luminance = [Int](repeating: 0, count: 256)
    var pixelCount = 0

    /// Fraction of pixels with any channel ≥ 252 (matches the clipping overlay)
    var highlightClipFraction: Double = 0
    /// Fraction of pixels with every channel ≤ 3
    var shadowClipFraction: Double = 0

    /// Compute from `image`, downsampling so the long edge is ≤ `maxDimension` (speed).
    static func compute(from image: CGImage, maxDimension: Int = 320) -> Histogram {
        let scale = min(1, Double(maxDimension) / Double(max(image.width, image.height)))
        let w = max(1, Int(Double(image.width) * scale))
        let h = max(1, Int(Double(image.height) * scale))

        var hist = Histogram()
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return hist }
        ctx.interpolationQuality = .medium
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let data = ctx.data else { return hist }
        let px = data.bindMemory(to: UInt8.self, capacity: w * h * 4)

        var highClipped = 0, lowClipped = 0
        for i in 0..<(w * h) {
            let p = i * 4
            let r = Int(px[p]), g = Int(px[p + 1]), b = Int(px[p + 2])
            hist.red[r] += 1
            hist.green[g] += 1
            hist.blue[b] += 1
            // Integer Rec.709 luma: (54 R + 183 G + 19 B) / 256
            hist.luminance[(54 * r + 183 * g + 19 * b) >> 8] += 1
            let hi = max(r, g, b)
            if hi >= Int(ClippingAnalyzer.highlightThreshold) { highClipped += 1 }
            else if hi <= Int(ClippingAnalyzer.shadowThreshold) { lowClipped += 1 }
        }
        hist.pixelCount = w * h
        hist.highlightClipFraction = Double(highClipped) / Double(w * h)
        hist.shadowClipFraction = Double(lowClipped) / Double(w * h)
        return hist
    }
}
