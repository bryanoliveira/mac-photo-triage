import SwiftUI

/// Crop overlay with draggable handles
struct CropOverlay: View {
    let url: URL
    @Binding var cropRect: CropRect?
    let preset: CropPreset
    @Binding var imageSize: CGSize

    @State private var image: NSImage?
    @State private var displayedImageRect: CGRect = .zero

    private let handleSize: CGFloat = 12
    private let minCropSize: CGFloat = 50

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background image (dimmed)
                if let image = image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .overlay(Color.black.opacity(0.5))
                        .background(
                            GeometryReader { imageGeometry in
                                Color.clear.onAppear {
                                    calculateDisplayedImageRect(in: geometry.size, imageSize: image.size)
                                }
                            }
                        )

                    // Crop rectangle
                    if let crop = cropRect {
                        cropRectangleView(crop: crop, containerSize: geometry.size)
                    }
                } else {
                    ProgressView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .task(id: url) {
            await loadImage()
            initializeCropRect()
        }
        .onChange(of: preset) { _, _ in
            adjustCropToPreset()
        }
    }

    @ViewBuilder
    private func cropRectangleView(crop: CropRect, containerSize: CGSize) -> some View {
        let displayCrop = convertToDisplayCoordinates(crop)

        ZStack {
            // Clear crop area (shows through)
            if let image = image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .mask(
                        Rectangle()
                            .frame(width: displayCrop.width, height: displayCrop.height)
                            .position(x: displayCrop.x + displayCrop.width / 2,
                                     y: displayCrop.y + displayCrop.height / 2)
                    )
            }

            // Border
            Rectangle()
                .stroke(Color.white, lineWidth: 2)
                .frame(width: displayCrop.width, height: displayCrop.height)
                .position(x: displayCrop.x + displayCrop.width / 2,
                         y: displayCrop.y + displayCrop.height / 2)

            // Rule of thirds grid
            ruleOfThirdsGrid(displayCrop: displayCrop)

            // Drag handles
            cropHandles(displayCrop: displayCrop)
        }
        .gesture(
            DragGesture()
                .onChanged { value in
                    moveCropRect(by: value.translation)
                }
        )
    }

    @ViewBuilder
    private func ruleOfThirdsGrid(displayCrop: CropRect) -> some View {
        let thirdWidth = displayCrop.width / 3
        let thirdHeight = displayCrop.height / 3

        ZStack {
            // Vertical lines
            ForEach(1..<3, id: \.self) { i in
                Rectangle()
                    .fill(Color.white.opacity(0.5))
                    .frame(width: 1, height: displayCrop.height)
                    .position(
                        x: displayCrop.x + thirdWidth * CGFloat(i),
                        y: displayCrop.y + displayCrop.height / 2
                    )
            }

            // Horizontal lines
            ForEach(1..<3, id: \.self) { i in
                Rectangle()
                    .fill(Color.white.opacity(0.5))
                    .frame(width: displayCrop.width, height: 1)
                    .position(
                        x: displayCrop.x + displayCrop.width / 2,
                        y: displayCrop.y + thirdHeight * CGFloat(i)
                    )
            }
        }
    }

    @ViewBuilder
    private func cropHandles(displayCrop: CropRect) -> some View {
        let corners: [(CGFloat, CGFloat, String)] = [
            (0, 0, "topLeft"),
            (displayCrop.width, 0, "topRight"),
            (0, displayCrop.height, "bottomLeft"),
            (displayCrop.width, displayCrop.height, "bottomRight")
        ]

        ForEach(corners, id: \.2) { corner in
            Circle()
                .fill(Color.white)
                .frame(width: handleSize, height: handleSize)
                .position(
                    x: displayCrop.x + corner.0,
                    y: displayCrop.y + corner.1
                )
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            resizeCropRect(corner: corner.2, translation: value.translation)
                        }
                )
        }
    }

    // MARK: - Coordinate Conversion

    private func calculateDisplayedImageRect(in containerSize: CGSize, imageSize: CGSize) {
        let containerAspect = containerSize.width / containerSize.height
        let imageAspect = imageSize.width / imageSize.height

        var displayWidth: CGFloat
        var displayHeight: CGFloat

        if imageAspect > containerAspect {
            displayWidth = containerSize.width
            displayHeight = containerSize.width / imageAspect
        } else {
            displayHeight = containerSize.height
            displayWidth = containerSize.height * imageAspect
        }

        let x = (containerSize.width - displayWidth) / 2
        let y = (containerSize.height - displayHeight) / 2

        displayedImageRect = CGRect(x: x, y: y, width: displayWidth, height: displayHeight)
        self.imageSize = imageSize
    }

    private func convertToDisplayCoordinates(_ crop: CropRect) -> CropRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return crop }

        let scaleX = displayedImageRect.width / imageSize.width
        let scaleY = displayedImageRect.height / imageSize.height

        return CropRect(
            x: displayedImageRect.minX + crop.x * scaleX,
            y: displayedImageRect.minY + crop.y * scaleY,
            width: crop.width * scaleX,
            height: crop.height * scaleY
        )
    }

    private func convertToImageCoordinates(_ displayCrop: CropRect) -> CropRect {
        guard displayedImageRect.width > 0, displayedImageRect.height > 0 else { return displayCrop }

        let scaleX = imageSize.width / displayedImageRect.width
        let scaleY = imageSize.height / displayedImageRect.height

        return CropRect(
            x: (displayCrop.x - displayedImageRect.minX) * scaleX,
            y: (displayCrop.y - displayedImageRect.minY) * scaleY,
            width: displayCrop.width * scaleX,
            height: displayCrop.height * scaleY
        )
    }

    // MARK: - Crop Operations

    private func initializeCropRect() {
        cropRect = CropRect.fill(imageSize: imageSize, aspectRatio: preset.ratio)
    }

    private func adjustCropToPreset() {
        guard var crop = cropRect else { return }
        crop.constrain(to: preset.ratio, within: imageSize)
        cropRect = crop
    }

    private func moveCropRect(by translation: CGSize) {
        guard var crop = cropRect else { return }

        let scaleX = imageSize.width / displayedImageRect.width
        let scaleY = imageSize.height / displayedImageRect.height

        crop.x += translation.width * scaleX
        crop.y += translation.height * scaleY

        // Clamp to bounds
        crop.x = max(0, min(crop.x, imageSize.width - crop.width))
        crop.y = max(0, min(crop.y, imageSize.height - crop.height))

        cropRect = crop
    }

    private func resizeCropRect(corner: String, translation: CGSize) {
        guard var crop = cropRect else { return }

        let scaleX = imageSize.width / displayedImageRect.width
        let scaleY = imageSize.height / displayedImageRect.height

        let dx = translation.width * scaleX
        let dy = translation.height * scaleY

        switch corner {
        case "topLeft":
            crop.x += dx
            crop.y += dy
            crop.width -= dx
            crop.height -= dy
        case "topRight":
            crop.y += dy
            crop.width += dx
            crop.height -= dy
        case "bottomLeft":
            crop.x += dx
            crop.width -= dx
            crop.height += dy
        case "bottomRight":
            crop.width += dx
            crop.height += dy
        default:
            break
        }

        // Enforce minimum size
        crop.width = max(minCropSize, crop.width)
        crop.height = max(minCropSize, crop.height)

        // Enforce aspect ratio if needed
        if let ratio = preset.ratio {
            crop.height = crop.width / ratio
        }

        // Clamp to bounds
        crop.x = max(0, min(crop.x, imageSize.width - crop.width))
        crop.y = max(0, min(crop.y, imageSize.height - crop.height))

        cropRect = crop
    }

    // MARK: - Image Loading

    private func loadImage() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let loaded = NSImage(contentsOf: url)
                DispatchQueue.main.async {
                    self.image = loaded
                    if let size = loaded?.size {
                        self.imageSize = size
                    }
                    continuation.resume()
                }
            }
        }
    }
}
