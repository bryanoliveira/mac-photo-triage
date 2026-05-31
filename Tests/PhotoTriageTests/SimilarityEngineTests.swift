import XCTest
@testable import PhotoTriage

@MainActor
final class SimilarityEngineTests: XCTestCase {

    var testDirectory: URL!
    var folder: ImageFolder!
    var engine: SimilarityEngine!

    override func setUp() async throws {
        testDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PhotoTriageTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: testDirectory, withIntermediateDirectories: true)

        folder = ImageFolder(folderURL: testDirectory)
        engine = SimilarityEngine()
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: testDirectory)
    }

    func testFindCandidatesExcludesAnchor() async throws {
        // Create test images with hashes
        let asset1 = createAssetWithHash(named: "image1.jpg", hash: Data(repeating: 0, count: 32))
        let asset2 = createAssetWithHash(named: "image2.jpg", hash: Data(repeating: 0, count: 32))
        let asset3 = createAssetWithHash(named: "image3.jpg", hash: Data(repeating: 0, count: 32))

        folder = ImageFolder(folderURL: testDirectory)
        await folder.scan()

        // Manually assign hashes
        folder.images.first { $0.stem == "image1" }?.dHash = asset1.dHash
        folder.images.first { $0.stem == "image2" }?.dHash = asset2.dHash
        folder.images.first { $0.stem == "image3" }?.dHash = asset3.dHash

        let anchor = folder.images.first { $0.stem == "image1" }!
        let candidates = engine.findCandidates(for: anchor, in: folder)

        XCTAssertEqual(candidates.count, 2)
        XCTAssertFalse(candidates.contains { $0.asset.stem == "image1" })
    }

    func testFindCandidatesExcludesTrashed() async throws {
        createTestFile(named: "image1.jpg")
        createTestFile(named: "image2.jpg")
        createTestFile(named: "trashed.jpg")

        folder = ImageFolder(folderURL: testDirectory)
        await folder.scan()

        // Set hashes
        for asset in folder.images {
            asset.dHash = Data(repeating: 0, count: 32)
        }

        // Mark one as trashed
        try folder.images.first { $0.stem == "trashed" }?.markTrashed()

        let anchor = folder.images.first { $0.stem == "image1" }!
        let candidates = engine.findCandidates(for: anchor, in: folder, excludeTrashed: true)

        XCTAssertEqual(candidates.count, 1)
        XCTAssertFalse(candidates.contains { $0.asset.stem == "trashed" })
    }

    func testCandidatesSortedBySimilarity() async throws {
        createTestFile(named: "anchor.jpg")
        createTestFile(named: "similar.jpg")
        createTestFile(named: "different.jpg")

        folder = ImageFolder(folderURL: testDirectory)
        await folder.scan()

        // Create hashes with different distances
        let anchorHash = Data(repeating: 0, count: 32)
        var similarHash = Data(repeating: 0, count: 32)
        similarHash[0] = 0b00000011  // 2 bits different
        let differentHash = Data(repeating: 0xFF, count: 32)  // All bits different

        folder.images.first { $0.stem == "anchor" }?.dHash = anchorHash
        folder.images.first { $0.stem == "similar" }?.dHash = similarHash
        folder.images.first { $0.stem == "different" }?.dHash = differentHash

        let anchor = folder.images.first { $0.stem == "anchor" }!
        let candidates = engine.findCandidates(for: anchor, in: folder)

        XCTAssertEqual(candidates.count, 2)
        XCTAssertEqual(candidates.first?.asset.stem, "similar")
        XCTAssertEqual(candidates.last?.asset.stem, "different")
    }

    func testBestCandidate() async throws {
        createTestFile(named: "anchor.jpg")
        createTestFile(named: "best.jpg")
        createTestFile(named: "worse.jpg")

        folder = ImageFolder(folderURL: testDirectory)
        await folder.scan()

        let anchorHash = Data(repeating: 0, count: 32)
        var bestHash = Data(repeating: 0, count: 32)
        bestHash[0] = 0b00000001  // 1 bit different
        var worseHash = Data(repeating: 0, count: 32)
        worseHash[0] = 0b11111111  // 8 bits different

        folder.images.first { $0.stem == "anchor" }?.dHash = anchorHash
        folder.images.first { $0.stem == "best" }?.dHash = bestHash
        folder.images.first { $0.stem == "worse" }?.dHash = worseHash

        let anchor = folder.images.first { $0.stem == "anchor" }!
        let best = engine.bestCandidate(for: anchor, in: folder)

        XCTAssertNotNil(best)
        XCTAssertEqual(best?.stem, "best")
    }

    func testHasAllHashes() async throws {
        createTestFile(named: "image1.jpg")
        createTestFile(named: "image2.jpg")

        folder = ImageFolder(folderURL: testDirectory)
        await folder.scan()

        XCTAssertFalse(engine.hasAllHashes(for: folder))

        // Add hashes
        for asset in folder.images {
            asset.dHash = Data(repeating: 0, count: 32)
        }

        XCTAssertTrue(engine.hasAllHashes(for: folder))
    }

    func testHashedCount() async throws {
        createTestFile(named: "image1.jpg")
        createTestFile(named: "image2.jpg")
        createTestFile(named: "image3.jpg")

        folder = ImageFolder(folderURL: testDirectory)
        await folder.scan()

        XCTAssertEqual(engine.hashedCount(for: folder), 0)

        folder.images.first?.dHash = Data(repeating: 0, count: 32)

        XCTAssertEqual(engine.hashedCount(for: folder), 1)
    }

    // MARK: - Histogram + Aspect Ratio Scoring

    func testHistogramImprovesSimilarImages() async throws {
        // Two images with the same dHash distance should rank higher if histograms also match
        createTestFile(named: "anchorH.jpg")
        createTestFile(named: "sameColor.jpg")
        createTestFile(named: "diffColor.jpg")

        folder = ImageFolder(folderURL: testDirectory)
        await folder.scan()

        let anchor    = folder.images.first { $0.stem == "anchorH" }!
        let sameColor = folder.images.first { $0.stem == "sameColor" }!
        let diffColor = folder.images.first { $0.stem == "diffColor" }!

        let hash = Data(repeating: 0b10101010, count: 32)
        anchor.dHash = hash
        sameColor.dHash = hash
        diffColor.dHash = hash

        let redHist  = makeHistogram(redWeight: 1.0, greenWeight: 0.0, blueWeight: 0.0)
        let blueHist = makeHistogram(redWeight: 0.0, greenWeight: 0.0, blueWeight: 1.0)
        anchor.colorHistogram = redHist
        sameColor.colorHistogram = redHist
        diffColor.colorHistogram = blueHist

        let candidates = engine.findCandidates(for: anchor, in: folder)
        XCTAssertEqual(candidates.count, 2)
        XCTAssertEqual(candidates.first?.asset.stem, "sameColor",
                       "sameColor should rank higher due to matching histogram")
    }

    func testAspectRatioDownranksPortraitVsLandscape() async throws {
        createTestFile(named: "anchorA.jpg")
        createTestFile(named: "landscapeC.jpg")
        createTestFile(named: "portraitC.jpg")

        folder = ImageFolder(folderURL: testDirectory)
        await folder.scan()

        let anchor    = folder.images.first { $0.stem == "anchorA" }!
        let landscape = folder.images.first { $0.stem == "landscapeC" }!
        let portrait  = folder.images.first { $0.stem == "portraitC" }!

        let hash = Data(repeating: 0, count: 32)
        anchor.dHash    = hash
        landscape.dHash = hash
        portrait.dHash  = hash

        anchor.imageSize    = CGSize(width: 3000, height: 2000)  // 3:2
        landscape.imageSize = CGSize(width: 6000, height: 4000)  // 3:2 (same ratio)
        portrait.imageSize  = CGSize(width: 2000, height: 3000)  // 2:3

        let candidates = engine.findCandidates(for: anchor, in: folder)
        XCTAssertEqual(candidates.count, 2)
        XCTAssertEqual(candidates.first?.asset.stem, "landscapeC",
                       "landscape (same ratio) should rank above portrait")
    }

    func testUnknownAspectDoesNotPenalize() async throws {
        // imageSize = nil should be treated as aspectDistance = 0 (no penalty)
        createTestFile(named: "anchorB.jpg")
        createTestFile(named: "knownSize.jpg")
        createTestFile(named: "unknownSize.jpg")

        folder = ImageFolder(folderURL: testDirectory)
        await folder.scan()

        let anchor      = folder.images.first { $0.stem == "anchorB" }!
        let known       = folder.images.first { $0.stem == "knownSize" }!
        let unknownSize = folder.images.first { $0.stem == "unknownSize" }!

        let hash = Data(repeating: 0, count: 32)
        anchor.dHash      = hash
        known.dHash       = hash
        unknownSize.dHash = hash

        anchor.imageSize = CGSize(width: 3000, height: 2000)
        known.imageSize  = CGSize(width: 3000, height: 2000)  // Same ratio → aspectDistance = 0
        // unknownSize.imageSize is nil → aspectDistance = 0

        let candidates = engine.findCandidates(for: anchor, in: folder)
        XCTAssertEqual(candidates.count, 2)
        if let first = candidates.first, let last = candidates.last {
            XCTAssertEqual(first.score, last.score, accuracy: 0.0001,
                           "nil imageSize and identical imageSize should score the same")
        }
    }

    func testScoreRangeIsNormalized() async throws {
        // Worst possible combination should score in [0, 1]
        createTestFile(named: "worstAnchor.jpg")
        createTestFile(named: "worstOther.jpg")

        folder = ImageFolder(folderURL: testDirectory)
        await folder.scan()

        let anchor = folder.images.first { $0.stem == "worstAnchor" }!
        let other  = folder.images.first { $0.stem == "worstOther" }!

        anchor.dHash = Data(repeating: 0x00, count: 32)
        other.dHash  = Data(repeating: 0xFF, count: 32)  // Max hash distance

        var histA = [Float32](repeating: 0, count: ColorHistogram.buckets * ColorHistogram.channels)
        var histB = [Float32](repeating: 0, count: ColorHistogram.buckets * ColorHistogram.channels)
        for c in 0..<ColorHistogram.channels {
            histA[c * ColorHistogram.buckets] = 1.0
            histB[c * ColorHistogram.buckets + ColorHistogram.buckets - 1] = 1.0
        }
        anchor.colorHistogram = histA.withUnsafeBytes { Data($0) }
        other.colorHistogram  = histB.withUnsafeBytes { Data($0) }

        anchor.imageSize = CGSize(width: 1000, height: 100)  // Very wide
        other.imageSize  = CGSize(width: 100, height: 1000)  // Very tall

        let candidates = engine.findCandidates(for: anchor, in: folder)
        XCTAssertEqual(candidates.count, 1)
        let score = candidates.first!.score
        XCTAssertGreaterThanOrEqual(score, 0.0)
        XCTAssertLessThanOrEqual(score, 1.0)
    }

    /// Regression: before the fix, findCandidates returned [] when no other image had a dHash,
    /// which meant triage showed "No candidate" until background hash computation finished.
    /// Now it always returns candidates, sorted by time when hashes are unavailable.
    func testFindCandidatesReturnsNonEmptyWhenHashesMissing() async throws {
        createTestFile(named: "solo.jpg")
        createTestFile(named: "nohash1.jpg")
        createTestFile(named: "nohash2.jpg")

        folder = ImageFolder(folderURL: testDirectory)
        await folder.scan()

        // No dHash set on any image — simulates early app state before computation finishes
        let anchor = folder.images.first { $0.stem == "solo" }!

        let candidates = engine.findCandidates(for: anchor, in: folder)
        XCTAssertEqual(candidates.count, 2, "Should return all non-anchor images even without hashes")
        candidates.forEach {
            XCTAssertEqual($0.hashDistance, 128, "Neutral hash distance used when hashes unavailable")
            XCTAssertNil($0.histogramDistance)
        }
    }

    // MARK: - Helpers

    private func makeHistogram(redWeight: Float32, greenWeight: Float32, blueWeight: Float32) -> Data {
        var hist = [Float32](repeating: 0, count: ColorHistogram.buckets * ColorHistogram.channels)
        // Put all weight in bucket 0 for the given channel
        hist[0] = redWeight
        hist[ColorHistogram.buckets] = greenWeight
        hist[ColorHistogram.buckets * 2] = blueWeight
        return hist.withUnsafeBytes { Data($0) }
    }

    private func createTestFile(named name: String) {
        let url = testDirectory.appendingPathComponent(name)
        FileManager.default.createFile(atPath: url.path, contents: Data(), attributes: nil)
    }

    private func createAssetWithHash(named name: String, hash: Data) -> ImageAsset {
        let url = testDirectory.appendingPathComponent(name)
        FileManager.default.createFile(atPath: url.path, contents: Data(), attributes: nil)
        let asset = ImageAsset(jpegURL: url)
        asset.dHash = hash
        return asset
    }
}
