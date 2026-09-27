import XCTest
import CoreImage
@testable import PhotoTriage

/// Tests for the tone/colour pipeline behind the Edit sliders.
final class ToneMapperTests: XCTestCase {

    private func mapper(_ configure: (inout ImageAdjustments) -> Void) -> ToneMapper {
        var adj = ImageAdjustments()
        configure(&adj)
        return ToneMapper(adj)
    }

    /// Output luminance-ish value for a neutral grey input
    private func grey(_ m: ToneMapper, _ v: Double) -> Double {
        m.map(v, v, v).0
    }

    private func assertMonotonicGreyRamp(_ m: ToneMapper, file: StaticString = #filePath, line: UInt = #line) {
        var previous = -1.0
        for i in 0...200 {
            let out = grey(m, Double(i) / 200)
            XCTAssertGreaterThanOrEqual(out, previous - 1e-9, "not monotonic at \(i)", file: file, line: line)
            XCTAssertTrue((0...1).contains(out), "out of range at \(i)", file: file, line: line)
            previous = out
        }
    }

    // MARK: - Identity

    func testIdentityLeavesPixelsUnchanged() {
        let m = ToneMapper(ImageAdjustments())
        for r in stride(from: 0.0, through: 1.0, by: 0.125) {
            for g in stride(from: 0.0, through: 1.0, by: 0.25) {
                let out = m.map(r, g, 0.3)
                XCTAssertEqual(out.0, r, accuracy: 1e-9)
                XCTAssertEqual(out.1, g, accuracy: 1e-9)
                XCTAssertEqual(out.2, 0.3, accuracy: 1e-9)
            }
        }
    }

    func testTransferFunctionsRoundTrip() {
        for i in 0...100 {
            let v = Double(i) / 100
            XCTAssertEqual(ToneMapper.encode(ToneMapper.decode(v)), v, accuracy: 1e-9)
        }
    }

    // MARK: - Exposure

    func testNegativeExposureHalvesLinearLight() {
        let m = mapper { $0.exposure = -1 }
        let input = 0.6
        let expectedLinear = ToneMapper.decode(input) / 2
        XCTAssertEqual(ToneMapper.decode(grey(m, input)), expectedLinear, accuracy: 1e-6)
    }

    func testPositiveExposureBrightensWithoutHardClipping() {
        let m = mapper { $0.exposure = 2 }
        // Mid-grey gets much brighter
        XCTAssertGreaterThan(grey(m, 0.46), 0.7)
        // Bright tones stay distinguishable instead of all clipping to white (CIExposureAdjust
        // would have clipped everything above 25% linear light at +2 EV)
        let a = grey(m, 0.8), b = grey(m, 0.9), c = grey(m, 0.95)
        XCTAssertLessThan(a, b)
        XCTAssertLessThan(b, c)
        XCTAssertLessThan(c, 1.0)
        // White stays white, black stays black
        XCTAssertEqual(grey(m, 1), 1, accuracy: 1e-9)
        XCTAssertEqual(grey(m, 0), 0, accuracy: 1e-9)
        assertMonotonicGreyRamp(m)
    }

    func testExposureShoulderIsContinuousAtKnee() {
        let m = mapper { $0.exposure = 1 }
        // Just below and just above the knee (linear 0.5 after gain → input 0.25 linear)
        let below = m.exposed(0.25 - 1e-6), above = m.exposed(0.25 + 1e-6)
        XCTAssertEqual(below, above, accuracy: 1e-5)
    }

    // MARK: - Shadows / highlights

    func testShadowsLiftDarkTonesAndLeaveHighlightsAlone() {
        let m = mapper { $0.shadows = 1 }
        XCTAssertGreaterThan(grey(m, 0.15), 0.15 + 0.1, "deep shadows should open up noticeably")
        XCTAssertEqual(grey(m, 0.85), 0.85, accuracy: 1e-6, "highlights untouched")
        XCTAssertEqual(grey(m, 1), 1, accuracy: 1e-9)
        XCTAssertEqual(grey(m, 0), 0, accuracy: 1e-9)
    }

    func testNegativeShadowsDeepenDarkTones() {
        let m = mapper { $0.shadows = -1 }
        XCTAssertLessThan(grey(m, 0.2), 0.2 - 0.02)
        XCTAssertEqual(grey(m, 0.9), 0.9, accuracy: 1e-6)
    }

    func testShadowLiftPreservesColour() {
        let m = mapper { $0.shadows = 1 }
        let (r, g, b) = (0.25, 0.12, 0.06)
        let out = m.map(r, g, b)
        // Ratios between channels in linear light are unchanged → hue & saturation preserved
        let before = ToneMapper.decode(r) / ToneMapper.decode(g)
        let after = ToneMapper.decode(out.0) / ToneMapper.decode(out.1)
        XCTAssertEqual(after, before, accuracy: 1e-6)
        XCTAssertGreaterThan(out.0, r)
    }

