import Foundation
import CoreImage

/// Tone adjustments applied during Edit mode and baked into the JPEG on save.
struct ImageAdjustments: Equatable, Codable {
    var exposure: Double = 0      // ±2 EV  — CIExposureAdjust inputEV
    var brightness: Double = 0    // ±0.5   — CIColorControls inputBrightness
    var contrast: Double = 1.0    // 0.5–1.5 — CIColorControls inputContrast
    var highlights: Double = 0    // -1–0; 0 = no change, -1 = max recovery
    var shadows: Double = 0       // -1–1;  0 = no change, +1 = max lift
    var whites: Double = 1.0      // 0.5–1.5; white point (levels ceiling)
    var blacks: Double = 0.0      // -0.5–0.5; black point (levels floor)
    var saturation: Double = 1.0  // 0–2    — CIColorControls inputSaturation

    var isIdentity: Bool {
        exposure == 0 && brightness == 0 && contrast == 1.0 &&
        highlights == 0 && shadows == 0 &&
        whites == 1.0 && blacks == 0.0 &&
        saturation == 1.0
    }

    mutating func reset() { self = .init() }

    /// Apply adjustments to a CIImage and return the result.
    /// Used by CropService when baking adjustments to a JPEG.
    func applyingCI(to input: CIImage) -> CIImage {
        var image = input

        if exposure != 0 {
            if let f = CIFilter(name: "CIExposureAdjust") {
                f.setValue(image, forKey: kCIInputImageKey)
                f.setValue(exposure, forKey: "inputEV")
                image = f.outputImage ?? image
            }
        }

        if brightness != 0 || contrast != 1.0 || saturation != 1.0 {
            if let f = CIFilter(name: "CIColorControls") {
                f.setValue(image, forKey: kCIInputImageKey)
                f.setValue(brightness, forKey: "inputBrightness")
                f.setValue(contrast, forKey: "inputContrast")
                f.setValue(saturation, forKey: "inputSaturation")
                image = f.outputImage ?? image
            }
        }

        if highlights != 0 || shadows != 0 {
            if let f = CIFilter(name: "CIHighlightShadowAdjust") {
                f.setValue(image, forKey: kCIInputImageKey)
                // inputHighlightAmount: 1.0 = identity, 0.0 = full darken
                f.setValue(1.0 + highlights, forKey: "inputHighlightAmount")
                f.setValue(shadows, forKey: "inputShadowAmount")
                image = f.outputImage ?? image
            }
        }

        // Levels remap: output = (input − blacks) / (whites − blacks)
        // CIColorMatrix applies: output = M * input + bias
        if whites != 1.0 || blacks != 0.0, whites > blacks {
            let scale = CGFloat(1.0 / (whites - blacks))
            let bias  = CGFloat(-blacks / (whites - blacks))
            if let f = CIFilter(name: "CIColorMatrix") {
                f.setValue(image, forKey: kCIInputImageKey)
                f.setValue(CIVector(x: scale, y: 0, z: 0, w: 0), forKey: "inputRVector")
                f.setValue(CIVector(x: 0, y: scale, z: 0, w: 0), forKey: "inputGVector")
                f.setValue(CIVector(x: 0, y: 0, z: scale, w: 0), forKey: "inputBVector")
                f.setValue(CIVector(x: 0, y: 0, z: 0, w: 1),     forKey: "inputAVector")
                f.setValue(CIVector(x: bias, y: bias, z: bias, w: 0), forKey: "inputBiasVector")
                image = f.outputImage ?? image
            }
        }

        return image
    }
}
