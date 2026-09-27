import SwiftUI
import AppKit
import ImageIO
import CoreImage

/// Edit overlay: crop handles, right sidebar with preset picker, horizon slider, and tone adjustments.
struct CropOverlay: View {
    let url: URL
    @Binding var cropRect: CropRect?
    @Binding var preset: CropPreset
    @Binding var imageSize: CGSize
    @Binding var fineRotation: Double   // degrees, ±15°, baked in on apply
    @Binding var adjustments: ImageAdjustments
    /// Exact crop rect (in original pixel space) to restore when re-entering Edit mode.
    var initialCropHint: CropRect? = nil
    /// Show red/blue clipping on the *adjusted* preview
    var showClippingWarnings: Bool = false

    // Base image (thumbnail at display resolution, EXIF-corrected)
    @State private var image: NSImage?
    @State private var baseCGImage: CGImage?
    // CI-adjusted version of `image`, updated asynchronously when adjustments change
    @State private var adjustedImage: NSImage?
    @State private var histogram: Histogram?
    @State private var clippingMasks: ClippingAnalyzer.ClippingMasks?
    @State private var containerSize: CGSize = .zero
    @State private var dragStartCrop: CropRect?
    // True while the user holds the preview-original button or backtick key
    @State private var showingOriginalPreview = false

    private let handleSize: CGFloat = 12
    private let minCropSize: CGFloat = 50
    private let sidebarWidth: CGFloat = 260

