import SwiftUI

/// Single thumbnail cell in the gallery grid
struct GalleryThumbnail: View {
    @ObservedObject var asset: ImageAsset
    let isSelected: Bool

    @State private var image: NSImage?
    @State private var isLoading = true
    @State private var isHovering = false

    var body: some View {
        ZStack {
            Color(NSColor.controlBackgroundColor)

            // Thumbnail image — trashed photos are dimmed and desaturated so decisions read at a glance
            if let image = image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                    .clipped()
                    .saturation(asset.isTrashed ? 0 : 1)
                    .opacity(asset.isTrashed ? 0.4 : 1)
            } else if isLoading {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: "photo")
                    .foregroundColor(.secondary)
            }

            // Badges overlay
            ThumbnailBadges(asset: asset)
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .overlay(
            RoundedRectangle(cornerRadius: 5)
                .strokeBorder(isSelected ? Color.accentColor : Color.white.opacity(isHovering ? 0.35 : 0),
                              lineWidth: isSelected ? 3 : 1)
        )
        .shadow(color: isSelected ? Color.accentColor.opacity(0.35) : .clear, radius: 4)
        .onHover { isHovering = $0 }
        .help(asset.displayName)
        .task(id: asset.thumbnailVersion) {
            await loadThumbnail()
        }
    }

    private func loadThumbnail() async {
        let pipeline = ImagePipeline.shared
        if let cached = pipeline.cachedImage(for: asset.displayURL, tier: .thumbnail) {
            image = cached
            isLoading = false
            return
        }
        isLoading = true
        let loaded = await pipeline.image(for: asset.displayURL, tier: .thumbnail)
        guard !Task.isCancelled else { return }
        image = loaded
        isLoading = false
    }
}

/// Thumbnail with loading state for async contexts
struct AsyncThumbnail: View {
    let url: URL
    let size: CGFloat
    var reloadToken: Int = 0

    @State private var image: NSImage?
    @State private var isLoading = true

    var body: some View {
        Group {
            if let image = image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else if isLoading {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: "photo")
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: size, maxHeight: size)
        .task(id: "\(url.path)#\(reloadToken)") {
            await loadThumbnail()
        }
    }

    private func loadThumbnail() async {
        let pipeline = ImagePipeline.shared
        if let cached = pipeline.cachedImage(for: url, tier: .thumbnail) {
            image = cached
            isLoading = false
            return
        }
        isLoading = true
        let loaded = await pipeline.image(for: url, tier: .thumbnail)
        guard !Task.isCancelled else { return }
        image = loaded
        isLoading = false
    }
}
