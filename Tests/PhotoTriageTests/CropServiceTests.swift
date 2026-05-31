import XCTest
import AppKit
import CoreGraphics
import ImageIO
@testable import PhotoTriage

/// Tests that CropService applies crops correctly in pixel space.
///
/// The key invariant: CropRect coordinates must match the native pixel dimensions
/// of the JPEG, not the DPI-scaled NSImage.size (which differs on camera files).
final class CropServiceTests: XCTestCase {

    var tempDir: URL!
    var service: CropService!

    override func setUp() async throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("CropServiceTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        service = CropService()
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - Helpers

    /// Creates a solid-colour JPEG at exact pixel dimensions. The NSImage is given an
    /// artificially high DPI so NSImage.size ≠ pixel dimensions, exposing the DPI bug.
    private func makeJPEG(pixelWidth: Int, pixelHeight: Int,
                           dpi: CGFloat = 240, name: String = "test.jpg") throws -> URL {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: pixelWidth, height: pixelHeight,
            bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { throw TestError.contextFailed }

        // Checkerboard so different crop positions produce different colours
        let tileSize = max(pixelWidth, pixelHeight) / 4
        for row in 0..<4 {
            for col in 0..<4 {
                let isWhite = (row + col) % 2 == 0
                ctx.setFillColor(isWhite ? CGColor.white : CGColor.black)
                ctx.fill(CGRect(x: col * tileSize, y: row * tileSize,
                                width: tileSize, height: tileSize))
            }
        }

        guard let cgImage = ctx.makeImage() else { throw TestError.contextFailed }

        // Embed the specified DPI so NSImage.size will be different from pixel size
        let pointWidth = CGFloat(pixelWidth) * 72.0 / dpi
        let pointHeight = CGFloat(pixelHeight) * 72.0 / dpi
        let nsImage = NSImage(cgImage: cgImage,
                              size: NSSize(width: pointWidth, height: pointHeight))

        let url = tempDir.appendingPathComponent(name)
        guard let tiff = nsImage.tiffRepresentation,
              let bmp = NSBitmapImageRep(data: tiff),
              let jpeg = bmp.representation(using: .jpeg,
                                            properties: [.compressionFactor: 0.95]) else {
            throw TestError.saveFailed
        }
        try jpeg.write(to: url)
        return url
    }

    private func pixelSize(of url: URL) -> CGSize {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
            return .zero
        }
        return CGSize(width: img.width, height: img.height)
    }

    private enum TestError: Error { case contextFailed, saveFailed }

    // MARK: - Crop produces correct output dimensions

    func testCropProducesCorrectDimensions() async throws {
        let url = try makeJPEG(pixelWidth: 600, pixelHeight: 400)
        let crop = CropRect(x: 100, y: 50, width: 300, height: 200)
        _ = try await service.applyCrop(to: url, cropRect: crop)

        let size = pixelSize(of: url)
        XCTAssertEqual(Int(size.width), 300, "Cropped width")
        XCTAssertEqual(Int(size.height), 200, "Cropped height")
    }

    func testCropFullImagePreservesSize() async throws {
        let url = try makeJPEG(pixelWidth: 500, pixelHeight: 300)
        let crop = CropRect(x: 0, y: 0, width: 500, height: 300)
        _ = try await service.applyCrop(to: url, cropRect: crop)

        let size = pixelSize(of: url)
        XCTAssertEqual(Int(size.width), 500)
        XCTAssertEqual(Int(size.height), 300)
    }

    func testCropTopLeftQuarter() async throws {
        let url = try makeJPEG(pixelWidth: 400, pixelHeight: 400)
        // Top-left quarter: x=0,y=0,w=200,h=200
        let crop = CropRect(x: 0, y: 0, width: 200, height: 200)
        _ = try await service.applyCrop(to: url, cropRect: crop)

        let size = pixelSize(of: url)
        XCTAssertEqual(Int(size.width), 200)
        XCTAssertEqual(Int(size.height), 200)
    }

    func testCropBottomRightQuarter() async throws {
        let url = try makeJPEG(pixelWidth: 400, pixelHeight: 400)
        let crop = CropRect(x: 200, y: 200, width: 200, height: 200)
        _ = try await service.applyCrop(to: url, cropRect: crop)

        let size = pixelSize(of: url)
        XCTAssertEqual(Int(size.width), 200)
        XCTAssertEqual(Int(size.height), 200)
    }