    private var displayImage: NSImage? { adjustedImage ?? image }

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
        HStack(spacing: 0) {
            GeometryReader { geometry in
                ZStack {
                    Color.black

                    if showingOriginalPreview {
                        originalPreviewLayer
                    } else {
                        editLayer
                    }
                }
                .clipped()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(showingOriginalPreview ? nil : moveCropGesture())
                .onAppear { containerSize = geometry.size }
                .onChange(of: geometry.size) { _, size in containerSize = size }
            }

            EditSidebarPanel(
                preset: $preset,
                fineRotation: $fineRotation,
                adjustments: $adjustments,
                showingOriginalPreview: $showingOriginalPreview,
                histogram: histogram
            )
            .frame(width: sidebarWidth)
            .background(Color(NSColor.windowBackgroundColor))
        }
        // Backtick key (key code 50 on standard keyboards) — hold for original preview
        .background(
            HoldKeyMonitor(keyCode: 50, isPressed: $showingOriginalPreview)
        )
        .task(id: url) {
            cropRect = nil
            image = nil
            baseCGImage = nil
            adjustedImage = nil
            await loadImage()
            if let hint = initialCropHint, imageSize.width > 0, imageSize.height > 0 {
                let w = min(hint.width, imageSize.width)
                let h = min(hint.height, imageSize.height)
                let x = max(0, min(hint.x, imageSize.width - w))
                let y = max(0, min(hint.y, imageSize.height - h))
                cropRect = CropRect(x: x, y: y, width: w, height: h)
            } else {
                cropRect = CropRect.fill(imageSize: imageSize, aspectRatio: preset.ratio)
            }
        }
        .task(id: PreviewRenderKey(adjustments: adjustments, clipping: showClippingWarnings,
                                   hasImage: baseCGImage != nil)) {
            await renderAdjustmentPreview()
        }
        .onChange(of: preset)      { _, _ in adjustCropToPreset() }
        .onChange(of: fineRotation) { _, _ in clampCropToSafeBounds() }
    }

    // MARK: - Image layers

    @ViewBuilder
    private var originalPreviewLayer: some View {
        if let img = image {
            Image(nsImage: img)
                .resizable()
                .aspectRatio(contentMode: .fit)

            // "Original" badge
            VStack {
                HStack {
                    Text("ORIGINAL")
                        .font(.caption2.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.black.opacity(0.55))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .padding(10)
                    Spacer()
                }
                Spacer()
            }
        } else {
            ProgressView()
        }
    }

    /// The adjusted image with (optional) clipping masks stacked exactly on top of it
    @ViewBuilder
    private func adjustedImageStack(_ img: NSImage) -> some View {
        ZStack {
            Image(nsImage: img).resizable()
            if showClippingWarnings, let masks = clippingMasks {
                Image(nsImage: masks.highlights).resizable().opacity(0.85)
                Image(nsImage: masks.shadows).resizable().opacity(0.85)
            }
        }
        .aspectRatio(img.size, contentMode: .fit)
    }

    @ViewBuilder
    private var editLayer: some View {
        if let img = displayImage {
            adjustedImageStack(img)
                .rotationEffect(.degrees(fineRotation))

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

            if let crop = cropRect {
                let displayCrop = toDisplay(crop)
                let r = displayedImageRect
                adjustedImageStack(img)
                    .rotationEffect(.degrees(fineRotation))
                    .mask {
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

                Rectangle()
                    .stroke(Color.white, lineWidth: 2)
                    .frame(width: displayCrop.width, height: displayCrop.height)
                    .position(x: displayCrop.midX, y: displayCrop.midY)

                ruleOfThirdsGrid(displayCrop: displayCrop)
                cropHandles(displayCrop: displayCrop)
            }

            GuidingGridOverlay()
        } else {
            ProgressView()
        }
    }

    // MARK: - Adjustment preview

    /// Identity of one preview render; `.task(id:)` cancels the previous render when it changes,
    /// so a slow render can never overwrite a newer one.
    private struct PreviewRenderKey: Equatable {
        let adjustments: ImageAdjustments
        let clipping: Bool
        let hasImage: Bool
    }

    private func renderAdjustmentPreview() async {
        guard let base = baseCGImage else { return }
        // Coalesce rapid slider movement into one render per frame or so
        try? await Task.sleep(nanoseconds: 12_000_000)
        guard !Task.isCancelled else { return }

        let adj = adjustments
        let clipping = showClippingWarnings
        let result = await Task.detached(priority: .userInitiated) {
            Self.renderPreview(base, adjustments: adj, clipping: clipping)
        }.value
        guard !Task.isCancelled else { return }
        adjustedImage = adj.isIdentity ? image : NSImage(cgImage: result.image,
                                                          size: NSSize(width: result.image.width, height: result.image.height))
        histogram = result.histogram
        clippingMasks = result.masks
    }

    private struct PreviewRender: @unchecked Sendable {
        let image: CGImage
        let histogram: Histogram
        let masks: ClippingAnalyzer.ClippingMasks?
    }

    /// Apply adjustments to the preview-sized base image, plus its histogram and clipping masks.
    private nonisolated static func renderPreview(_ base: CGImage, adjustments: ImageAdjustments,
                                                  clipping: Bool) -> PreviewRender {
        var output = base
        if !adjustments.isIdentity {
            let space = base.colorSpace.flatMap { $0.model == .rgb ? $0 : nil }
                ?? CGColorSpace(name: CGColorSpace.sRGB)!
            let adjusted = adjustments.applyingCI(to: CIImage(cgImage: base), colorSpace: space, cubeDimension: 32)
            if let rendered = CIContext.shared.createCGImage(adjusted, from: adjusted.extent,
                                                             format: .RGBA8, colorSpace: space) {
                output = rendered
            }
        }
        return PreviewRender(image: output,
                             histogram: Histogram.compute(from: output),
                             masks: clipping ? ClippingAnalyzer.buildMasks(from: output) : nil)
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

    /// Largest centred axis-aligned rectangle that fits inside the image rotated by `degrees`.
    ///
    /// Derived by solving the two binding constraints simultaneously:
    ///   a·cos(θ) + b·sin(θ) = W/2   (right edge)
    ///   a·sin(θ) + b·cos(θ) = H/2   (top edge)
    /// giving  safeW = (W·c − H·s) / cos(2θ),  safeH = (H·c − W·s) / cos(2θ).
    private func safeCropBounds(for degrees: Double) -> CGRect {
        let radians = abs(degrees) * .pi / 180.0
        let c = cos(radians), s = sin(radians)
        let cos2 = cos(2 * radians)
        let W = imageSize.width, H = imageSize.height
        guard cos2 > 0.001 else { return CGRect(origin: .zero, size: imageSize) }
        let safeW = (W * c - H * s) / cos2
        let safeH = (H * c - W * s) / cos2
        guard safeW > 1, safeH > 1 else { return CGRect(origin: .zero, size: imageSize) }
        return CGRect(x: (W - safeW) / 2, y: (H - safeH) / 2, width: safeW, height: safeH)
    }

    // MARK: - Image loading

    /// Load a downscaled preview thumbnail (≤1500 px) and set `imageSize` to native pixel dimensions.
    /// `imageSize` stays at native resolution so crop coordinates remain correct.
    private func loadImage() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
                    DispatchQueue.main.async { continuation.resume() }
                    return
                }
                let orientation = source.exifOrientation

                var nativeSize: CGSize = .zero
                if let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                   let pw = props[kCGImagePropertyPixelWidth] as? CGFloat,
                   let ph = props[kCGImagePropertyPixelHeight] as? CGFloat {
                    switch orientation {
                    case .right, .left, .rightMirrored, .leftMirrored:
                        nativeSize = CGSize(width: ph, height: pw)
                    default:
                        nativeSize = CGSize(width: pw, height: ph)
                    }
                }

                let thumbOptions: [CFString: Any] = [
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceThumbnailMaxPixelSize: 1500
                ]

                if let thumbCG = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOptions as CFDictionary) {
                    let nsImage = NSImage(cgImage: thumbCG,
                                         size: NSSize(width: thumbCG.width, height: thumbCG.height))
                    let size = nativeSize.width > 0 ? nativeSize
                                                    : CGSize(width: thumbCG.width, height: thumbCG.height)
                    DispatchQueue.main.async {
                        self.image = nsImage
                        self.baseCGImage = thumbCG
                        self.imageSize = size
                        continuation.resume()
                    }
                } else {
                    // Fallback: full image with EXIF orientation applied
                    guard let raw = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                        DispatchQueue.main.async { continuation.resume() }
                        return
                    }
                    let cgImg = raw.applyingExifOrientation(orientation) ?? raw
                    let nsImage = NSImage(cgImage: cgImg,
                                         size: NSSize(width: cgImg.width, height: cgImg.height))
                    let size = nativeSize.width > 0 ? nativeSize
                                                    : CGSize(width: cgImg.width, height: cgImg.height)
                    DispatchQueue.main.async {
                        self.image = nsImage
                        self.baseCGImage = cgImg
                        self.imageSize = size
                        continuation.resume()
                    }
                }
            }
        }
    }
}

