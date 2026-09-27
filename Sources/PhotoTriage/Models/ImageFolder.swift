import Foundation
import Combine

/// Filter options for gallery view
enum ImageFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case unreviewed = "Unreviewed"
    case kept = "Kept"
    case trashed = "Trashed"
    case favorites = "Favorites"

    var id: String { rawValue }
}

/// Sort options for gallery view
enum ImageSort: String, CaseIterable, Identifiable {
    case dateAscending = "Date ↑"
    case dateDescending = "Date ↓"
    case nameAscending = "Name ↑"
    case nameDescending = "Name ↓"

    var id: String { rawValue }
}

/// Represents a loaded folder of images
@MainActor
final class ImageFolder: ObservableObject {
    /// Folder URL
    let folderURL: URL

    /// All image assets in the folder
    @Published private(set) var images: [ImageAsset] = []

    /// Current filter
    @Published var filter: ImageFilter = .all

    /// Current sort
    @Published var sort: ImageSort = .dateAscending

    /// Loading state
    @Published private(set) var isLoading = false

    /// Scanning progress (0.0 - 1.0)
    @Published private(set) var scanProgress: Double = 0

    /// Error message if scan failed
    @Published var errorMessage: String?

    /// Database path for this folder
    var databaseURL: URL {
        folderURL.appendingPathComponent(".photo-triage.db")
    }

    /// Thumbnail cache directory
    var thumbnailCacheURL: URL {
        folderURL.appendingPathComponent(".photo-triage-thumbs")
    }

    /// Filtered and sorted images for display
    var filteredImages: [ImageAsset] {
        let filtered: [ImageAsset]

        switch filter {
        case .all:
            filtered = images
        case .unreviewed:
            filtered = images.filter { !$0.isReviewed }
        case .kept:
            filtered = images.filter { $0.isKept }
        case .trashed:
            filtered = images.filter { $0.isTrashed }
        case .favorites:
            filtered = images.filter { $0.isFavorite }
        }

        return sortImages(filtered)
    }

    /// Every image (ignoring the filter) in the current sort order — the order triage walks through
    var sortedImages: [ImageAsset] {
        sortImages(images)
    }

    /// Images available for triage (not yet reviewed, not trashed)
    var triageableImages: [ImageAsset] {
        images.filter { !$0.isReviewed && !$0.isTrashed }
    }

    /// Count of images in each state
    var statistics: FolderStatistics {
        FolderStatistics(
            total: images.count,
            reviewed: images.filter { $0.isReviewed }.count,
            kept: images.filter { $0.isKept }.count,
            trashed: images.filter { $0.isTrashed }.count,
            favorites: images.filter { $0.isFavorite }.count
        )
    }

    init(folderURL: URL) {
        self.folderURL = folderURL
    }

    /// Scan the folder for images
    func scan() async {
        isLoading = true
        scanProgress = 0
        errorMessage = nil

        do {
            let scannedImages = try await scanFolder()
            images = scannedImages
            scanProgress = 1.0
        } catch {
            errorMessage = "Failed to scan folder: \(error.localizedDescription)"
        }

        isLoading = false
    }

    /// Refresh sentinel states for all images
    func refreshStates() {
        for image in images {
            image.refreshState()
        }
    }

    /// Find an asset by display URL
    func asset(for url: URL) -> ImageAsset? {
        images.first { $0.displayURL == url }
    }

    /// Find an asset by ID
    func asset(withID id: UUID) -> ImageAsset? {
        images.first { $0.id == id }
    }

    /// Get index of an asset
    func index(of asset: ImageAsset) -> Int? {
        filteredImages.firstIndex { $0.id == asset.id }
    }

    // MARK: - Private

