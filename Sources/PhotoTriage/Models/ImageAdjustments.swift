import Foundation
import CoreImage

/// Tone and color adjustments applied in Edit mode and baked into the JPEG on save.
///
/// Every slider except exposure is normalised to **−1…+1 with 0 = no change**, and follows
/// Lightroom's conventions (moving right brightens / adds). The UI shows them as −100…+100.
/// The pixel math lives in `ToneMapper`; `applyingCI(to:)` bakes it into a 3D LUT.
struct ImageAdjustments: Equatable {
    var exposure: Double = 0      // EV, −3…+3. Linear-light gain with a highlight shoulder (no hard clipping)
    var brightness: Double = 0    // midtone gamma — lifts/darkens mids, keeps black & white fixed
    var contrast: Double = 0      // smooth S-curve around mid-grey (never clips)
    var highlights: Double = 0    // −1 recovers bright areas, +1 brightens them
    var shadows: Double = 0       // +1 opens up dark areas, −1 deepens them
    var whites: Double = 0        // white point: + brightens / clips the top end, − dims it
    var blacks: Double = 0        // black point: + lifts blacks, − crushes them
    var temperature: Double = 0   // − cooler (blue), + warmer (amber)
    var tint: Double = 0          // − green, + magenta
    var vibrance: Double = 0      // saturation boost weighted towards muted colours
    var saturation: Double = 0    // uniform saturation: −1 = monochrome, +1 = double

    var isIdentity: Bool { self == ImageAdjustments() }

    mutating func reset() { self = .init() }

    /// Apply adjustments to a CIImage and return the result.
    /// - Parameters:
    ///   - colorSpace: RGB space the tone math runs in; pass the source image's space so wide-gamut
    ///     photos are not clipped to sRGB. Defaults to sRGB.
    ///   - cubeDimension: LUT resolution — 32 is plenty for interactive preview, 64 for export.
    func applyingCI(to input: CIImage, colorSpace: CGColorSpace? = nil, cubeDimension: Int = 64) -> CIImage {
        guard !isIdentity else { return input }
        let space = colorSpace.flatMap { $0.model == .rgb ? $0 : nil }
            ?? CGColorSpace(name: CGColorSpace.sRGB)!
        let mapper = ToneMapper(self)
        guard let f = CIFilter(name: "CIColorCubeWithColorSpace") else { return input }
        f.setValue(input, forKey: kCIInputImageKey)
        f.setValue(cubeDimension, forKey: "inputCubeDimension")
        f.setValue(mapper.cubeData(dimension: cubeDimension), forKey: "inputCubeData")
        f.setValue(space, forKey: "inputColorSpace")
        return f.outputImage ?? input
    }
}

// MARK: - Codable (with migration from the v1 sidecar format)

extension ImageAdjustments: Codable {
    private enum CodingKeys: String, CodingKey {
        case version, exposure, brightness, contrast, highlights, shadows, whites, blacks
        case temperature, tint, vibrance, saturation
    }

    static let currentVersion = 2

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        func value(_ key: CodingKeys, _ fallback: Double) throws -> Double {
            try c.decodeIfPresent(Double.self, forKey: key) ?? fallback
        }
        exposure = try value(.exposure, 0)
        highlights = try value(.highlights, 0)
        shadows = try value(.shadows, 0)
        if version >= 2 {
            brightness = try value(.brightness, 0)
            contrast = try value(.contrast, 0)
            whites = try value(.whites, 0)
            blacks = try value(.blacks, 0)
            temperature = try value(.temperature, 0)
            tint = try value(.tint, 0)
            vibrance = try value(.vibrance, 0)
            saturation = try value(.saturation, 0)
        } else {
            // v1 stored CIColorControls-style values: brightness ±0.5, contrast/saturation as
            // multipliers around 1, whites/blacks as raw levels points (whites 1 = identity).
            let clamp = { (v: Double) in min(1, max(-1, v)) }
            brightness = clamp(try value(.brightness, 0) * 2)
            contrast = clamp((try value(.contrast, 1) - 1) * 2)
            whites = clamp((1 - (try value(.whites, 1))) / ToneMapper.whitesRange)
            blacks = clamp(-(try value(.blacks, 0)) / ToneMapper.blacksRange)
            saturation = clamp(try value(.saturation, 1) - 1)
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(Self.currentVersion, forKey: .version)
        try c.encode(exposure, forKey: .exposure)
        try c.encode(brightness, forKey: .brightness)
        try c.encode(contrast, forKey: .contrast)
        try c.encode(highlights, forKey: .highlights)
        try c.encode(shadows, forKey: .shadows)
        try c.encode(whites, forKey: .whites)
        try c.encode(blacks, forKey: .blacks)
        try c.encode(temperature, forKey: .temperature)
        try c.encode(tint, forKey: .tint)
        try c.encode(vibrance, forKey: .vibrance)
        try c.encode(saturation, forKey: .saturation)
    }
}

