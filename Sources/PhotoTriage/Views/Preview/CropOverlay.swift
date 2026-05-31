import SwiftUI
import ImageIO

/// Crop overlay with draggable handles and integrated fine-rotation slider
struct CropOverlay: View {
    let url: URL
    @Binding var cropRect: CropRect?
    let preset: CropPreset
    @Binding var imageSize: CGSize
    @Binding var fineRotation: Double   // degrees, ±15°, baked in on apply
    /// When recropping a previously-edited image, the original pixel size of the pre-crop file.
    /// The initial crop rect is centred to this size within the (larger) original.
    var initialCropSizeHint: CGSize? = nil

    @State private var image: NSImage?
    @State private var containerSize: CGSize = .zero
    @State private var dragStartCrop: CropRect?

    private let handleSize: CGFloat = 12
    private let minCropSize: CGFloat = 50

    // Always current — recomputed whenever containerSize or imageSize changes
    private var displayedImageRect: CGRect {
        guard imageSize.width > 0, imageSize.height > 0,
              containerSize.width > 0, containerSize.height > 0 else { return .zero }
        let imageAspect = imageSize.width / imageSize.height
        let containerAspect = containerSize.width / containerSize.height
        let (w, h): (CGFloat, CGFloat)
        if imageAspect > containerAspect {
            w = containerSize.width; h = w / imageAspect
        } else {
            h = containerSize.height; w = h * imageAspect
        }
        return CGRect(
            x: (containerSize.width - w) / 2,
            y: (containerSize.height - h) / 2,
            width: w, height: h
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geometry in
                ZStack {
                    Color.black

                    if let img = image {
                        // Base image — full brightness, sits under dim + clear layers
                        Image(nsImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .rotationEffect(.degrees(fineRotation))

                        // Dim overlay: black over the entire container with a clear hole
                        // at the crop rect so only the crop area shows at full brightness.
                        if let crop = cropRect {
                            let displayCrop = toDisplay(crop)
                            Canvas { ctx, size in
                                var combined = Path(CGRect(origin: .zero, size: size))
                                combined.addRect(displayCrop)
                                ctx.fill(combined, with: .color(Color.black.opacity(0.5)),
                                         style: FillStyle(eoFill: true))
                            }
                        } else {
                            Color.black.opacity(0.5)
                        }

                        // Crop window: same image visible only inside the crop rect
                        if let crop = cropRect {
                            let displayCrop = toDisplay(crop)
                            let r = displayedImageRect
                            Image(nsImage: img)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .rotationEffect(.degrees(fineRotation))
                                .mask {
                                    // Canvas coordinate space is the image view's local space
                                    // (top-left of the fitted image, not the container), so
                                    // subtract the letterbox offset before drawing the mask rect.
                                    Canvas { ctx, _ in
                                        ctx.fill(
                                            Path(CGRect(x: displayCrop.minX - r.minX,
                                                        y: displayCrop.minY - r.minY,
                                                        width: displayCrop.width,
                                                        height: displayCrop.height)),
                                            with: .color(.white)
                                        )
                                    }
                                }

                            // Crop border
                            Rectangle()
                                .stroke(Color.white, lineWidth: 2)
                                .frame(width: displayCrop.width, height: displayCrop.height)
                                .position(x: displayCrop.midX, y: displayCrop.midY)

                            // Rule-of-thirds inside crop
                            ruleOfThirdsGrid(displayCrop: displayCrop)

                            // Resize handles
                            cropHandles(displayCrop: displayCrop)
                        }

                        // Guiding grid always visible in crop mode
                        GuidingGridOverlay()
                    } else {
                        ProgressView()
                    }
                }
                // Clip so the rotated image never bleeds into the toolbar or rotation strip
                .clipped()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(moveCropGesture())
                .onAppear { containerSize = geometry.size }
                .onChange(of: geometry.size) { _, size in containerSize = size }
            }

            rotationStrip
                .background(Color(NSColor.windowBackgroundColor))
        }
        .task(id: url) {
            cropRect = nil
            await loadImage()
            if let hint = initialCropSizeHint,
               hint.width > 0, hint.height > 0,
               imageSize.width > 0, imageSize.height > 0 {
                // Centre the previous crop dimensions within the original image
                let cx = (imageSize.width - hint.width) / 2
                let cy = (imageSize.height - hint.height) / 2
                cropRect = CropRect(
                    x: max(0, cx),
                    y: max(0, cy),
                    width: min(hint.width, imageSize.width),
                    height: min(hint.height, imageSize.height)
                )
            } else {
                cropRect = CropRect.fill(imageSize: imageSize, aspectRatio: preset.ratio)
            }
        }
        .onChange(of: preset) { _, _ in adjustCropToPreset() }
        .onChange(of: fineRotation) { _, _ in clampCropToSafeBounds() }
    }