// MARK: - Hold-key monitor

/// Zero-size background view that tracks key-down and key-up for a single key code.
/// Sets `isPressed` to true while the key is held, false when released.
private struct HoldKeyMonitor: NSViewRepresentable {
    let keyCode: UInt16
    @Binding var isPressed: Bool

    func makeNSView(context: Context) -> HoldKeyNSView {
        let v = HoldKeyNSView()
        v.keyCode = keyCode
        v.onDown = { isPressed = true }
        v.onUp   = { isPressed = false }
        return v
    }

    func updateNSView(_ nsView: HoldKeyNSView, context: Context) {
        nsView.onDown = { isPressed = true }
        nsView.onUp   = { isPressed = false }
    }

    class HoldKeyNSView: NSView {
        var keyCode: UInt16 = 0
        var onDown: (() -> Void)?
        var onUp:   (() -> Void)?
        private var downMonitor: Any?
        private var upMonitor:   Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window != nil { install() } else { remove() }
        }

        private func install() {
            guard downMonitor == nil else { return }
            downMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, event.keyCode == self.keyCode, !event.isARepeat else { return event }
                DispatchQueue.main.async { self.onDown?() }
                return nil  // consume — prevents system beep
            }
            upMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyUp) { [weak self] event in
                guard let self, event.keyCode == self.keyCode else { return event }
                DispatchQueue.main.async { self.onUp?() }
                return nil
            }
        }

        private func remove() {
            if let m = downMonitor { NSEvent.removeMonitor(m); downMonitor = nil }
            if let m = upMonitor   { NSEvent.removeMonitor(m); upMonitor   = nil }
        }

        deinit { remove() }
    }
}

// MARK: - Edit sidebar

private struct EditSidebarPanel: View {
    @Binding var preset: CropPreset
    @Binding var fineRotation: Double
    @Binding var adjustments: ImageAdjustments
    @Binding var showingOriginalPreview: Bool
    let histogram: Histogram?