    private func scanFolder() async throws -> [ImageAsset] {
        let fileManager = FileManager.default

        guard fileManager.fileExists(atPath: folderURL.path) else {
            throw ImageFolderError.folderNotFound
        }

        // Get all files in folder
        let contents = try fileManager.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        // Filter to supported image files
        let imageFiles = contents.filter { $0.isSupportedImage }

        // Group by stem for RAW+JPEG pairing
        var stemGroups: [String: [URL]] = [:]
        for url in imageFiles {
            let stem = url.stem
            stemGroups[stem, default: []].append(url)
        }

        // Create assets from groups
        var assets: [ImageAsset] = []
        let totalGroups = Double(stemGroups.count)
        var processed = 0.0

        for (_, urls) in stemGroups {
            let asset = createAsset(from: urls)
            assets.append(asset)

            processed += 1
            await MainActor.run {
                scanProgress = processed / totalGroups
            }
        }

        // Read EXIF up front (metadata only — no pixel decode) so capture-time sorting is
        // correct from the first frame instead of reshuffling once background loading finishes.
        let urls = assets.map(\.displayURL)
        let metadata = await Task.detached(priority: .userInitiated) { () -> [EXIFMetadata] in
            // Each iteration writes only its own slot, so concurrent access is safe
            nonisolated(unsafe) var results = [EXIFMetadata](repeating: EXIFMetadata(), count: urls.count)
            let lock = NSLock()
            DispatchQueue.concurrentPerform(iterations: urls.count) { i in
                let meta = EXIFReader.read(from: urls[i])
                lock.withLock { results[i] = meta }
            }
            return results
        }.value
        for (asset, meta) in zip(assets, metadata) {
            asset.exifMetadata = meta
        }

        // Sort by capture time initially (name breaks ties so the order is stable)
        return assets.sorted {
            let t0 = $0.captureTime ?? .distantPast, t1 = $1.captureTime ?? .distantPast
            return t0 == t1 ? $0.stem.localizedStandardCompare($1.stem) == .orderedAscending : t0 < t1
        }
    }

    private func createAsset(from urls: [URL]) -> ImageAsset {
        // Sort by display priority (JPEG first)
        let sorted = urls.sorted {
            FileExtensions.displayPriority($0.pathExtension) <
            FileExtensions.displayPriority($1.pathExtension)
        }

        let jpegURL = sorted.first { $0.isJPEG }
        let rawURL = sorted.first { $0.isRAW }

        if let jpeg = jpegURL, let raw = rawURL {
            return ImageAsset(jpegURL: jpeg, rawURL: raw)
        } else if let jpeg = jpegURL {
            return ImageAsset(jpegURL: jpeg)
        } else if let raw = rawURL {
            return ImageAsset(rawURL: raw)
        } else {
            // Should not happen given our filtering
            return ImageAsset(jpegURL: sorted[0])
        }
    }

    /// Capture-time order with filename as a tie-breaker (a strict weak ordering, unlike `!compareByTime`)
    private static func dateOrder(_ a: ImageAsset, _ b: ImageAsset) -> Bool {
        let t0 = a.captureTime ?? .distantPast, t1 = b.captureTime ?? .distantPast
        if t0 != t1 { return t0 < t1 }
        return a.stem.localizedStandardCompare(b.stem) == .orderedAscending
    }

    private func sortImages(_ images: [ImageAsset]) -> [ImageAsset] {
        switch sort {
        case .dateAscending:
            return images.sorted { Self.dateOrder($0, $1) }
        case .dateDescending:
            return images.sorted { Self.dateOrder($1, $0) }
        case .nameAscending:
            return images.sorted { $0.stem.localizedStandardCompare($1.stem) == .orderedAscending }
        case .nameDescending:
            return images.sorted { $0.stem.localizedStandardCompare($1.stem) == .orderedDescending }
        }
    }
}

/// Error types for folder operations
enum ImageFolderError: Error, LocalizedError {
    case folderNotFound
    case accessDenied
    case scanFailed(Error)

    var errorDescription: String? {
        switch self {
        case .folderNotFound:
            return "The selected folder does not exist."
        case .accessDenied:
            return "Access to the folder was denied."
        case .scanFailed(let error):
            return "Failed to scan folder: \(error.localizedDescription)"
        }
    }
}

/// Statistics for folder display
struct FolderStatistics: Equatable {
    let total: Int
    let reviewed: Int
    let kept: Int
    let trashed: Int
    let favorites: Int

    var unreviewed: Int { total - reviewed }
    var progress: Double { total > 0 ? Double(reviewed) / Double(total) : 0 }

    var summary: String {
        "\(reviewed)/\(total) reviewed • \(kept) kept • \(trashed) trashed • \(favorites) favorites"
    }

    /// Short progress text for status bars, e.g. "12 of 340 reviewed (4%)"
    var progressSummary: String {
        "\(reviewed) of \(total) reviewed (\(Int((progress * 100).rounded()))%)"
    }
}