    // MARK: - Rotation strip

    private var rotationStrip: some View {
        VStack(spacing: 6) {
            HStack(spacing: 12) {
                Button("-0.5°") { fineRotation = max(-15, fineRotation - 0.5) }
                    .buttonStyle(.borderless).font(.caption)
                Slider(value: $fineRotation, in: -15...15, step: 0.1)
                    .frame(maxWidth: 360)
                Button("+0.5°") { fineRotation = min(15, fineRotation + 0.5) }
                    .buttonStyle(.borderless).font(.caption)
                Button("Reset") { fineRotation = 0 }
                    .buttonStyle(.borderless).font(.caption).foregroundStyle(.secondary)
            }
            Text("Horizon adjust: \(String(format: "%+.1f", fineRotation))°")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - Crop decorations

    @ViewBuilder
    private func ruleOfThirdsGrid(displayCrop: CGRect) -> some View {
        let w3 = displayCrop.width / 3
        let h3 = displayCrop.height / 3
        ZStack {
            ForEach(1..<3, id: \.self) { i in
                Rectangle()
                    .fill(Color.white.opacity(0.5))
                    .frame(width: 1, height: displayCrop.height)
                    .position(x: displayCrop.minX + w3 * CGFloat(i), y: displayCrop.midY)
            }
            ForEach(1..<3, id: \.self) { i in
                Rectangle()
                    .fill(Color.white.opacity(0.5))
                    .frame(width: displayCrop.width, height: 1)
                    .position(x: displayCrop.midX, y: displayCrop.minY + h3 * CGFloat(i))
            }
        }
    }

    @ViewBuilder
    private func cropHandles(displayCrop: CGRect) -> some View {
        let corners: [(CGFloat, CGFloat, String)] = [
            (displayCrop.minX, displayCrop.minY, "topLeft"),
            (displayCrop.maxX, displayCrop.minY, "topRight"),
            (displayCrop.minX, displayCrop.maxY, "bottomLeft"),
            (displayCrop.maxX, displayCrop.maxY, "bottomRight")
        ]
        ForEach(corners, id: \.2) { corner in
            Circle()
                .fill(Color.white)
                .frame(width: handleSize, height: handleSize)
                .position(x: corner.0, y: corner.1)
                .gesture(resizeCropGesture(corner: corner.2))
        }
    }

    // MARK: - Gestures

    private func moveCropGesture() -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                if dragStartCrop == nil { dragStartCrop = cropRect }
                guard let start = dragStartCrop else { return }
                moveCropRectFromStart(start, by: value.translation)
            }
            .onEnded { _ in dragStartCrop = nil }
    }

