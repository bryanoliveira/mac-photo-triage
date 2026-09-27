import Foundation
import AppKit
import ImageIO

/// Decodes images off the main thread (EXIF orientation applied) and keeps recently used
/// results in memory, so stepping through photos is instant once neighbours are prefetched.
///
/// Three tiers are used:
/// - **thumbnail** (≤ 512 px) for gallery cells and the detail panel
/// - **screen** (≈ screen size) for fit-to-window display in Preview / Triage
/// - **full** (native resolution) loaded on demand when the user zooms past screen resolution
///
/// `NSImage(contentsOf:)` — the previous approach — decodes lazily *on the main thread* at
/// first draw, which caused a visible stall on every navigation for large camera JPEGs.
final class ImagePipeline: @unchecked Sendable {
    static let shared = ImagePipeline()

    enum Tier: Hashable {
        case thumbnail
        case screen
        case full

        var maxPixel: Int? {
            switch self {
            case .thumbnail: return 512
            case .screen:    return ImagePipeline.screenMaxPixel
            case .full:      return nil
            }
        }
    }

    /// Long-edge pixel size for the screen tier: the main screen's size in pixels, clamped.
    static let screenMaxPixel: Int = {
        let screens = NSScreen.screens
        let longest = screens.map { max($0.frame.width, $0.frame.height) * $0.backingScaleFactor }.max() ?? 2560
        return Int(min(max(longest, 2048), 5120))
    }()

    private let thumbnails = NSCache<NSString, NSImage>()
    private let large = NSCache<NSString, NSImage>()
    private let lock = NSLock()
    private var versions: [URL: Int] = [:]
    private var inflight: [String: Task<NSImage?, Never>] = [:]
    private var pixelSizes: [URL: CGSize] = [:]

    init() {
        thumbnails.totalCostLimit = 256 * 1024 * 1024
        large.totalCostLimit = 900 * 1024 * 1024
    }

    // MARK: - Public API

    /// Synchronously return a cached image, if present (used to avoid a loading flash).
    func cachedImage(for url: URL, tier: Tier) -> NSImage? {
        let key = cacheKey(url, tier)
        return cache(for: tier).object(forKey: key as NSString)
    }

    /// Load (or fetch from cache) the image for `url` at `tier`. Concurrent requests for the
    /// same image share a single decode.
    func image(for url: URL, tier: Tier) async -> NSImage? {
        let key = cacheKey(url, tier)
        if let hit = cache(for: tier).object(forKey: key as NSString) { return hit }

        let task: Task<NSImage?, Never> = lock.withLock {
            if let existing = inflight[key] { return existing }
            let t = Task.detached(priority: tier == .full ? .userInitiated : .utility) { [weak self] () -> NSImage? in
                guard let self else { return nil }
                let decoded = Self.decode(url: url, maxPixel: tier.maxPixel)
                if let img = decoded {
                    let cost = Int(img.size.width * img.size.height * 4)
                    // Only cache if the file wasn't edited while we were decoding
                    if self.cacheKey(url, tier) == key {
                        self.cache(for: tier).setObject(img, forKey: key as NSString, cost: cost)
                    }
                }
                self.lock.withLock { _ = self.inflight.removeValue(forKey: key) }
                return decoded
            }
            inflight[key] = t
            return t
        }
        return await task.value
    }

    /// Warm the cache for images the user is likely to view next.
    func prefetch(_ urls: [URL], tier: Tier = .screen) {
        for url in urls where cachedImage(for: url, tier: tier) == nil {
            Task.detached(priority: .background) { [weak self] in
                _ = await self?.image(for: url, tier: tier)
            }
        }
    }

    /// Drop every cached tier for `url` (call after the file is modified on disk).
    func invalidate(_ url: URL) {
        lock.withLock {
            versions[url, default: 0] += 1
            pixelSizes.removeValue(forKey: url)
        }
    }

    /// Display-oriented pixel dimensions (EXIF orientation applied), read from metadata only.
    func pixelSize(for url: URL) -> CGSize? {
        if let cached = lock.withLock({ pixelSizes[url] }) { return cached }
        guard let size = Self.orientedPixelSize(url: url) else { return nil }
        lock.withLock { pixelSizes[url] = size }
        return size
    }

    // MARK: - Decoding

    /// Decode `url` with EXIF orientation applied, downsampled so the long edge ≤ `maxPixel`
    /// (nil = native resolution). Forces an immediate decode so drawing never blocks.
    static func decode(url: URL, maxPixel: Int?) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let native = orientedPixelSize(source: source)
        let nativeLong = native.map { Int(max($0.width, $0.height)) }
        let target = min(maxPixel ?? Int.max, nativeLong ?? maxPixel ?? 8192)

        let options: [CFString: Any] = [
            kCGImageSourceThumbnailMaxPixelSize: target,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }

    static func orientedPixelSize(url: URL) -> CGSize? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return orientedPixelSize(source: source)
    }

    private static func orientedPixelSize(source: CGImageSource) -> CGSize? {
        guard let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? CGFloat,
              let h = props[kCGImagePropertyPixelHeight] as? CGFloat else { return nil }
        switch source.exifOrientation {
        case .left, .right, .leftMirrored, .rightMirrored: return CGSize(width: h, height: w)
        default: return CGSize(width: w, height: h)
        }
    }

    // MARK: - Private

    private func cache(for tier: Tier) -> NSCache<NSString, NSImage> {
        tier == .thumbnail ? thumbnails : large
    }

    private func cacheKey(_ url: URL, _ tier: Tier) -> String {
        let version = lock.withLock { versions[url] ?? 0 }
        return "\(url.path)#\(tier)#\(version)"
    }
}
