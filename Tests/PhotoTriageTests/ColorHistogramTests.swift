import XCTest
@testable import PhotoTriage

final class ColorHistogramTests: XCTestCase {

    func testDataSize() {
        // 16 buckets × 3 channels × 4 bytes per Float32
        XCTAssertEqual(ColorHistogram.dataSize, 192)
    }

    func testDistanceIdentical() {
        // Same data → distance 0
        let data = Data(repeating: 0, count: ColorHistogram.dataSize)
        XCTAssertEqual(ColorHistogram.distance(data, data), 0.0, accuracy: 0.001)
    }

    func testDistanceMaximal() {
        // All weight in first bucket for A, all in last bucket for B → max distance
        var histA = [Float32](repeating: 0, count: ColorHistogram.buckets * ColorHistogram.channels)
        var histB = [Float32](repeating: 0, count: ColorHistogram.buckets * ColorHistogram.channels)
        // Channel 0: A has all weight in bucket 0, B has all weight in bucket 15
        histA[0] = 1.0
        histB[ColorHistogram.buckets - 1] = 1.0
        // Channels 1 and 2: identical (zero everywhere) so no contribution
        let dataA = histA.withUnsafeBytes { Data($0) }
        let dataB = histB.withUnsafeBytes { Data($0) }

        // L1 for channel 0 = |1.0 - 0| + |0 - 1.0| = 2.0 → max per channel
        // Normalized by 2*channels=6 → 2.0/6.0 ≈ 0.333
        let dist = ColorHistogram.distance(dataA, dataB)
        XCTAssertEqual(dist, 2.0 / 6.0, accuracy: 0.001)
    }

    func testDistanceAllChannelsMax() {
        // All three channels maximally different
        var histA = [Float32](repeating: 0, count: ColorHistogram.buckets * ColorHistogram.channels)
        var histB = [Float32](repeating: 0, count: ColorHistogram.buckets * ColorHistogram.channels)
        for c in 0..<ColorHistogram.channels {
            histA[c * ColorHistogram.buckets] = 1.0
            histB[c * ColorHistogram.buckets + ColorHistogram.buckets - 1] = 1.0
        }
        let dataA = histA.withUnsafeBytes { Data($0) }
        let dataB = histB.withUnsafeBytes { Data($0) }

        // Normalized: 6.0 / 6.0 = 1.0
        XCTAssertEqual(ColorHistogram.distance(dataA, dataB), 1.0, accuracy: 0.001)
    }

    func testDistanceWrongSize() {
        // Mismatched size → returns 1.0 (max distance, safe fallback)
        let a = Data(count: 10)
        let b = Data(count: 20)
        XCTAssertEqual(ColorHistogram.distance(a, b), 1.0)
    }

    func testDistanceSymmetric() {
        var histA = [Float32](repeating: 0, count: ColorHistogram.buckets * ColorHistogram.channels)
        var histB = [Float32](repeating: 0, count: ColorHistogram.buckets * ColorHistogram.channels)
        histA[0] = 0.6; histA[1] = 0.4
        histB[2] = 0.5; histB[3] = 0.5
        let dataA = histA.withUnsafeBytes { Data($0) }
        let dataB = histB.withUnsafeBytes { Data($0) }
        XCTAssertEqual(ColorHistogram.distance(dataA, dataB),
                       ColorHistogram.distance(dataB, dataA),
                       accuracy: 0.0001)
    }
}
