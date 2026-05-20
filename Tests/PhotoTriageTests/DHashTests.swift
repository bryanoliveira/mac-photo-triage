import XCTest
@testable import PhotoTriage

final class DHashTests: XCTestCase {

    func testHashComputation() {
        // Test that hash computation produces consistent results
        // Create a simple test image
        let image1 = createTestImage(width: 100, height: 100, color: .red)
        let image2 = createTestImage(width: 100, height: 100, color: .red)
        let image3 = createTestImage(width: 100, height: 100, color: .blue)

        let hash1 = DHash.compute(from: image1)
        let hash2 = DHash.compute(from: image2)
        let hash3 = DHash.compute(from: image3)

        // Same images should have identical hashes
        XCTAssertEqual(hash1, hash2)

        // Different images should have different hashes (usually)
        // Note: Solid color images may have similar hashes
        XCTAssertNotNil(hash1)
        XCTAssertNotNil(hash3)
    }

    func testHammingDistance() {
        // Test hamming distance calculation
        let data1 = Data([0b11110000, 0b10101010])
        let data2 = Data([0b11110000, 0b10101010])
        let data3 = Data([0b00001111, 0b01010101])

        // Identical data should have distance 0
        XCTAssertEqual(DHash.hammingDistance(data1, data2), 0)

        // Completely inverted should have max distance
        XCTAssertEqual(DHash.hammingDistance(data1, data3), 16)
    }

    func testNormalizedDistance() {
        // Test normalized distance (0.0 to 1.0)
        let hash1 = Data(repeating: 0, count: 32)
        let hash2 = Data(repeating: 0xFF, count: 32)

        let distance = DHash.normalizedDistance(hash1, hash2)

        // All bits different = 1.0
        XCTAssertEqual(distance, 1.0, accuracy: 0.001)

        // Same hash = 0.0
        let sameDistance = DHash.normalizedDistance(hash1, hash1)
        XCTAssertEqual(sameDistance, 0.0, accuracy: 0.001)
    }

    func testAreSimilar() {
        let hash1 = Data(repeating: 0, count: 32)
        var hash2 = Data(repeating: 0, count: 32)

        // Flip just a few bits
        hash2[0] = 0b00000111  // 3 bits different

        XCTAssertTrue(DHash.areSimilar(hash1, hash2, threshold: 10))
        XCTAssertFalse(DHash.areSimilar(hash1, hash2, threshold: 2))
    }

    func testHashSize() {
        let image = createTestImage(width: 200, height: 200, color: .green)
        let hash = DHash.compute(from: image)

        // Hash should be 256 bits = 32 bytes
        XCTAssertEqual(hash?.count, 32)
    }

    // MARK: - Helpers

    private func createTestImage(width: Int, height: Int, color: NSColor) -> NSImage {
        let image = NSImage(size: NSSize(width: width, height: height))
        image.lockFocus()
        color.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        image.unlockFocus()
        return image
    }
}