    func testHighlightRecoveryDarkensBrightTones() {
        let m = mapper { $0.highlights = -1 }
        XCTAssertLessThan(grey(m, 0.9), 0.9 - 0.1)
        XCTAssertEqual(grey(m, 0.2), 0.2, accuracy: 1e-6, "shadows untouched")
        XCTAssertEqual(grey(m, 1), 1, accuracy: 1e-9, "clipped white can't be recovered and stays white")
    }

    func testPositiveHighlightsBrightenBrightTones() {
        let m = mapper { $0.highlights = 1 }
        XCTAssertGreaterThan(grey(m, 0.8), 0.8)
        XCTAssertLessThanOrEqual(grey(m, 0.8), 1)
    }

    func testShadowAndHighlightCurvesAreMonotonicForAllAmounts() {
        for amount in [-1.0, -0.5, 0.3, 1.0] {
            assertMonotonicGreyRamp(mapper { $0.shadows = amount })
            assertMonotonicGreyRamp(mapper { $0.highlights = amount })
        }
        assertMonotonicGreyRamp(mapper { $0.shadows = 1; $0.highlights = -1; $0.exposure = 1.5 })
    }

    // MARK: - Contrast, levels, brightness

    func testContrastCurveFixedPointsAndSlope() {
        for amount in [-1.0, 1.0] {
            XCTAssertEqual(ToneMapper.contrastCurve(0, amount: amount), 0, accuracy: 1e-9)
            XCTAssertEqual(ToneMapper.contrastCurve(0.5, amount: amount), 0.5, accuracy: 1e-9)
            XCTAssertEqual(ToneMapper.contrastCurve(1, amount: amount), 1, accuracy: 1e-9)
        }
        XCTAssertLessThan(ToneMapper.contrastCurve(0.3, amount: 1), 0.3, "more contrast darkens below mid")
        XCTAssertGreaterThan(ToneMapper.contrastCurve(0.7, amount: 1), 0.7, "more contrast brightens above mid")
        XCTAssertGreaterThan(ToneMapper.contrastCurve(0.3, amount: -1), 0.3, "less contrast lifts below mid")
        assertMonotonicGreyRamp(mapper { $0.contrast = 1 })
    }

    func testWhitesAndBlacksFollowLightroomDirection() {
        XCTAssertGreaterThan(grey(mapper { $0.whites = 1 }, 0.7), 0.7, "+whites brightens")
        XCTAssertLessThan(grey(mapper { $0.whites = -1 }, 1.0), 1.0, "−whites dims white")
        XCTAssertGreaterThan(grey(mapper { $0.blacks = 1 }, 0.0), 0.0, "+blacks lifts black")
        XCTAssertEqual(grey(mapper { $0.blacks = -1 }, 0.1), 0, accuracy: 1e-9, "−blacks crushes near-black")
    }

    func testBrightnessMovesMidtonesButNotEndpoints() {
        let m = mapper { $0.brightness = 1 }
        XCTAssertGreaterThan(grey(m, 0.5), 0.6)
        XCTAssertEqual(grey(m, 0), 0, accuracy: 1e-9)
        XCTAssertEqual(grey(m, 1), 1, accuracy: 1e-9)
    }

    // MARK: - Colour

    func testSaturationMinusOneIsMonochrome() {
        let out = mapper { $0.saturation = -1 }.map(0.8, 0.3, 0.1)
        XCTAssertEqual(out.0, out.1, accuracy: 1e-9)
        XCTAssertEqual(out.1, out.2, accuracy: 1e-9)
    }

    func testVibranceBoostsMutedColoursMoreThanSaturatedOnes() {
        let m = mapper { $0.vibrance = 1 }
        func chroma(_ c: (Double, Double, Double)) -> Double { max(c.0, c.1, c.2) - min(c.0, c.1, c.2) }
        let muted = (0.55, 0.5, 0.45), vivid = (0.9, 0.2, 0.1)
        let mutedGain = chroma(m.map(muted.0, muted.1, muted.2)) / chroma(muted)
        let vividGain = chroma(m.map(vivid.0, vivid.1, vivid.2)) / chroma(vivid)
        XCTAssertGreaterThan(mutedGain, vividGain)
    }

