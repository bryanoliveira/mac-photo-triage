import Foundation
import AppKit
import SwiftUI
import CoreGraphics
import ImageIO

/// Cached image data
struct CachedImage {
    let image: NSImage
    let size: CGSize
    let loadedAt: Date
}

/// Async image loading and thumbnail caching service
@MainActor
final class ImageLoader: ObservableObject {
    /// Thumbnail size
    static let thumbnailSize: CGFloat = 256

    /// Maximum full-resolution images in memory
    private static let maxFullResImages = 4

    /// Thumbnail cache directory URL
    private let thumbnailCacheURL: URL?

    /// In-memory thumbnail cache
    private var thumbnailCache: [URL: NSImage] = [:]

    /// In-memory full-res cache (limited size)
    private var fullResCache: [URL: CachedImage] = [:]
    private var fullResCacheOrder: [URL] = []

    /// Loading state for URLs
    @Published var loadingURLs: Set<URL> = []

    init(folderURL: URL? = nil) {
        if let folder = folderURL {
            thumbnailCacheURL = folder.appendingPathComponent(".photo-triage-thumbs")
            createThumbnailDirectory()
        } else {
            thumbnailCacheURL = nil
        }
    }

    // MARK: - Thumbnail Loading

    /// Load thumbnail for an image (cached)
    func loadThumbnail(for url: URL) async -> NSImage? {
        // Check in-memory cache
        if let cached = thumbnailCache[url] {
            return cached
        }

        // Check disk cache
        if let diskCached = loadThumbnailFromDisk(for: url) {
            thumbnailCache[url] = diskCached
            return diskCached
        }

        // Generate thumbnail
        loadingURLs.insert(url)
        defer { loadingURLs.remove(url) }

        let thumbnail = await generateThumbnail(for: url)

        if let thumbnail = thumbnail {
            thumbnailCache[url] = thumbnail
            saveThumbnailToDisk(thumbnail, for: url)
        }

        return thumbnail
    }

    /// Generate a thumbnail image
    private func generateThumbnail(for url: URL) async -> NSImage? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let options: [CFString: Any] = [
                    kCGImageSourceThumbnailMaxPixelSize: Self.thumbnailSize,
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true
                ]

                guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                      let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
                    continuation.resume(returning: nil)
                    return
                }

                let nsImage = NSImage(cgImage: cgImage, size: NSSize(
                    width: cgImage.width,
                    height: cgImage.height
                ))

                continuation.resume(returning: nsImage)
            }
        }
    }

    // MARK: - Full Resolution Loading

    /// Load full resolution image
    func loadFullResolution(for url: URL) async -> NSImage? {
        // Check cache
        if let cached = fullResCache[url] {
            return cached.image
        }

        loadingURLs.insert(url)
        defer { loadingURLs.remove(url) }

        let image = await loadImageAsync(url)

        if let image = image {
            cacheFullRes(image, for: url)
        }

        return image
    }

    /// Load image asynchronously
    private func loadImageAsync(_ url: URL) async -> NSImage? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                // Use ImageIO for better RAW support
                guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
                    continuation.resume(returning: nil)
                    return
                }

                let options: [CFString: Any] = [
                    kCGImageSourceShouldCache: false
                ]

                guard let cgImage = CGImageSourceCreateImageAtIndex(source, 0, options as CFDictionary) else {
                    continuation.resume(returning: nil)
                    return
                }

                let nsImage = NSImage(cgImage: cgImage, size: NSSize(
                    width: cgImage.width,
                    height: cgImage.height
                ))

                continuation.resume(returning: nsImage)
            }
        }
    }

    /// Prefetch adjacent images
    func prefetch(urls: [URL]) {
        for url in urls {
            Task {
                _ = await loadFullResolution(for: url)
            }
        }
    }

    // MARK: - Cache Management

    private func cacheFullRes(_ image: NSImage, for url: URL) {
        // Evict oldest if at capacity
        while fullResCacheOrder.count >= Self.maxFullResImages {
            if let oldestURL = fullResCacheOrder.first {
                fullResCache.removeValue(forKey: oldestURL)
                fullResCacheOrder.removeFirst()
            }
        }

        fullResCache[url] = CachedImage(
            image: image,
            size: image.size,
            loadedAt: Date()
        )
        fullResCacheOrder.append(url)
    }

    func clearCache() {
        thumbnailCache.removeAll()
        fullResCache.removeAll()
        fullResCacheOrder.removeAll()
    }

    // MARK: - Disk Cache

    private func createThumbnailDirectory() {
        guard let cacheURL = thumbnailCacheURL else { return }
        try? FileManager.default.createDirectory(
            at: cacheURL,
            withIntermediateDirectories: true
        )
    }

    private func thumbnailCachePath(for url: URL) -> URL? {
        guard let cacheURL = thumbnailCacheURL else { return nil }
        let filename = url.lastPathComponent + ".thumb.jpg"
        return cacheURL.appendingPathComponent(filename)
    }

    private func loadThumbnailFromDisk(for url: URL) -> NSImage? {
        guard let cachePath = thumbnailCachePath(for: url),
              FileManager.default.fileExists(atPath: cachePath.path) else {
            return nil
        }

        // Check if source file is newer than cached thumbnail
        let sourceAttrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        let cacheAttrs = try? FileManager.default.attributesOfItem(atPath: cachePath.path)

        if let sourceDate = sourceAttrs?[.modificationDate] as? Date,
           let cacheDate = cacheAttrs?[.modificationDate] as? Date,
           sourceDate > cacheDate {
            // Source is newer, invalidate cache
            return nil
        }

        return NSImage(contentsOf: cachePath)
    }

    private func saveThumbnailToDisk(_ image: NSImage, for url: URL) {
        guard let cachePath = thumbnailCachePath(for: url) else { return }

        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) else {
            return
        }

        try? jpegData.write(to: cachePath)
    }
}

// MARK: - SwiftUI Image View

/// Async image loading view
struct AsyncImageView: View {
    let url: URL
    let contentMode: ContentMode
    @State private var image: NSImage?
    @State private var isLoading = true

    var body: some View {
        Group {
            if let image = image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else if isLoading {
                ProgressView()
                    .scaleEffect(0.5)
            } else {
                Image(systemName: "photo")
                    .foregroundColor(.secondary)
            }
        }
        .task {
            await loadImage()
        }
    }

    private func loadImage() async {
        isLoading = true
        defer { isLoading = false }

        // Generate thumbnail inline for simplicity
        let options: [CFString: Any] = [
            kCGImageSourceThumbnailMaxPixelSize: 256,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]

        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return
        }

        let nsImage = NSImage(cgImage: cgImage, size: NSSize(
            width: cgImage.width,
            height: cgImage.height
        ))

        await MainActor.run {
            self.image = nsImage
        }
    }
}