    /// Regression: with NSImage.size-based coordinates at 240 DPI, a 600×400 JPEG appears
    /// as 180×120 to NSImage.size. A CropRect of (0,0,180,120) would crop only ~1/9 of the
    /// actual image. With the fix, (0,0,600,400) covers the whole image correctly.
    func testDPIScaledImageCropsInPixelSpace() async throws {
        // 600×400 at 240 DPI → NSImage.size would be (180, 120)
        let url = try makeJPEG(pixelWidth: 600, pixelHeight: 400, dpi: 240)

        // Full-image crop in PIXEL space (correct)
        let crop = CropRect(x: 0, y: 0, width: 600, height: 400)
        _ = try await service.applyCrop(to: url, cropRect: crop)

        let size = pixelSize(of: url)
        XCTAssertEqual(Int(size.width), 600, "Full-image crop must preserve pixel width")
        XCTAssertEqual(Int(size.height), 400, "Full-image crop must preserve pixel height")
    }

    func testCropNarrowStrip() async throws {
        let url = try makeJPEG(pixelWidth: 800, pixelHeight: 600)
        let crop = CropRect(x: 0, y: 250, width: 800, height: 100)
        _ = try await service.applyCrop(to: url, cropRect: crop)

        let size = pixelSize(of: url)
        XCTAssertEqual(Int(size.width), 800)
        XCTAssertEqual(Int(size.height), 100)
    }

    // MARK: - Rotation + crop

    func testRotationAndCropPreservesRequestedOutputSize() async throws {
        let url = try makeJPEG(pixelWidth: 400, pixelHeight: 300)
        let crop = CropRect(x: 50, y: 50, width: 300, height: 200)
        _ = try await service.applyCrop(to: url, cropRect: crop, rotation: 1.5)

        let size = pixelSize(of: url)
        XCTAssertEqual(Int(size.width), 300, "Width after rotation+crop")
        XCTAssertEqual(Int(size.height), 200, "Height after rotation+crop")
    }

    // MARK: - Backup & restore

    func testCropCreatesBackupBeforeModifying() async throws {
        let url = try makeJPEG(pixelWidth: 300, pixelHeight: 200)
        let hasBackupBefore = await service.hasBackup(for: url)
        XCTAssertFalse(hasBackupBefore)

        _ = try await service.applyCrop(to: url, cropRect: CropRect(x: 0, y: 0, width: 100, height: 100))
        let hasBackupAfter = await service.hasBackup(for: url)
        XCTAssertTrue(hasBackupAfter)
    }

    func testRestoreOriginalRestoresPixelDimensions() async throws {
        let url = try makeJPEG(pixelWidth: 400, pixelHeight: 300)
        let originalSize = pixelSize(of: url)

        _ = try await service.applyCrop(to: url, cropRect: CropRect(x: 0, y: 0, width: 100, height: 100))
        let croppedSize = pixelSize(of: url)
        XCTAssertEqual(Int(croppedSize.width), 100, "Verify crop was applied")

        try await service.restoreOriginal(for: url)
        let restoredSize = pixelSize(of: url)
        XCTAssertEqual(restoredSize.width, originalSize.width, "Width restored to original")
        XCTAssertEqual(restoredSize.height, originalSize.height, "Height restored to original")
    }

    func testBackupNotOverwrittenBySecondCrop() async throws {
        let url = try makeJPEG(pixelWidth: 600, pixelHeight: 400)
        let originalSize = pixelSize(of: url)

        // First crop: 200×150
        _ = try await service.applyCrop(to: url, cropRect: CropRect(x: 0, y: 0, width: 200, height: 150))
        // Second crop: 50×50 (applied to already-cropped image)
        _ = try await service.applyCrop(to: url, cropRect: CropRect(x: 0, y: 0, width: 50, height: 50))

        // Restore should return to the pre-first-crop original
        try await service.restoreOriginal(for: url)
        let restoredSize = pixelSize(of: url)
        XCTAssertEqual(restoredSize.width, originalSize.width, "Restores to original, not intermediate")
        XCTAssertEqual(restoredSize.height, originalSize.height)
    }

    func testRestoreWithoutBackupThrowsNoBackup() async throws {
        let url = try makeJPEG(pixelWidth: 200, pixelHeight: 200)
        do {
            try await service.restoreOriginal(for: url)
            XCTFail("Should throw CropError.noBackup")
        } catch CropError.noBackup {
            // expected
        }
    }

    func testRawFileIsRejected() async throws {
        let url = tempDir.appendingPathComponent("photo.CR3")
        FileManager.default.createFile(atPath: url.path, contents: Data())
        do {
            _ = try await service.applyCrop(to: url, cropRect: CropRect(x: 0, y: 0, width: 10, height: 10))
            XCTFail("Should throw rawNotSupported")
        } catch CropError.rawNotSupported {
            // expected
        }
    }
}