// MARK: - Tone mapping

/// Pure per-pixel implementation of `ImageAdjustments`, operating on gamma-encoded RGB in
/// [0, 1]. Kept free of CoreImage so it can be unit-tested directly; `cubeData` samples it
/// into a LUT for `CIColorCubeWithColorSpace`.
///
/// Pipeline (order matters):
/// 1. decode to linear light
/// 2. white balance (temperature / tint) as luminance-neutral channel gains
/// 3. **exposure** — gain of 2^EV in linear light. For +EV a rational shoulder maps the new
///    white (2^EV) back to 1.0, so highlights roll off smoothly instead of clipping
///    (`CIExposureAdjust` clipped everything above 1/2^EV)
/// 4. **shadows / highlights** — a smooth curve on perceptual luminance whose effect is
///    concentrated in the dark (resp. bright) end and fades to zero across the midtones. The
///    luminance change is applied as an RGB *ratio*, so hue and saturation are preserved —
///    lifted shadows stay colourful instead of turning grey, and recovered highlights regain
///    colour. The curves are monotonic for every slider value (no tonal inversions or halos)
/// 5. encode to perceptual space
/// 6. whites / blacks (levels), brightness (midtone gamma), contrast (S-curve)
/// 7. vibrance / saturation around Rec.709 luma
struct ToneMapper {
    let adjustments: ImageAdjustments

    /// Levels travel at ±1: whites moves the white point by 30%, blacks the black point by 15%
    static let whitesRange = 0.30
    static let blacksRange = 0.15

    /// Shadows/highlights curve extent (in perceptual luminance) and strengths
    static let toneExtent = 0.7
    static let toneBoostStrength = 3.0   // opening shadows / recovering highlights
    static let toneCutStrength = 0.9     // deepening shadows / brightening highlights (must stay < 1)

    private let wbGains: (r: Double, g: Double, b: Double)
    private let exposureGain: Double
    private let shoulderA: Double
    private let shoulderKnee = 0.5

    init(_ adjustments: ImageAdjustments) {
        self.adjustments = adjustments

        let r = pow(2, 0.35 * adjustments.temperature)
        let b = pow(2, -0.35 * adjustments.temperature)
        let g = pow(2, -0.3 * adjustments.tint)
        let luma = 0.2126 * r + 0.7152 * g + 0.0722 * b
        wbGains = (r / luma, g / luma, b / luma)

        exposureGain = pow(2, adjustments.exposure)
        let w = exposureGain, k = shoulderKnee
        shoulderA = w > 1 ? (w - 1) / ((1 - k) * (w - k)) : 0
    }

    // MARK: Transfer functions

    static func decode(_ v: Double) -> Double {
        v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
    }

    static func encode(_ v: Double) -> Double {
        v <= 0.0031308 ? v * 12.92 : 1.055 * pow(v, 1 / 2.4) - 0.055
    }

    static func luminance(_ r: Double, _ g: Double, _ b: Double) -> Double {
        0.2126 * r + 0.7152 * g + 0.0722 * b
    }

    // MARK: Individual curves (exposed for testing)

    /// Exposure in linear light: gain, then a C¹-continuous shoulder above the knee that maps
    /// 2^EV → 1 so +EV never hard-clips.
    func exposed(_ x: Double) -> Double {
        let y = x * exposureGain
        guard shoulderA > 0, y > shoulderKnee else { return y }
        let t = y - shoulderKnee
        return shoulderKnee + t / (1 + shoulderA * t)
    }

    /// Shadow-weighted lift: s(L) = a·L·(1 − L/e)³ on [0, e], zero elsewhere.
    /// Peaks at L = e/4; slope stays positive for a < 4 (boost) and a < 1 (cut).
    static func shadowCurve(_ l: Double, amount: Double) -> Double {
        guard amount != 0, l > 0, l < toneExtent else { return l }
        let a = amount > 0 ? toneBoostStrength * amount : toneCutStrength * amount
        let f = 1 - l / toneExtent
        return l + a * l * f * f * f
    }

    /// Highlights are the shadow curve mirrored around white: −amount recovers (darkens).
    static func highlightCurve(_ l: Double, amount: Double) -> Double {
        guard amount != 0 else { return l }
        return 1 - shadowCurve(1 - l, amount: -amount)
    }

