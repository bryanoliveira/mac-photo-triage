import Foundation
import SwiftUI

/// Represents a single image asset (or JPEG+RAW pair)
/// The JPEG is the display/edit target; RAW is kept pristine
final class ImageAsset: Identifiable, ObservableObject, Equatable, Hashable {
    let id: UUID

    /// Primary display URL (JPEG if pair exists, otherwise RAW)
    let displayURL: URL

    /// JPEG URL if exists
    let jpegURL: URL?

    /// RAW URL if exists
    let rawURL: URL?

    /// Filename stem (without extension)
    let stem: String

    /// Parent folder URL
    let folderURL: URL

    /// Cached EXIF metadata
    @Published var exifMetadata: EXIFMetadata?

    /// Cached perceptual hash
    @Published var dHash: Data?

    /// 16-bucket × 3-channel RGB color histogram (192 bytes of Float32)
    @Published var colorHistogram: Data?

    /// Pixel dimensions (read from ImageIO properties — no full decode needed)
    @Published var imageSize: CGSize?

    /// Sentinel state (keep/trash/favorite/reviewed)
    @Published var sentinelState: SentinelState

    /// Incremented after any file edit so thumbnails know to reload from disk
    @Published var thumbnailVersion: Int = 0

    /// Capture timestamp from EXIF (for similarity ranking)
    var captureTime: Date? {
        exifMetadata?.captureDate
    }

    /// Whether this asset has been marked for trash
    var isTrashed: Bool {
        sentinelState.isTrash
    }

    /// Whether this asset has been kept
    var isKept: Bool {
        sentinelState.isKeep
    }

    /// Whether this asset has been reviewed
    var isReviewed: Bool {
        sentinelState.isReviewed
    }

    /// Whether this asset is a favorite
    var isFavorite: Bool {
        sentinelState.isFavorite
    }

    /// Whether this is a RAW+JPEG pair
    var isPair: Bool {
        jpegURL != nil && rawURL != nil
    }

    /// Initialize with JPEG only
    init(jpegURL: URL) {
        self.id = UUID()
        self.displayURL = jpegURL
        self.jpegURL = jpegURL
        self.rawURL = nil
        self.stem = jpegURL.stem
        self.folderURL = jpegURL.deletingLastPathComponent()
        self.sentinelState = SentinelState(for: jpegURL)
    }

    /// Initialize with RAW only
    init(rawURL: URL) {
        self.id = UUID()
        self.displayURL = rawURL
        self.jpegURL = nil
        self.rawURL = rawURL
        self.stem = rawURL.stem
        self.folderURL = rawURL.deletingLastPathComponent()
        self.sentinelState = SentinelState(for: rawURL)
    }

    /// Initialize with JPEG+RAW pair
    init(jpegURL: URL, rawURL: URL) {
        self.id = UUID()
        self.displayURL = jpegURL  // JPEG is display priority
        self.jpegURL = jpegURL
        self.rawURL = rawURL
        self.stem = jpegURL.stem
        self.folderURL = jpegURL.deletingLastPathComponent()
        self.sentinelState = SentinelState(for: jpegURL)
    }

    // MARK: - Actions

    /// Mark as kept
    func markKept() throws {
        try sentinelState.markKept()
        // Mirror to RAW if pair exists
        if let rawURL = rawURL {
            try sentinelState.copySentinels(to: rawURL)
        }
        objectWillChange.send()
    }

    /// Mark as trashed
    func markTrashed() throws {
        try sentinelState.markTrashed()
        // Mirror to RAW if pair exists
        if let rawURL = rawURL {
            try sentinelState.copySentinels(to: rawURL)
        }
        objectWillChange.send()
    }

    /// Toggle favorite
    func toggleFavorite() throws {
        try sentinelState.toggleFavorite()
        // Mirror to RAW if pair exists
        if let rawURL = rawURL {
            try sentinelState.copySentinels(to: rawURL)
        }
        objectWillChange.send()
    }

    /// Clear triage state (for undo)
    func clearTriageState() throws {
        try sentinelState.clearTriageState()
        // Mirror to RAW if pair exists
        if let rawURL = rawURL {
            try sentinelState.copySentinels(to: rawURL)
        }
        objectWillChange.send()
    }

    /// Refresh sentinel state from filesystem
    func refreshState() {
        sentinelState.refresh()
        objectWillChange.send()
    }

    /// All file URLs belonging to this asset (for trash)
    var allFileURLs: [URL] {
        var urls = [displayURL]
        if let rawURL = rawURL, rawURL != displayURL {
            urls.append(rawURL)
        }
        return urls
    }

    /// All sentinel URLs belonging to this asset
    var allSentinelURLs: [URL] {
        var urls = sentinelState.allSentinelURLs
        if let rawURL = rawURL {
            let rawState = SentinelState(for: rawURL)
            urls.append(contentsOf: rawState.allSentinelURLs)
        }
        return urls
    }

    // MARK: - Display Helpers

    /// Filename for display
    var displayName: String {
        displayURL.lastPathComponent
    }

    /// Type indicator for display
    var typeIndicator: String {
        if isPair { return "RAW+JPEG" }
        if rawURL != nil { return "RAW" }
        return "JPEG"
    }

    /// State badge text
    var stateBadge: String? {
        if isTrashed { return "Trash" }
        if isKept { return "Keep" }
        return nil
    }

    // MARK: - Equatable & Hashable

    static func == (lhs: ImageAsset, rhs: ImageAsset) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - Comparable by capture time

extension ImageAsset {
    /// Compare by capture time (for sorting)
    func compareByTime(_ other: ImageAsset) -> Bool {
        let time1 = captureTime ?? Date.distantPast
        let time2 = other.captureTime ?? Date.distantPast
        return time1 < time2
    }
}