    var body: some View {
        VStack(spacing: 0) {
            HistogramView(histogram: histogram)
                .frame(height: 90)
                .padding([.horizontal, .top], 12)
                .padding(.bottom, 8)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    SidebarSection(title: "Crop") {
                        Picker("Aspect ratio", selection: $preset) {
                            ForEach(CropPreset.allCases) { p in
                                Text(p.rawValue).tag(p)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    SidebarSection(title: "Straighten") {
                        HStack(spacing: 8) {
                            Button { fineRotation = max(-15, fineRotation - 0.5) } label: {
                                Image(systemName: "rotate.left")
                            }
                            .buttonStyle(.borderless)
                            .help("−0.5°")
                            // No `step:` — on macOS that draws a tick mark per step (300 here)
                            Slider(value: Binding(get: { fineRotation },
                                                  set: { fineRotation = ($0 * 10).rounded() / 10 }),
                                   in: -15...15)
                            Button { fineRotation = min(15, fineRotation + 0.5) } label: {
                                Image(systemName: "rotate.right")
                            }
                            .buttonStyle(.borderless)
                            .help("+0.5°")
                        }
                        HStack {
                            Text(String(format: "%+.1f°", fineRotation))
                                .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                            Spacer()
                            Button("Reset") { fineRotation = 0 }
                                .buttonStyle(.borderless).font(.caption2)
                                .disabled(fineRotation == 0)
                        }
                    }

                    SidebarSection(title: "Light", onReset: resetLight, canReset: !lightIsIdentity) {
                        AdjustmentRow(label: "Exposure", value: $adjustments.exposure, range: -3...3,
                                      display: { String(format: "%+.2f", $0) },
                                      help: "Brightens or darkens in linear light like changing the shutter speed; highlights roll off instead of clipping")
                        AdjustmentRow(label: "Contrast", value: $adjustments.contrast,
                                      help: "S-curve around mid-grey; never clips")
                        AdjustmentRow(label: "Highlights", value: $adjustments.highlights,
                                      help: "Drag left to recover detail in bright areas, right to brighten them")
                        AdjustmentRow(label: "Shadows", value: $adjustments.shadows,
                                      help: "Drag right to open up dark areas (keeps their colour), left to deepen them")
                        AdjustmentRow(label: "Whites", value: $adjustments.whites,
                                      help: "Sets the white point")
                        AdjustmentRow(label: "Blacks", value: $adjustments.blacks,
                                      help: "Sets the black point")
                        AdjustmentRow(label: "Brightness", value: $adjustments.brightness,
                                      help: "Midtone gamma — keeps pure black and white fixed")
                    }

                    SidebarSection(title: "Color", onReset: resetColor, canReset: !colorIsIdentity) {
                        AdjustmentRow(label: "Temp", value: $adjustments.temperature,
                                      track: [.blue, .yellow], help: "White balance: cooler ↔ warmer")
                        AdjustmentRow(label: "Tint", value: $adjustments.tint,
                                      track: [.green, .pink], help: "White balance: green ↔ magenta")
                        AdjustmentRow(label: "Vibrance", value: $adjustments.vibrance,
                                      help: "Boosts muted colours more than already-saturated ones")
                        AdjustmentRow(label: "Saturation", value: $adjustments.saturation,
                                      help: "Uniform saturation")
                    }

                    Text("Double-click a slider's name to reset it.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(12)
            }

            Divider()

            HStack(spacing: 8) {
                // Original-preview button — hold to compare, release to return
                PreviewOriginalButton(isPressed: $showingOriginalPreview)
                Button("Reset All") { adjustments.reset(); fineRotation = 0 }
                    .disabled(adjustments.isIdentity && fineRotation == 0)
                    .help("Reset tone, colour and straighten")
            }
            .padding(12)
        }
    }

    private var lightIsIdentity: Bool {
        var a = adjustments
        a.temperature = 0; a.tint = 0; a.vibrance = 0; a.saturation = 0
        return a.isIdentity
    }

    private var colorIsIdentity: Bool {
        adjustments.temperature == 0 && adjustments.tint == 0 && adjustments.vibrance == 0 && adjustments.saturation == 0
    }

    private func resetLight() {
        let color = adjustments
        adjustments.reset()
        adjustments.temperature = color.temperature
        adjustments.tint = color.tint
        adjustments.vibrance = color.vibrance
        adjustments.saturation = color.saturation
    }

    private func resetColor() {
        adjustments.temperature = 0
        adjustments.tint = 0
        adjustments.vibrance = 0
        adjustments.saturation = 0
    }
}

// MARK: - Sidebar sub-views

private struct SidebarSection<Content: View>: View {
    let title: String
    var onReset: (() -> Void)? = nil
    var canReset: Bool = false
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title.uppercased())
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .tracking(1)
                Spacer()
                if let onReset {
                    Button("Reset", action: onReset)
                        .buttonStyle(.borderless)
                        .font(.caption2)
                        .disabled(!canReset)
                }
            }
            content()
        }
    }
}

