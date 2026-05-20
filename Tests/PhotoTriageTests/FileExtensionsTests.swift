import XCTest
@testable import PhotoTriage

final class FileExtensionsTests: XCTestCase {

    func testJPEGExtensions() {
        XCTAssertTrue(FileExtensions.isJPEG("jpg"))
        XCTAssertTrue(FileExtensions.isJPEG("jpeg"))
        XCTAssertTrue(FileExtensions.isJPEG("JPG"))
        XCTAssertTrue(FileExtensions.isJPEG("JPEG"))
        XCTAssertFalse(FileExtensions.isJPEG("png"))
        XCTAssertFalse(FileExtensions.isJPEG("cr2"))
    }

    func testRAWExtensions() {
        XCTAssertTrue(FileExtensions.isRAW("cr2"))
        XCTAssertTrue(FileExtensions.isRAW("cr3"))
        XCTAssertTrue(FileExtensions.isRAW("nef"))
        XCTAssertTrue(FileExtensions.isRAW("arw"))
        XCTAssertTrue(FileExtensions.isRAW("dng"))
        XCTAssertTrue(FileExtensions.isRAW("raf"))
        XCTAssertTrue(FileExtensions.isRAW("orf"))
        XCTAssertTrue(FileExtensions.isRAW("rw2"))
        XCTAssertTrue(FileExtensions.isRAW("CR2"))
        XCTAssertTrue(FileExtensions.isRAW("NEF"))
        XCTAssertFalse(FileExtensions.isRAW("jpg"))
        XCTAssertFalse(FileExtensions.isRAW("png"))
    }

    func testSupportedExtensions() {
        XCTAssertTrue(FileExtensions.isSupported("jpg"))
        XCTAssertTrue(FileExtensions.isSupported("cr2"))
        XCTAssertFalse(FileExtensions.isSupported("png"))
        XCTAssertFalse(FileExtensions.isSupported("gif"))
        XCTAssertFalse(FileExtensions.isSupported("pdf"))
    }

    func testDisplayPriority() {
        // JPEG has highest priority (0)
        XCTAssertEqual(FileExtensions.displayPriority("jpg"), 0)
        XCTAssertEqual(FileExtensions.displayPriority("jpeg"), 0)

        // RAW has lower priority (1)
        XCTAssertEqual(FileExtensions.displayPriority("cr2"), 1)
        XCTAssertEqual(FileExtensions.displayPriority("nef"), 1)

        // Unknown has lowest priority (999)
        XCTAssertEqual(FileExtensions.displayPriority("png"), 999)
    }

    func testURLExtensions() {
        let jpegURL = URL(fileURLWithPath: "/test/image.jpg")
        let rawURL = URL(fileURLWithPath: "/test/image.cr2")
        let pngURL = URL(fileURLWithPath: "/test/image.png")

        XCTAssertTrue(jpegURL.isJPEG)
        XCTAssertFalse(jpegURL.isRAW)
        XCTAssertTrue(jpegURL.isSupportedImage)

        XCTAssertFalse(rawURL.isJPEG)
        XCTAssertTrue(rawURL.isRAW)
        XCTAssertTrue(rawURL.isSupportedImage)

        XCTAssertFalse(pngURL.isJPEG)
        XCTAssertFalse(pngURL.isRAW)
        XCTAssertFalse(pngURL.isSupportedImage)
    }

    func testURLStem() {
        let url1 = URL(fileURLWithPath: "/path/to/IMG_1234.jpg")
        let url2 = URL(fileURLWithPath: "/path/to/photo.with.dots.cr2")

        XCTAssertEqual(url1.stem, "IMG_1234")
        XCTAssertEqual(url2.stem, "photo.with.dots")
    }

    func testFileExtensionLowercased() {
        let url1 = URL(fileURLWithPath: "/test/image.JPG")
        let url2 = URL(fileURLWithPath: "/test/image.Cr2")

        XCTAssertEqual(url1.fileExtensionLowercased, "jpg")
        XCTAssertEqual(url2.fileExtensionLowercased, "cr2")
    }
}