    /// Smooth contrast S-curve pivoting at 0.5: slope 2^amount at the pivot, fixed 0 and 1.
    static func contrastCurve(_ p: Double, amount: Double) -> Double {
        guard amount != 0 else { return p }
        let c = pow(2, amount)
        let x = min(max(p, 0), 1)
        return x < 0.5 ? 0.5 * pow(2 * x, c) : 1 - 0.5 * pow(2 * (1 - x), c)
    }

    /// Midtone gamma: exponent 2^−amount (amount +1 → 0.5, brightens mids).
    static func brightnessCurve(_ p: Double, amount: Double) -> Double {
        guard amount != 0 else { return p }
        return pow(min(max(p, 0), 1), pow(2, -amount))
    }

    // MARK: Full pipeline

    /// Map one gamma-encoded RGB triple (components in [0, 1]) through every adjustment.
    func map(_ r: Double, _ g: Double, _ b: Double) -> (Double, Double, Double) {
        let adj = adjustments
        // 1–2: linear light + white balance
        var lr = Self.decode(r) * wbGains.r
        var lg = Self.decode(g) * wbGains.g
        var lb = Self.decode(b) * wbGains.b

        // 3: exposure with highlight shoulder
        if adj.exposure != 0 {
            lr = exposed(lr); lg = exposed(lg); lb = exposed(lb)
        }

        // 4: shadows / highlights on perceptual luminance, applied as a colour-preserving ratio
        if adj.shadows != 0 || adj.highlights != 0 {
            let y = max(Self.luminance(lr, lg, lb), 0)
            let l = Self.encode(min(y, 1))
            var l2 = Self.shadowCurve(l, amount: adj.shadows)
            l2 = Self.highlightCurve(l2, amount: adj.highlights)
            let y2 = Self.decode(min(max(l2, 0), 1))
            let ratio: Double
            if y > 1e-6 {
                ratio = y2 / y
            } else {
                // Limit of the ratio at black: slope of the curve at 0 (linear sRGB toe)
                ratio = 1 + (adj.shadows > 0 ? Self.toneBoostStrength : Self.toneCutStrength) * adj.shadows
            }
            lr *= ratio; lg *= ratio; lb *= ratio
        }

        // 5: perceptual space
        var pr = Self.encode(min(max(lr, 0), 1))
        var pg = Self.encode(min(max(lg, 0), 1))
        var pb = Self.encode(min(max(lb, 0), 1))

        // 6: levels, brightness, contrast (per channel)
        let whitePoint = 1 - Self.whitesRange * adj.whites
        let blackPoint = -Self.blacksRange * adj.blacks
        func tone(_ p: Double) -> Double {
            var v = p
            if adj.whites != 0 || adj.blacks != 0 {
                v = min(max((v - blackPoint) / (whitePoint - blackPoint), 0), 1)
            }
            v = Self.brightnessCurve(v, amount: adj.brightness)
            v = Self.contrastCurve(v, amount: adj.contrast)
            return v
        }
        pr = tone(pr); pg = tone(pg); pb = tone(pb)

        // 7: vibrance + saturation around luma
        if adj.vibrance != 0 || adj.saturation != 0 {
            let luma = Self.luminance(pr, pg, pb)
            let maxC = max(pr, pg, pb), minC = min(pr, pg, pb)
            let currentSat = maxC > 1e-6 ? (maxC - minC) / maxC : 0
            let factor = (1 + adj.saturation) * (1 + adj.vibrance * (1 - currentSat))
            pr = luma + (pr - luma) * factor
            pg = luma + (pg - luma) * factor
            pb = luma + (pb - luma) * factor
        }

        return (min(max(pr, 0), 1), min(max(pg, 0), 1), min(max(pb, 0), 1))
    }

    /// Sample `map` into RGBA Float32 cube data for `CIColorCube*` (red varies fastest).
    func cubeData(dimension n: Int) -> Data {
        var values = [Float](repeating: 1, count: n * n * n * 4)
        let scale = 1 / Double(n - 1)
        var i = 0
        for bi in 0..<n {
            let b = Double(bi) * scale
            for gi in 0..<n {
                let g = Double(gi) * scale
                for ri in 0..<n {
                    let (or, og, ob) = map(Double(ri) * scale, g, b)
                    values[i] = Float(or)
                    values[i + 1] = Float(og)
                    values[i + 2] = Float(ob)
                    i += 4
                }
            }
        }
        return values.withUnsafeBufferPointer { Data(buffer: $0) }
    }
}
