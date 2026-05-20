import XCTest
@testable import PhotoTriage

@MainActor
final class ImageFolderTests: XCTestCase {

    var testDirectory: URL!

    override func setUp() async throws {
        // Create temporary test directory
        testDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PhotoTriageTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: testDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        // Clean up test directory
        try? FileManager.default.removeItem(at: testDirectory)
    }

    func testEmptyFolder() async {
        let folder = ImageFolder(folderURL: testDirectory)
        await folder.scan()

        XCTAssertEqual(folder.images.count, 0)
        XCTAssertEqual(folder.filteredImages.count, 0)
    }

    func testScanJPEGFiles() async throws {
        // Create test JPEG files
        createTestFile(named: "image1.jpg")
        createTestFile(named: "image2.jpeg")
        createTestFile(named: "image3.JPG")

        let folder = ImageFolder(folderURL: testDirectory)
        await folder.scan()

        XCTAssertEqual(folder.images.count, 3)
    }

    func testScanRAWFiles() async throws {
        // Create test RAW files
        createTestFile(named: "image1.cr2")
        createTestFile(named: "image2.nef")
        createTestFile(named: "image3.arw")
        createTestFile(named: "image4.dng")

        let folder = ImageFolder(folderURL: testDirectory)
        await folder.scan()

        XCTAssertEqual(folder.images.count, 4)
    }

    func testRAWJPEGPairing() async throws {
        // Create paired RAW+JPEG
        createTestFile(named: "IMG_1234.jpg")
        createTestFile(named: "IMG_1234.cr2")
        // Create standalone files
        createTestFile(named: "IMG_5678.jpg")
        createTestFile(named: "IMG_9012.nef")

        let folder = ImageFolder(folderURL: testDirectory)
        await folder.scan()

        // Should have 3 assets (one pair + two singles)
        XCTAssertEqual(folder.images.count, 3)

        // Find the pair
        let pair = folder.images.first { $0.isPair }
        XCTAssertNotNil(pair)
        XCTAssertEqual(pair?.stem, "IMG_1234")
        XCTAssertNotNil(pair?.jpegURL)
        XCTAssertNotNil(pair?.rawURL)

        // Pair should display JPEG
        XCTAssertTrue(pair?.displayURL.isJPEG ?? false)
    }

    func testIgnoresHiddenFiles() async throws {
        createTestFile(named: ".hidden.jpg")
        createTestFile(named: "visible.jpg")

        let folder = ImageFolder(folderURL: testDirectory)
        await folder.scan()

        XCTAssertEqual(folder.images.count, 1)
        XCTAssertEqual(folder.images.first?.stem, "visible")
    }

    func testIgnoresUnsupportedFormats() async throws {
        createTestFile(named: "image.jpg")
        createTestFile(named: "document.pdf")
        createTestFile(named: "video.mp4")
        createTestFile(named: "text.txt")

        let folder = ImageFolder(folderURL: testDirectory)
        await folder.scan()

        XCTAssertEqual(folder.images.count, 1)
    }

    func testFilterByState() async throws {
        createTestFile(named: "kept.jpg")
        createTestFile(named: "trashed.jpg")
        createTestFile(named: "unreviewed.jpg")

        let folder = ImageFolder(folderURL: testDirectory)
        await folder.scan()

        // Mark states
        let keptAsset = folder.images.first { $0.stem == "kept" }
        let trashedAsset = folder.images.first { $0.stem == "trashed" }

        try keptAsset?.markKept()
        try trashedAsset?.markTrashed()

        // Test filters
        folder.filter = .all
        XCTAssertEqual(folder.filteredImages.count, 3)

        folder.filter = .kept
        XCTAssertEqual(folder.filteredImages.count, 1)
        XCTAssertEqual(folder.filteredImages.first?.stem, "kept")

        folder.filter = .trashed
        XCTAssertEqual(folder.filteredImages.count, 1)
        XCTAssertEqual(folder.filteredImages.first?.stem, "trashed")

        folder.filter = .unreviewed
        XCTAssertEqual(folder.filteredImages.count, 1)
        XCTAssertEqual(folder.filteredImages.first?.stem, "unreviewed")
    }

    func testStatistics() async throws {
        createTestFile(named: "kept.jpg")
        createTestFile(named: "trashed.jpg")
        createTestFile(named: "favorite.jpg")
        createTestFile(named: "unreviewed.jpg")

        let folder = ImageFolder(folderURL: testDirectory)
        await folder.scan()

        // Mark states
        try folder.images.first { $0.stem == "kept" }?.markKept()
        try folder.images.first { $0.stem == "trashed" }?.markTrashed()
        let favoriteAsset = folder.images.first { $0.stem == "favorite" }
        try favoriteAsset?.toggleFavorite()

        let stats = folder.statistics

        XCTAssertEqual(stats.total, 4)
        XCTAssertEqual(stats.kept, 1)
        XCTAssertEqual(stats.trashed, 1)
        XCTAssertEqual(stats.favorites, 1)
        XCTAssertEqual(stats.reviewed, 2) // kept + trashed
        XCTAssertEqual(stats.unreviewed, 2)
    }

    func testTriageableImages() async throws {
        createTestFile(named: "kept.jpg")
        createTestFile(named: "trashed.jpg")
        createTestFile(named: "unreviewed1.jpg")
        createTestFile(named: "unreviewed2.jpg")

        let folder = ImageFolder(folderURL: testDirectory)
        await folder.scan()

        try folder.images.first { $0.stem == "kept" }?.markKept()
        try folder.images.first { $0.stem == "trashed" }?.markTrashed()

        let triageable = folder.triageableImages

        XCTAssertEqual(triageable.count, 2)
        XCTAssertTrue(triageable.allSatisfy { !$0.isReviewed && !$0.isTrashed })
    }

    // MARK: - Helpers

    private func createTestFile(named name: String) {
        let url = testDirectory.appendingPathComponent(name)
        FileManager.default.createFile(atPath: url.path, contents: Data(), attributes: nil)
    }
}