    private func resizeCropGesture(corner: String) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                if dragStartCrop == nil { dragStartCrop = cropRect }
                guard let start = dragStartCrop else { return }
                resizeCropRectFromStart(start, corner: corner, translation: value.translation)
            }
            .onEnded { _ in dragStartCrop = nil }
    }

    // MARK: - Coordinate conversion

    private func toDisplay(_ crop: CropRect) -> CGRect {
        let r = displayedImageRect
        guard r.width > 0, r.height > 0, imageSize.width > 0, imageSize.height > 0 else { return .zero }
        let sx = r.width / imageSize.width
        let sy = r.height / imageSize.height
        return CGRect(x: r.minX + crop.x * sx, y: r.minY + crop.y * sy,
                      width: crop.width * sx, height: crop.height * sy)
    }

    // MARK: - Crop operations

    private func moveCropRectFromStart(_ start: CropRect, by translation: CGSize) {
        let r = displayedImageRect
        guard r.width > 0, r.height > 0 else { return }
        let sx = imageSize.width / r.width
        let sy = imageSize.height / r.height
        let bounds = safeCropBounds(for: fineRotation)
        var crop = start
        crop.x = max(bounds.minX, min(start.x + translation.width * sx, bounds.maxX - start.width))
        crop.y = max(bounds.minY, min(start.y + translation.height * sy, bounds.maxY - start.height))
        cropRect = crop
    }

    private func resizeCropRectFromStart(_ start: CropRect, corner: String, translation: CGSize) {
        let r = displayedImageRect
        guard r.width > 0, r.height > 0 else { return }
        let sx = imageSize.width / r.width
        let sy = imageSize.height / r.height
        let dx = translation.width * sx
        let dy = translation.height * sy
        let bounds = safeCropBounds(for: fineRotation)
        var crop = start

        switch corner {
        case "topLeft":
            crop.x = start.x + dx; crop.width = start.width - dx
            crop.y = start.y + dy; crop.height = start.height - dy
        case "topRight":
            crop.width = start.width + dx
            crop.y = start.y + dy; crop.height = start.height - dy
        case "bottomLeft":
            crop.x = start.x + dx; crop.width = start.width - dx
            crop.height = start.height + dy
        case "bottomRight":
            crop.width = start.width + dx
            crop.height = start.height + dy
        default: break
        }

        crop.width  = min(max(minCropSize, crop.width), bounds.width)
        crop.height = min(max(minCropSize, crop.height), bounds.height)
        if let ratio = preset.ratio { crop.height = crop.width / ratio }
        crop.x = max(bounds.minX, min(crop.x, bounds.maxX - crop.width))
        crop.y = max(bounds.minY, min(crop.y, bounds.maxY - crop.height))
        cropRect = crop
    }

    private func adjustCropToPreset() {
        guard var crop = cropRect else { return }
        let bounds = safeCropBounds(for: fineRotation)
        crop.constrain(to: preset.ratio, within: CGSize(width: bounds.width, height: bounds.height))
        crop.x = max(bounds.minX, min(crop.x, bounds.maxX - crop.width))
        crop.y = max(bounds.minY, min(crop.y, bounds.maxY - crop.height))
        cropRect = crop
    }

    private func clampCropToSafeBounds() {
        guard var crop = cropRect else { return }
        let bounds = safeCropBounds(for: fineRotation)
        crop.width  = min(crop.width, bounds.width)
        crop.height = min(crop.height, bounds.height)
        if let ratio = preset.ratio { crop.height = crop.width / ratio }
        crop.x = max(bounds.minX, min(crop.x, bounds.maxX - crop.width))
        crop.y = max(bounds.minY, min(crop.y, bounds.maxY - crop.height))
        cropRect = crop
    }

    /// Largest centred axis-aligned rectangle that fits inside the image rotated by `degrees`,
    /// i.e. whose corners all touch the rotated boundary — no black pixels included.
    ///
    /// Derived by solving the two binding constraints simultaneously:
    ///   a·cos(θ) + b·sin(θ) = W/2   (right edge)
    ///   a·sin(θ) + b·cos(θ) = H/2   (top edge, from adjacent corner)
    /// giving  safeW = 2a = (W·c − H·s) / cos(2θ),  safeH = 2b = (H·c − W·s) / cos(2θ).
    private func safeCropBounds(for degrees: Double) -> CGRect {
        let radians = abs(degrees) * .pi / 180.0
        let c = cos(radians), s = sin(radians)
        let cos2 = cos(2 * radians)
        let W = imageSize.width, H = imageSize.height
        guard cos2 > 0.001 else {
            return CGRect(origin: .zero, size: imageSize)
        }
        let safeW = (W * c - H * s) / cos2
        let safeH = (H * c - W * s) / cos2
        guard safeW > 1, safeH > 1 else {
            return CGRect(origin: .zero, size: imageSize)
        }
        return CGRect(x: (W - safeW) / 2, y: (H - safeH) / 2, width: safeW, height: safeH)
    }

    // MARK: - Image loading

    private func loadImage() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                // CGImageSource gives the native pixel dimensions, avoiding the DPI-scaling
                // bug where NSImage.size returns logical points (e.g. 1800×1200 for a 6000×4000
                // JPEG at 240 DPI). CropRect coordinates must match what CropService applies.
                guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                      let cgImg = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                    DispatchQueue.main.async { continuation.resume() }
                    return
                }
                let pixelSize = CGSize(width: cgImg.width, height: cgImg.height)
                let nsImage = NSImage(cgImage: cgImg,
                                      size: NSSize(width: cgImg.width, height: cgImg.height))
                DispatchQueue.main.async {
                    self.image = nsImage
                    self.imageSize = pixelSize
                    continuation.resume()
                }
            }
        }
    }
}
