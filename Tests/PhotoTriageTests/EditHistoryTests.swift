import XCTest
@testable import PhotoTriage

/// Snapshot-based undo/redo for on-disk edits.
final class EditHistoryTests: XCTestCase {
    var dir: URL!
    var snapshotDir: URL!
    let service = CropService()

    override func setUpWithError() throws {
        dir = try TestImages.makeTempDirectory("EditHistoryTests")
        snapshotDir = dir.appendingPathComponent("snapshots")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func size(_ url: URL) -> CGSize? { ImagePipeline.orientedPixelSize(url: url) }

    func testUndoFirstEditRestoresFileAndRemovesBackup() async throws {
        let url = try TestImages.makeJPEG(at: dir.appendingPathComponent("a.jpg"), width: 60, height: 40)
        let before = try EditHistory.capture(url, in: snapshotDir)
        XCTAssertFalse(before.hadBackup)

        _ = try await service.applyRotation(to: url, clockwise: true)
        let after = try EditHistory.capture(url, in: snapshotDir)
        XCTAssertTrue(after.hadBackup)
        XCTAssertEqual(size(url), CGSize(width: 40, height: 60))

        // Undo
        try EditHistory.restore(before, to: url)
        XCTAssertEqual(size(url), CGSize(width: 60, height: 40))
        XCTAssertFalse(FileManager.default.fileExists(atPath: service.backupURL(for: url).path),
                       "undoing the first edit removes the backup so Restore Original disappears")

        // Redo recreates the backup from the pre-edit snapshot
        try EditHistory.restore(after, to: url, originalIfMissing: before.imageCopy)
        XCTAssertEqual(size(url), CGSize(width: 40, height: 60))
        XCTAssertTrue(FileManager.default.fileExists(atPath: service.backupURL(for: url).path))
        XCTAssertEqual(size(service.backupURL(for: url)), CGSize(width: 60, height: 40))
    }

    func testUndoSecondEditReturnsToFirstEditNotOriginal() async throws {
        let url = try TestImages.makeJPEG(at: dir.appendingPathComponent("b.jpg"), width: 80, height: 40)

        // Edit 1: crop to 50×40
        _ = try await service.applyCrop(to: url, cropRect: CropRect(x: 0, y: 0, width: 50, height: 40))
        let beforeSecond = try EditHistory.capture(url, in: snapshotDir)

        // Edit 2: rotate
        _ = try await service.applyRotation(to: url, clockwise: false)
        XCTAssertEqual(size(url), CGSize(width: 40, height: 50))

        try EditHistory.restore(beforeSecond, to: url)
        XCTAssertEqual(size(url), CGSize(width: 50, height: 40), "undo keeps the crop from edit 1")
        XCTAssertTrue(FileManager.default.fileExists(atPath: service.backupURL(for: url).path))
        XCTAssertNotNil(service.cropMetadata(for: url), "edit 1's sidecar is restored")
    }

    func testDiscardRemovesSnapshotFiles() throws {
        let url = try TestImages.makeJPEG(at: dir.appendingPathComponent("c.jpg"))
        let snap = try EditHistory.capture(url, in: snapshotDir)
        XCTAssertTrue(FileManager.default.fileExists(atPath: snap.imageCopy.path))
        EditHistory.discard(snap)
        XCTAssertFalse(FileManager.default.fileExists(atPath: snap.imageCopy.path))
    }
}
