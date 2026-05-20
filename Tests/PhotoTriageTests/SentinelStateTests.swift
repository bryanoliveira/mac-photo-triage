import XCTest
@testable import PhotoTriage

final class SentinelStateTests: XCTestCase {

    var testDirectory: URL!
    var testImageURL: URL!

    override func setUp() {
        super.setUp()
        // Create temporary test directory
        testDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PhotoTriageTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: testDirectory, withIntermediateDirectories: true)

        // Create a dummy test image file
        testImageURL = testDirectory.appendingPathComponent("test_image.jpg")
        FileManager.default.createFile(atPath: testImageURL.path, contents: Data(), attributes: nil)
    }

    override func tearDown() {
        // Clean up test directory
        try? FileManager.default.removeItem(at: testDirectory)
        super.tearDown()
    }

    func testInitialState() {
        let state = SentinelState(for: testImageURL)

        XCTAssertFalse(state.isKeep)
        XCTAssertFalse(state.isTrash)
        XCTAssertFalse(state.isFavorite)
        XCTAssertFalse(state.isReviewed)
    }

    func testSetKeep() throws {
        var state = SentinelState(for: testImageURL)

        try state.set(.keep, value: true)

        XCTAssertTrue(state.isKeep)
        XCTAssertTrue(FileManager.default.fileExists(atPath: state.sentinelURL(for: .keep).path))
    }

    func testSetTrash() throws {
        var state = SentinelState(for: testImageURL)

        try state.set(.trash, value: true)

        XCTAssertTrue(state.isTrash)
        XCTAssertTrue(FileManager.default.fileExists(atPath: state.sentinelURL(for: .trash).path))
    }

    func testSetFavorite() throws {
        var state = SentinelState(for: testImageURL)

        try state.set(.favorite, value: true)

        XCTAssertTrue(state.isFavorite)
        XCTAssertTrue(FileManager.default.fileExists(atPath: state.sentinelURL(for: .favorite).path))
    }

    func testMarkKept() throws {
        var state = SentinelState(for: testImageURL)

        try state.markKept()

        XCTAssertTrue(state.isKeep)
        XCTAssertFalse(state.isTrash)
        XCTAssertTrue(state.isReviewed)
    }

    func testMarkTrashed() throws {
        var state = SentinelState(for: testImageURL)

        try state.markTrashed()

        XCTAssertFalse(state.isKeep)
        XCTAssertTrue(state.isTrash)
        XCTAssertTrue(state.isReviewed)
    }

    func testMarkKeptOverridesTrash() throws {
        var state = SentinelState(for: testImageURL)

        try state.markTrashed()
        try state.markKept()

        XCTAssertTrue(state.isKeep)
        XCTAssertFalse(state.isTrash)
    }

    func testToggleFavorite() throws {
        var state = SentinelState(for: testImageURL)

        XCTAssertFalse(state.isFavorite)

        try state.toggleFavorite()
        XCTAssertTrue(state.isFavorite)

        try state.toggleFavorite()
        XCTAssertFalse(state.isFavorite)
    }

    func testClearTriageState() throws {
        var state = SentinelState(for: testImageURL)

        try state.markKept()
        try state.set(.favorite, value: true)
        try state.clearTriageState()

        XCTAssertFalse(state.isKeep)
        XCTAssertFalse(state.isTrash)
        XCTAssertFalse(state.isReviewed)
        XCTAssertTrue(state.isFavorite) // Favorite should not be cleared
    }

    func testRemoveAllSentinels() throws {
        var state = SentinelState(for: testImageURL)

        try state.set(.keep, value: true)
        try state.set(.favorite, value: true)
        try state.set(.reviewed, value: true)
        try state.removeAllSentinels()

        XCTAssertFalse(state.isKeep)
        XCTAssertFalse(state.isTrash)
        XCTAssertFalse(state.isFavorite)
        XCTAssertFalse(state.isReviewed)
    }

    func testRefresh() throws {
        var state = SentinelState(for: testImageURL)

        // Create sentinel file directly
        let keepURL = state.sentinelURL(for: .keep)
        FileManager.default.createFile(atPath: keepURL.path, contents: nil, attributes: nil)

        XCTAssertFalse(state.isKeep) // Not updated yet

        state.refresh()

        XCTAssertTrue(state.isKeep) // Now updated
    }

    func testSentinelURLs() {
        let state = SentinelState(for: testImageURL)

        let keepURL = state.sentinelURL(for: .keep)
        let trashURL = state.sentinelURL(for: .trash)
        let favoriteURL = state.sentinelURL(for: .favorite)
        let reviewedURL = state.sentinelURL(for: .reviewed)

        XCTAssertEqual(keepURL.lastPathComponent, "test_image.jpg.keep")
        XCTAssertEqual(trashURL.lastPathComponent, "test_image.jpg.trash")
        XCTAssertEqual(favoriteURL.lastPathComponent, "test_image.jpg.favorite")
        XCTAssertEqual(reviewedURL.lastPathComponent, "test_image.jpg.reviewed")
    }

    func testStateDescription() throws {
        var state = SentinelState(for: testImageURL)

        XCTAssertEqual(state.stateDescription, "unreviewed")

        try state.markKept()
        XCTAssertTrue(state.stateDescription.contains("kept"))

        try state.set(.favorite, value: true)
        XCTAssertTrue(state.stateDescription.contains("favorite"))
    }

    func testCopySentinels() throws {
        var sourceState = SentinelState(for: testImageURL)
        try sourceState.markKept()
        try sourceState.set(.favorite, value: true)

        let targetURL = testDirectory.appendingPathComponent("target_image.jpg")
        FileManager.default.createFile(atPath: targetURL.path, contents: nil, attributes: nil)

        try sourceState.copySentinels(to: targetURL)

        let targetState = SentinelState(for: targetURL)
        XCTAssertTrue(targetState.isKeep)
        XCTAssertTrue(targetState.isFavorite)
        XCTAssertTrue(targetState.isReviewed)
    }
}
