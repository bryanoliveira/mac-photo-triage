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

    // MARK: - Helpers

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
