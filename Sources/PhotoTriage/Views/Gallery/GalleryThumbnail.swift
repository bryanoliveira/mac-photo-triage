import SwiftUI

/// Single thumbnail cell in the gallery grid
struct GalleryThumbnail: View {
    @ObservedObject var asset: ImageAsset
    let isSelected: Bool

    @State private var image: NSImage?
    @State private var isLoading = true

    var body: some View {
        ZStack {
            // Thumbnail image
            if let image = image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                    .clipped()
            } else if isLoading {
                ProgressView()
                    .scaleEffect(0.5)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(NSColor.controlBackgroundColor))
            } else {
                Image(systemName: "photo")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(NSColor.controlBackgroundColor))
            }

            // Badges overlay
            ThumbnailBadges(asset: asset)
        }
        .aspectRatio(1, contentMode: .fit)
        .cornerRadius(4)
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 3)
        )
        .shadow(color: isSelected ? Color.accentColor.opacity(0.3) : .clear, radius: 4)
        .task(id: asset.displayURL) {
            await loadThumbnail()
        }
    }

    private func loadThumbnail() async {
        isLoading = true
        defer { isLoading = false }

        let options: [CFString: Any] = [
            kCGImageSourceThumbnailMaxPixelSize: 256,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]

        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                guard let source = CGImageSourceCreateWithURL(asset.displayURL as CFURL, nil),
                      let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
                    DispatchQueue.main.async {
                        continuation.resume()
                    }
                    return
                }

                let nsImage = NSImage(cgImage: cgImage, size: NSSize(
                    width: cgImage.width,
                    height: cgImage.height
                ))

                DispatchQueue.main.async {
                    self.image = nsImage
                    continuation.resume()
                }
            }
        }
    }
}

/// Thumbnail with loading state for async contexts
struct AsyncThumbnail: View {
    let url: URL
    let size: CGFloat

    @State private var image: NSImage?
    @State private var isLoading = true

    var body: some View {
        Group {
            if let image = image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else if isLoading {
                ProgressView()
                    .scaleEffect(0.5)
            } else {
                Image(systemName: "photo")
                    .foregroundColor(.secondary)
            }
        }
        .frame(width: size, height: size)
        .background(Color(NSColor.controlBackgroundColor))
        .clipped()
        .task(id: url) {
            await loadThumbnail()
        }
    }

    private func loadThumbnail() async {
        isLoading = true
        defer { isLoading = false }

        let options: [CFString: Any] = [
            kCGImageSourceThumbnailMaxPixelSize: size * 2,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]

        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                      let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
                    DispatchQueue.main.async {
                        continuation.resume()
                    }
                    return
                }

                let nsImage = NSImage(cgImage: cgImage, size: NSSize(
                    width: cgImage.width,
                    height: cgImage.height
                ))

                DispatchQueue.main.async {
                    self.image = nsImage
                    continuation.resume()
                }
            }
        }
    }
}
