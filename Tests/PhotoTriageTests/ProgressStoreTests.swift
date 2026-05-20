import XCTest
@testable import PhotoTriage

final class ProgressStoreTests: XCTestCase {

    var testDirectory: URL!
    var store: ProgressStore!

    override func setUp() async throws {
        testDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PhotoTriageTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: testDirectory, withIntermediateDirectories: true)

        store = try await ProgressStore(folderURL: testDirectory)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: testDirectory)
    }

    func testInitialProgress() async throws {
        let progress = try await store.loadProgress()
        XCTAssertNil(progress)
    }

    func testSaveTriageProgress() async throws {
        try await store.saveTriageProgress(anchorIndex: 5, imagePath: "/test/image.jpg")

        let progress = try await store.loadProgress()

        XCTAssertNotNil(progress)
        XCTAssertEqual(progress?.lastTriageIndex, 5)
        XCTAssertEqual(progress?.lastView, ViewType.triage.rawValue)
        XCTAssertEqual(progress?.lastImagePath, "/test/image.jpg")
    }

    func testSavePreviewProgress() async throws {
        try await store.savePreviewProgress(imageIndex: 10, imagePath: "/test/preview.jpg")

        let progress = try await store.loadProgress()

        XCTAssertNotNil(progress)
        XCTAssertEqual(progress?.lastPreviewIndex, 10)
        XCTAssertEqual(progress?.lastView, ViewType.preview.rawValue)
    }

    func testSaveGalleryProgress() async throws {
        try await store.saveGalleryProgress(scrollPosition: 0.75)

        let progress = try await store.loadProgress()

        XCTAssertNotNil(progress)
        XCTAssertEqual(progress?.lastGalleryScroll, 0.75)
        XCTAssertEqual(progress?.lastView, ViewType.gallery.rawValue)
    }

    func testSaveCurrentView() async throws {
        try await store.saveCurrentView(.preview)

        let progress = try await store.loadProgress()

        XCTAssertEqual(progress?.lastView, ViewType.preview.rawValue)
    }

    func testClearProgress() async throws {
        try await store.saveTriageProgress(anchorIndex: 5, imagePath: nil)

        var progress = try await store.loadProgress()
        XCTAssertNotNil(progress)

        try await store.clearProgress()

        progress = try await store.loadProgress()
        XCTAssertNil(progress)
    }

    func testProgressUpdates() async throws {
        try await store.saveTriageProgress(anchorIndex: 5, imagePath: nil)
        try await store.saveTriageProgress(anchorIndex: 10, imagePath: nil)

        let progress = try await store.loadProgress()

        XCTAssertEqual(progress?.lastTriageIndex, 10)
    }

    func testHasProgress() async throws {
        let emptyProgress = ProgressRecord(
            folderPath: testDirectory.path,
            lastTriageIndex: nil,
            lastPreviewIndex: nil,
            lastGalleryScroll: nil,
            lastView: nil,
            lastImagePath: nil,
            updatedAt: Date()
        )

        XCTAssertFalse(emptyProgress.hasProgress)

        let withProgress = ProgressRecord(
            folderPath: testDirectory.path,
            lastTriageIndex: 5,
            lastPreviewIndex: nil,
            lastGalleryScroll: nil,
            lastView: "triage",
            lastImagePath: nil,
            updatedAt: Date()
        )

        XCTAssertTrue(withProgress.hasProgress)
    }

    func testResumeDescription() {
        let progress = ProgressRecord(
            folderPath: testDirectory.path,
            lastTriageIndex: 5,
            lastPreviewIndex: nil,
            lastGalleryScroll: nil,
            lastView: "triage",
            lastImagePath: "/test/IMG_1234.jpg",
            updatedAt: Date()
        )

        let description = progress.resumeDescription

        XCTAssertTrue(description.contains("triage"))
        XCTAssertTrue(description.contains("6")) // index + 1
        XCTAssertTrue(description.contains("IMG_1234.jpg"))
    }
}