    func testTemperatureWarmsNeutralsAndPreservesLuminance() {
        let warm = mapper { $0.temperature = 1 }.map(0.5, 0.5, 0.5)
        XCTAssertGreaterThan(warm.0, warm.2, "warmer → more red than blue")
        let cool = mapper { $0.temperature = -1 }.map(0.5, 0.5, 0.5)
        XCTAssertGreaterThan(cool.2, cool.0)
        let lum = ToneMapper.luminance(ToneMapper.decode(warm.0), ToneMapper.decode(warm.1), ToneMapper.decode(warm.2))
        XCTAssertEqual(lum, ToneMapper.decode(0.5), accuracy: 0.01)
    }

    // MARK: - LUT / CoreImage

    func testCubeDataLayout() {
        let n = 8
        let data = mapper { $0.exposure = 0.5 }.cubeData(dimension: n)
        XCTAssertEqual(data.count, n * n * n * 4 * MemoryLayout<Float>.size)
        let floats = data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
        // First entry is black, last is white (both fixed points), alpha is 1
        XCTAssertEqual(floats[0], 0, accuracy: 1e-6)
        XCTAssertEqual(floats[3], 1)
        XCTAssertEqual(floats[floats.count - 4], 1, accuracy: 1e-6)
        // Red varies fastest: entry 1 is (1/7, 0, 0) → red > 0, green == 0
        XCTAssertGreaterThan(floats[4], 0)
        XCTAssertEqual(floats[5], 0, accuracy: 1e-6)
    }

    func testApplyingCIIdentityReturnsInput() {
        let input = CIImage(color: CIColor(red: 0.4, green: 0.4, blue: 0.4)).cropped(to: CGRect(x: 0, y: 0, width: 4, height: 4))
        XCTAssertTrue(ImageAdjustments().applyingCI(to: input) === input)
    }

    func testApplyingCIRendersAdjustment() throws {
        let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
        let input = CIImage(color: CIColor(red: 0.3, green: 0.3, blue: 0.3, alpha: 1, colorSpace: sRGB)!)
            .cropped(to: CGRect(x: 0, y: 0, width: 4, height: 4))
        var adj = ImageAdjustments()
        adj.exposure = 1
        let output = adj.applyingCI(to: input, colorSpace: sRGB, cubeDimension: 32)
        var pixel = [UInt8](repeating: 0, count: 4)
        CIContext.shared.render(output, toBitmap: &pixel, rowBytes: 4,
                                bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: sRGB)
        let expected = ToneMapper(adj).map(0.3, 0.3, 0.3).0 * 255
        XCTAssertEqual(Double(pixel[0]), expected, accuracy: 3)
        XCTAssertGreaterThan(Double(pixel[0]), 0.3 * 255 + 20)
    }

    // MARK: - Codable

    func testCodableRoundTrip() throws {
        var adj = ImageAdjustments()
        adj.exposure = 0.7; adj.shadows = 0.4; adj.temperature = -0.2; adj.vibrance = 0.5
        let data = try JSONEncoder().encode(adj)
        XCTAssertEqual(try JSONDecoder().decode(ImageAdjustments.self, from: data), adj)
    }

    func testDecodesVersion1Sidecar() throws {
        // v1 used CIColorControls-style values with 1.0 as identity for contrast/saturation/whites
        let json = """
        {"exposure":0.5,"brightness":0.25,"contrast":1.5,"highlights":-0.5,"shadows":0.3,
         "whites":1.0,"blacks":0.0,"saturation":0.5}
        """.data(using: .utf8)!
        let adj = try JSONDecoder().decode(ImageAdjustments.self, from: json)
        XCTAssertEqual(adj.exposure, 0.5)
        XCTAssertEqual(adj.brightness, 0.5, accuracy: 1e-9)
        XCTAssertEqual(adj.contrast, 1.0, accuracy: 1e-9)
        XCTAssertEqual(adj.highlights, -0.5)
        XCTAssertEqual(adj.shadows, 0.3)
        XCTAssertEqual(adj.whites, 0, accuracy: 1e-9)
        XCTAssertEqual(adj.blacks, 0, accuracy: 1e-9)
        XCTAssertEqual(adj.saturation, -0.5, accuracy: 1e-9)
    }

    func testDecodesV1IdentityAsIdentity() throws {
        let json = #"{"exposure":0,"brightness":0,"contrast":1,"highlights":0,"shadows":0,"whites":1,"blacks":0,"saturation":1}"#
        let adj = try JSONDecoder().decode(ImageAdjustments.self, from: json.data(using: .utf8)!)
        XCTAssertTrue(adj.isIdentity)
    }

    func testCropMetadataWithoutAdjustmentsStillDecodes() throws {
        let json = #"{"cropX":0,"cropY":0,"cropWidth":10,"cropHeight":10,"rotation":1.5}"#
        let meta = try JSONDecoder().decode(CropMetadata.self, from: json.data(using: .utf8)!)
        XCTAssertNil(meta.adjustments)
        XCTAssertEqual(meta.rotation, 1.5)
    }
}
