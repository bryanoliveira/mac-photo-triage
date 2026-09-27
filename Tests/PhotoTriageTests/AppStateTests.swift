import XCTest
@testable import PhotoTriage

/// Behavioural tests for navigation, auto-keep, triage ordering and undo.
@MainActor
final class AppStateTests: XCTestCase {
    var dir: URL!
    var appState: AppState!

    override func setUp() async throws {
        dir = try TestImages.makeTempDirectory("AppStateTests")
        for i in 0..<5 {
            try TestImages.makeJPEG(at: dir.appendingPathComponent("IMG_\(i).jpg"),
                                    gray: 0.2 + CGFloat(i) * 0.1,
                                    captureDate: "2024:01:01 10:00:0\(i)")
        }
        appState = AppState()
        await appState.openFolder(dir)
        await appState.analysisTask?.value
        appState.startFresh()
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private var images: [ImageAsset] { appState.folder!.sortedImages }

    // MARK: - Preview

    func testArrowNavigationInPreviewMarksCurrentImageKept() {
        appState.showPreview(for: images[0])
        appState.nextPreviewImage()
        XCTAssertEqual(images[0].triageState, .kept)
        XCTAssertEqual(appState.previewAsset, images[1])

        appState.previousPreviewImage()
        XCTAssertEqual(images[1].triageState, .kept, "left arrow keeps too")
        XCTAssertEqual(appState.previewAsset, images[0])
    }

    func testArrowNavigationDoesNotOverrideTrash() throws {
        try images[0].setTriageState(.trashed)
        appState.showPreview(for: images[0])
        appState.nextPreviewImage()
        XCTAssertEqual(images[0].triageState, .trashed)
    }

    func testArrowAtLastImageStillKeepsIt() {
        appState.showPreview(for: images[4])
        appState.nextPreviewImage()
        XCTAssertEqual(images[4].triageState, .kept)
        XCTAssertEqual(appState.previewAsset, images[4])
    }

    func testNavigationUnderUnreviewedFilterDoesNotSkip() {
        appState.folder!.filter = .unreviewed
        let list = appState.folder!.filteredImages
        appState.showPreview(for: list[0])
        appState.nextPreviewImage()   // list[0] is kept and leaves the filtered list
        XCTAssertEqual(appState.previewAsset, list[1], "must land on the next image, not skip one")
    }

    func testUndoAutoKeepRestoresStateAndNavigatesBack() {
        appState.showPreview(for: images[0])
        appState.nextPreviewImage()
        appState.undo()
        XCTAssertEqual(images[0].triageState, .unreviewed)
        XCTAssertEqual(appState.previewAsset, images[0])
        appState.redo()
        XCTAssertEqual(images[0].triageState, .kept)
    }

    func testTrashAndKeepInPreviewAdvance() {
        appState.showPreview(for: images[0])
        appState.trashPreviewImage()
        XCTAssertEqual(images[0].triageState, .trashed)
        XCTAssertEqual(appState.previewAsset, images[1])
        appState.keepPreviewImage()
        XCTAssertEqual(images[1].triageState, .kept)
        XCTAssertEqual(appState.previewAsset, images[2])
    }

    func testClearPreviewImage() throws {
        try images[2].setTriageState(.trashed)
        appState.showPreview(for: images[2])
        appState.clearPreviewImage()
        XCTAssertEqual(images[2].triageState, .unreviewed)
        XCTAssertEqual(appState.previewAsset, images[2])
    }

    // MARK: - Gallery

    func testDecideSelectedAdvancesSelectionAndIsUndoable() throws {
        try images[0].setTriageState(.kept)
        appState.selectedAsset = images[0]
        appState.decideSelected(.trashed)
        XCTAssertEqual(images[0].triageState, .trashed)
        XCTAssertEqual(appState.selectedAsset, images[1])
        appState.undo()
        XCTAssertEqual(images[0].triageState, .kept, "undo restores the exact previous state")
    }

    // MARK: - Triage

    func testTriageVisitsReviewedImages() throws {
        try images[1].setTriageState(.kept)
        try images[2].setTriageState(.trashed)
        appState.showTriage(from: images[0])
        appState.nextTriageAnchor()
        XCTAssertEqual(appState.triageAnchor, images[1], "kept images are not skipped")
        appState.nextTriageAnchor()
        XCTAssertEqual(appState.triageAnchor, images[2], "trashed images are not skipped")
        XCTAssertEqual(images[2].triageState, .trashed, "forward navigation doesn't un-trash")
        XCTAssertEqual(images[0].triageState, .kept, "undecided anchor is auto-kept")
    }

    func testTriageStartsFromSelectionEvenIfReviewed() throws {
        try images[3].setTriageState(.kept)
        appState.selectedAsset = images[3]
        appState.showTriage()
        XCTAssertEqual(appState.triageAnchor, images[3])
    }

    func testTriageFinishesAtLastImageAndCanGoBack() {
        appState.showTriage(from: images[4])
        appState.nextTriageAnchor()
        XCTAssertTrue(appState.triageFinished)
        XCTAssertEqual(appState.triageAnchor, images[4])
        appState.previousTriageAnchor()
        XCTAssertFalse(appState.triageFinished)
        XCTAssertEqual(appState.triageAnchor, images[4], "first ← just dismisses the completion screen")
    }

    func testKeepLeftUndoRestoresPreviouslyKeptCandidate() throws {
        appState.showTriage(from: images[0])
        guard let candidate = appState.triageCandidate else { return XCTFail("no candidate") }
        try candidate.setTriageState(.kept)
        appState.keepLeft()
        XCTAssertEqual(candidate.triageState, .trashed)
        appState.undo()
        XCTAssertEqual(candidate.triageState, .kept, "not reset to unreviewed")
        XCTAssertEqual(images[0].triageState, .unreviewed)
        XCTAssertEqual(appState.triageCandidate, candidate, "undo brings the pair back")
    }

    func testTrashedImagesAreNotCandidates() throws {
        try images[1].setTriageState(.trashed)
        appState.showTriage(from: images[0])
        XCTAssertNotEqual(appState.triageCandidate, images[1])
        XCTAssertEqual(appState.candidateCount, 3)
    }

    // MARK: - File edits

    func testRotateIsUndoableAndRedoable() async throws {
        let asset = images[0]
        let before = ImagePipeline.orientedPixelSize(url: asset.displayURL)
        await appState.rotate(asset, clockwise: true)
        XCTAssertEqual(ImagePipeline.orientedPixelSize(url: asset.displayURL),
                       before.map { CGSize(width: $0.height, height: $0.width) })
        XCTAssertEqual(asset.thumbnailVersion, 1)
        XCTAssertEqual(appState.undoLabel, "Rotate Right")

        appState.undo()
        XCTAssertEqual(ImagePipeline.orientedPixelSize(url: asset.displayURL), before)
        XCTAssertFalse(FileManager.default.fileExists(atPath: CropService().backupURL(for: asset.displayURL).path))

        appState.redo()
        XCTAssertEqual(ImagePipeline.orientedPixelSize(url: asset.displayURL),
                       before.map { CGSize(width: $0.height, height: $0.width) })
    }

    func testEmptyTrashRequiresConfirmation() throws {
        appState.requestEmptyTrash()
        XCTAssertFalse(appState.showEmptyTrashConfirmation, "nothing to trash")
        try images[0].setTriageState(.trashed)
        appState.requestEmptyTrash()
        XCTAssertTrue(appState.showEmptyTrashConfirmation)
        XCTAssertEqual(appState.trashedCount, 1)
    }

    func testNeighborPrefersNextThenPrevious() {
        let list = images
        XCTAssertEqual(AppState.neighbor(of: list[0], in: list), list[1])
        XCTAssertEqual(AppState.neighbor(of: list[4], in: list), list[3])
        XCTAssertNil(AppState.neighbor(of: list[0], in: [list[0]]))
    }
}
