import SwiftUI
import AppKit
import CoreImage

/// Renders an image with optional transformations
struct ImageRenderer: View {
    let url: URL
    let rotation: Angle
    let showLoading: Bool

    @State private var image: NSImage?
    @State private var isLoading = true

    init(url: URL, rotation: Angle = .zero, showLoading: Bool = true) {
        self.url = url
        self.rotation = rotation
        self.showLoading = showLoading
    }

    var body: some View {
        Group {
            if let image = image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .rotationEffect(rotation)
            } else if isLoading && showLoading {
                ProgressView()
                    .scaleEffect(0.8)
            } else {
                Image(systemName: "photo")
                    .font(.largeTitle)
                    .foregroundColor(.secondary)
            }
        }
        .task(id: url) {
            await loadImage()
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

/// Renders a CIImage with transformations applied
struct CIImageRenderer: View {
    let ciImage: CIImage
    @State private var nsImage: NSImage?

    var body: some View {
        Group {
            if let image = nsImage {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                ProgressView()
            }
        }
        .task(id: ciImage) {
            await renderImage()
        }
    }

    private func renderImage() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let context = CIContext()
                if let cgImage = context.createCGImage(ciImage, from: ciImage.extent) {
                    let nsImage = NSImage(cgImage: cgImage, size: NSSize(
                        width: cgImage.width,
                        height: cgImage.height
                    ))
                    DispatchQueue.main.async {
                        self.nsImage = nsImage
                        continuation.resume()
                    }
                } else {
                    DispatchQueue.main.async {
                        continuation.resume()
                    }
                }
            }
        }
    }
}
