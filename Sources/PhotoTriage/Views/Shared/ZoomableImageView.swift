import SwiftUI
import AppKit

/// A view that displays an image with pan and zoom capabilities
struct ZoomableImageView: View {
    let url: URL
    var showClippingWarnings: Bool = false
    /// Increment to force a reload from disk (e.g. after crop undo/redo)
    var reloadToken: Int = 0
    /// Increment to reset zoom/pan to fit-to-window without reloading the image
    var resetZoomToken: Int = 0

    @State private var image: NSImage?
    @State private var isLoading = true

    // Zoom state
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0

    // Pan state
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    // Fit state
    @State private var isFitToWindow = true
    @State private var imageSize: CGSize = .zero

    private let minScale: CGFloat = 0.1
    private let maxScale: CGFloat = 10.0

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if let image = image {
                    ZStack {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                        if showClippingWarnings {
                            ClippingOverlay(url: url)
                        }
                    }
                    .scaleEffect(effectiveScale(in: geometry.size))
                    .offset(offset)
                    .gesture(dragGesture)
                    .gesture(magnificationGesture)
                    .onTapGesture(count: 2) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            toggleZoom(in: geometry.size)
                        }
                    }
                    .onAppear {
                        imageSize = image.size
                    }
                } else if isLoading {
                    ProgressView()
                } else {
                    Image(systemName: "photo")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
            .clipped()
        }
        .task(id: "\(url.absoluteString)-\(reloadToken)") {
            await loadImage()
        }
        .onChange(of: resetZoomToken) { _, _ in resetZoom() }
    }

    private func effectiveScale(in containerSize: CGSize) -> CGFloat {
        if isFitToWindow {
            return 1.0  // SwiftUI's .fit handles this
        }
        return scale
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                guard !isFitToWindow else { return }
                offset = CGSize(
                    width: lastOffset.width + value.translation.width,
                    height: lastOffset.height + value.translation.height
                )
            }
            .onEnded { _ in
                lastOffset = offset
            }
    }

    private var magnificationGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                isFitToWindow = false
                let newScale = lastScale * value
                scale = min(max(newScale, minScale), maxScale)
            }
            .onEnded { _ in
                lastScale = scale
            }
    }

    private func toggleZoom(in containerSize: CGSize) {
        if isFitToWindow {
            // Zoom to 100%
            isFitToWindow = false
            scale = 1.0
            lastScale = 1.0
            offset = .zero
            lastOffset = .zero
        } else {
            // Fit to window
            isFitToWindow = true
            scale = 1.0
            lastScale = 1.0
            offset = .zero
            lastOffset = .zero
        }
    }

    /// Reset zoom and pan
    func resetZoom() {
        isFitToWindow = true
        scale = 1.0
        lastScale = 1.0
        offset = .zero
        lastOffset = .zero
    }

    private func loadImage() async {
        isLoading = true
        defer { isLoading = false }

        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let loaded = NSImage(contentsOf: url)
                DispatchQueue.main.async {
                    self.image = loaded
                    continuation.resume()
                }
            }
        }
    }
}

/// Zoomable image view with external zoom control
struct ControlledZoomableImageView: View {
    let url: URL
    @Binding var scale: CGFloat
    @Binding var offset: CGSize
    @Binding var isFitToWindow: Bool
    var showClippingWarnings: Bool = false

    @State private var image: NSImage?
    @State private var isLoading = true
    @State private var lastScale: CGFloat = 1.0
    @State private var lastOffset: CGSize = .zero

    private let minScale: CGFloat = 0.1
    private let maxScale: CGFloat = 10.0

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if let image = image {
                    ZStack {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                        if showClippingWarnings {
                            ClippingOverlay(url: url)
                        }
                    }
                    .scaleEffect(isFitToWindow ? 1.0 : scale)
                    .offset(offset)
                    .gesture(dragGesture)
                    .gesture(magnificationGesture)
                    .onTapGesture(count: 2) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            toggleZoom()
                        }
                    }
                } else if isLoading {
                    ProgressView()
                } else {
                    Image(systemName: "photo")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
            .clipped()
        }
        .task(id: url) {
            await loadImage()
        }
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                guard !isFitToWindow else { return }
                offset = CGSize(
                    width: lastOffset.width + value.translation.width,
                    height: lastOffset.height + value.translation.height
                )
            }
            .onEnded { _ in
                lastOffset = offset
            }
    }

    private var magnificationGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                isFitToWindow = false
                let newScale = lastScale * value
                scale = min(max(newScale, minScale), maxScale)
            }
            .onEnded { _ in
                lastScale = scale
            }
    }

    private func toggleZoom() {
        if isFitToWindow {
            isFitToWindow = false
            scale = 1.0
            lastScale = 1.0
            offset = .zero
            lastOffset = .zero
        } else {
            isFitToWindow = true
            scale = 1.0
            lastScale = 1.0
            offset = .zero
            lastOffset = .zero
        }
    }

    private func loadImage() async {
        isLoading = true
        defer { isLoading = false }

        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let loaded = NSImage(contentsOf: url)
                DispatchQueue.main.async {
                    self.image = loaded
                    continuation.resume()
                }
            }
        }
    }
}