/// Labelled slider for one adjustment. Values are shown ×100 (−100…+100) except where a custom
/// `display` is given (exposure in EV). Double-click the label to reset to 0.
private struct AdjustmentRow: View {
    let label: String
    @Binding var value: Double
    var range: ClosedRange<Double> = -1...1
    var display: (Double) -> String = { String(format: "%+.0f", $0 * 100) }
    var track: [Color]? = nil
    var help: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(value == 0 ? .secondary : .primary)
                Spacer()
                Text(value == 0 ? "0" : display(value))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { value = 0 }

            Slider(value: $value, in: range)
                .controlSize(.small)
                .background(alignment: .center) {
                    if let track {
                        LinearGradient(colors: track, startPoint: .leading, endPoint: .trailing)
                            .frame(height: 3)
                            .clipShape(Capsule())
                            .opacity(0.6)
                            .allowsHitTesting(false)
                    }
                }
        }
        .help(help)
    }
}

/// RGB + luminance histogram with highlight / shadow clipping indicators.
private struct HistogramView: View {
    let histogram: Histogram?

    var body: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.black.opacity(0.85))

            if let h = histogram, h.pixelCount > 0 {
                Canvas { ctx, size in
                    let peak = Self.peak(h)
                    func path(_ bins: [Int]) -> Path {
                        var p = Path()
                        p.move(to: CGPoint(x: 0, y: size.height))
                        for (i, count) in bins.enumerated() {
                            let x = CGFloat(i) / 255 * size.width
                            let y = size.height - min(1, CGFloat(count) / peak) * (size.height - 4)
                            p.addLine(to: CGPoint(x: x, y: y))
                        }
                        p.addLine(to: CGPoint(x: size.width, y: size.height))
                        p.closeSubpath()
                        return p
                    }
                    ctx.blendMode = .plusLighter
                    ctx.fill(path(h.red), with: .color(.red.opacity(0.55)))
                    ctx.fill(path(h.green), with: .color(.green.opacity(0.55)))
                    ctx.fill(path(h.blue), with: .color(.blue.opacity(0.6)))
                    ctx.blendMode = .normal
                    ctx.stroke(path(h.luminance), with: .color(.white.opacity(0.7)), lineWidth: 1)
                }
                .padding(.horizontal, 4)
                .clipShape(RoundedRectangle(cornerRadius: 6))

                HStack {
                    clipIndicator(fraction: h.shadowClipFraction, color: .blue, label: "Shadows clipped")
                    Spacer()
                    clipIndicator(fraction: h.highlightClipFraction, color: .red, label: "Highlights clipped")
                }
                .padding(5)
            } else {
                ProgressView().controlSize(.small).frame(maxHeight: .infinity)
            }
        }
        .accessibilityLabel("Histogram")
    }

    private func clipIndicator(fraction: Double, color: Color, label: String) -> some View {
        let clipped = fraction > 0.0005
        return Image(systemName: clipped ? "triangle.fill" : "triangle")
            .font(.system(size: 8))
            .foregroundStyle(clipped ? color : Color.white.opacity(0.35))
            .help(clipped ? "\(label): \(String(format: "%.1f", fraction * 100))% of pixels (W shows where)" : "No clipping")
    }

    /// Scale to a robust peak (ignoring the extreme end bins, which spike on clipped images)
    private static func peak(_ h: Histogram) -> CGFloat {
        let inner = (1..<255).map { max(h.red[$0], h.green[$0], h.blue[$0], h.luminance[$0]) }
        return CGFloat(max(inner.max() ?? 1, 1))
    }
}

/// Button that stays highlighted while held down. Activates `isPressed` via DragGesture
/// (which fires on press/release) and via the backtick key monitor on the parent view.
private struct PreviewOriginalButton: View {
    @Binding var isPressed: Bool

    var body: some View {
        HStack {
            Image(systemName: isPressed ? "photo.fill" : "photo")
                .font(.caption)
            Text(isPressed ? "Original" : "Preview Original")
                .font(.caption)
        }
        .foregroundStyle(isPressed ? Color.white : Color.primary)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 7)
        .background(isPressed ? Color.accentColor : Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.3), lineWidth: 1))
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded   { _ in isPressed = false }
        )
        .help("Hold to compare against the original  (\u{60})")
    }
}
