import Foundation
import CoreGraphics
import AppKit

/// Perceptual hash (dHash) implementation for image similarity detection
/// Uses difference hash algorithm: 17x16 grayscale → 256-bit hash
enum DHash {
    /// Hash size constants
    static let hashWidth = 17   // One extra column for difference calculation
    static let hashHeight = 16
    static let hashBits = 256   // 16 * 16 bits

    /// Compute dHash for an image at the given URL
    static func compute(from url: URL) -> Data? {
        guard let image = NSImage(contentsOf: url) else {
            return nil
        }
        return compute(from: image)
    }

    /// Compute dHash from an NSImage
    static func compute(from image: NSImage) -> Data? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        return compute(from: cgImage)
    }

    /// Compute dHash from a CGImage
    static func compute(from cgImage: CGImage) -> Data {
        // Create grayscale context at hash dimensions
        let colorSpace = CGColorSpaceCreateDeviceGray()
        var pixels = [UInt8](repeating: 0, count: hashWidth * hashHeight)

        guard let context = CGContext(
            data: &pixels,
            width: hashWidth,
            height: hashHeight,
            bitsPerComponent: 8,
            bytesPerRow: hashWidth,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            return Data(repeating: 0, count: hashBits / 8)
        }

        // Draw image scaled to hash size
        context.interpolationQuality = .medium
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: hashWidth, height: hashHeight))

        // Compute difference hash
        // Compare each pixel to its right neighbor
        // 256 bits = 32 bytes
        var hashBytes = [UInt8](repeating: 0, count: hashBits / 8)
        var bitIndex = 0

        for y in 0..<hashHeight {
            for x in 0..<(hashWidth - 1) {
                let leftPixel = pixels[y * hashWidth + x]
                let rightPixel = pixels[y * hashWidth + x + 1]

                // Set bit if left pixel is brighter than right
                if leftPixel > rightPixel {
                    let byteIndex = bitIndex / 8
                    let bitPosition = 7 - (bitIndex % 8)
                    hashBytes[byteIndex] |= (1 << bitPosition)
                }
                bitIndex += 1
            }
        }

        return Data(hashBytes)
    }

    /// Calculate Hamming distance between two hashes
    /// Returns the number of differing bits (0-256)
    static func hammingDistance(_ hash1: Data, _ hash2: Data) -> Int {
        guard hash1.count == hash2.count else {
            return hashBits // Maximum distance if sizes don't match
        }

        var distance = 0
        for i in 0..<hash1.count {
            let xor = hash1[i] ^ hash2[i]
            distance += xor.nonzeroBitCount
        }
        return distance
    }

    /// Calculate normalized similarity score (0.0 = identical, 1.0 = completely different)
    static func normalizedDistance(_ hash1: Data, _ hash2: Data) -> Double {
        return Double(hammingDistance(hash1, hash2)) / Double(hashBits)
    }

    /// Check if two images are likely similar (threshold-based)
    /// A hamming distance of ~10% or less typically indicates similar images
    static func areSimilar(_ hash1: Data, _ hash2: Data, threshold: Int = 26) -> Bool {
        return hammingDistance(hash1, hash2) <= threshold
    }
}

extension UInt8 {
    /// Count of non-zero bits (popcount)
    var nonzeroBitCount: Int {
        var n = self
        var count = 0
        while n != 0 {
            count += 1
            n &= n - 1
        }
        return count
    }
}
