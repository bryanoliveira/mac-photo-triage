import XCTest
import CoreGraphics
@testable import PhotoTriage

/// Histogram, clipping masks, image pipeline and triage-state sentinels.
final class ImagingUtilitiesTests: XCTestCase {
    var dir: URL!

    override func setUpWithError() throws {
        dir = try TestImages.makeTempDirectory("ImagingUtilitiesTests")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func solid(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, size: Int = 32) -> CGImage {
        let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        ctx.setFillColor(CGColor(red: r, green: g, blue: b, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
        return ctx.makeImage()!
    }

    // MARK: Histogram

    func testHistogramOfWhiteImageIsFullyClipped() {
        let h = Histogram.compute(from: solid(1, 1, 1))
        XCTAssertEqual(h.highlightClipFraction, 1, accuracy: 1e-9)
        XCTAssertEqual(h.shadowClipFraction, 0)
        XCTAssertEqual(h.luminance[255], h.pixelCount)
    }

    func testHistogramOfBlackImageIsShadowClipped() {
        let h = Histogram.compute(from: solid(0, 0, 0))
        XCTAssertEqual(h.shadowClipFraction, 1, accuracy: 1e-9)
        XCTAssertEqual(h.red[0], h.pixelCount)
    }

    func testSingleBlownChannelCountsAsHighlightClipping() {
        let h = Histogram.compute(from: solid(1, 0.2, 0.1))
        XCTAssertEqual(h.highlightClipFraction, 1, accuracy: 1e-9)
    }

    func testHistogramDownsamples() {
        let h = Histogram.compute(from: solid(0.5, 0.5, 0.5, size: 1000), maxDimension: 100)
        XCTAssertEqual(h.pixelCount, 100 * 100)
    }

    // MARK: Clipping masks

    func testClippingMasksFromImage() {
        XCTAssertNotNil(ClippingAnalyzer.buildMasks(from: solid(1, 0, 0)))
        let masks = ClippingAnalyzer.buildMasks(from: solid(0.5, 0.5, 0.5, size: 16))
        XCTAssertEqual(masks?.highlights.size, CGSize(width: 16, height: 16))
    }

    // MARK: Image pipeline

    func testPipelineAppliesOrientationAndDownsamples() async throws {
        let url = try TestImages.makeJPEG(at: dir.appendingPathComponent("rot.jpg"), width: 200, height: 100, orientation: 6)
        XCTAssertEqual(ImagePipeline.orientedPixelSize(url: url), CGSize(width: 100, height: 200))

        let full = ImagePipeline.decode(url: url, maxPixel: nil)
        XCTAssertEqual(full?.size, CGSize(width: 100, height: 200))

        let small = ImagePipeline.decode(url: url, maxPixel: 50)
        XCTAssertEqual(small.map { max($0.size.width, $0.size.height) }, 50)
    }

    func testPipelineCachesAndInvalidates() async throws {
        let pipeline = ImagePipeline()
        let url = try TestImages.makeJPEG(at: dir.appendingPathComponent("c.jpg"))
        XCTAssertNil(pipeline.cachedImage(for: url, tier: .thumbnail))
        let first = await pipeline.image(for: url, tier: .thumbnail)
        XCTAssertNotNil(first)
        XCTAssertTrue(pipeline.cachedImage(for: url, tier: .thumbnail) === first)
        pipeline.invalidate(url)
        XCTAssertNil(pipeline.cachedImage(for: url, tier: .thumbnail), "edits must drop cached pixels")
    }

    func testPipelineReturnsNilForUnreadableFile() async {
        let url = dir.appendingPathComponent("broken.jpg")
        FileManager.default.createFile(atPath: url.path, contents: Data("nope".utf8))
        let img = await ImagePipeline().image(for: url, tier: .screen)
        XCTAssertNil(img)
    }

    // MARK: Triage state

    func testTriageStateRoundTripsThroughSentinels() throws {
        let url = dir.appendingPathComponent("s.jpg")
        FileManager.default.createFile(atPath: url.path, contents: Data())
        var state = SentinelState(for: url)
        for target in TriageState.allCases {
            try state.apply(target)
            XCTAssertEqual(state.triageState, target)
            XCTAssertEqual(SentinelState(for: url).triageState, target, "persisted to disk")
        }
    }

    func testSetTriageStateMirrorsToRAW() throws {
        let jpg = dir.appendingPathComponent("p.jpg"), raw = dir.appendingPathComponent("p.cr2")
        FileManager.default.createFile(atPath: jpg.path, contents: Data())
        FileManager.default.createFile(atPath: raw.path, contents: Data())
        let asset = ImageAsset(jpegURL: jpg, rawURL: raw)
        try asset.setTriageState(.trashed)
        XCTAssertTrue(SentinelState(for: raw).isTrash)
        try asset.setTriageState(.unreviewed)
        XCTAssertEqual(SentinelState(for: raw).triageState, .unreviewed)
    }
}
