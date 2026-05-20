import Foundation

/// Sentinel file types for marking image state
enum SentinelType: String, CaseIterable {
    case keep = "keep"
    case trash = "trash"
    case favorite = "favorite"
    case reviewed = "reviewed"

    /// The file extension for this sentinel type
    var fileExtension: String { rawValue }
}

/// Manages sentinel files for marking image state
/// Sentinel files are zero-byte files next to images: IMG_1234.JPG.keep, etc.
struct SentinelState: Equatable {
    let imageURL: URL
    private(set) var isKeep: Bool = false
    private(set) var isTrash: Bool = false
    private(set) var isFavorite: Bool = false
    private(set) var isReviewed: Bool = false

    /// Initialize by reading existing sentinel files
    init(for imageURL: URL) {
        self.imageURL = imageURL
        refresh()
    }

    /// Create with explicit state (for testing)
    init(imageURL: URL, isKeep: Bool, isTrash: Bool, isFavorite: Bool, isReviewed: Bool) {
        self.imageURL = imageURL
        self.isKeep = isKeep
        self.isTrash = isTrash
        self.isFavorite = isFavorite
        self.isReviewed = isReviewed
    }

    /// URL for a sentinel file of the given type
    func sentinelURL(for type: SentinelType) -> URL {
        imageURL.appendingPathExtension(type.fileExtension)
    }

    /// Refresh state by checking filesystem
    mutating func refresh() {
        let fileManager = FileManager.default
        isKeep = fileManager.fileExists(atPath: sentinelURL(for: .keep).path)
        isTrash = fileManager.fileExists(atPath: sentinelURL(for: .trash).path)
        isFavorite = fileManager.fileExists(atPath: sentinelURL(for: .favorite).path)
        isReviewed = fileManager.fileExists(atPath: sentinelURL(for: .reviewed).path)
    }

    /// Set a sentinel state and persist to filesystem
    mutating func set(_ type: SentinelType, value: Bool) throws {
        let url = sentinelURL(for: type)
        let fileManager = FileManager.default

        if value {
            // Create zero-byte sentinel file
            if !fileManager.fileExists(atPath: url.path) {
                fileManager.createFile(atPath: url.path, contents: nil, attributes: nil)
            }
        } else {
            // Remove sentinel file
            if fileManager.fileExists(atPath: url.path) {
                try fileManager.removeItem(at: url)
            }
        }

        // Update local state
        switch type {
        case .keep: isKeep = value
        case .trash: isTrash = value
        case .favorite: isFavorite = value
        case .reviewed: isReviewed = value
        }
    }

    /// Mark as kept (auto-keep on forward navigation)
    mutating func markKept() throws {
        try set(.keep, value: true)
        try set(.trash, value: false)
        try set(.reviewed, value: true)
    }

    /// Mark as trashed
    mutating func markTrashed() throws {
        try set(.trash, value: true)
        try set(.keep, value: false)
        try set(.reviewed, value: true)
    }

    /// Clear all triage state (undo)
    mutating func clearTriageState() throws {
        try set(.keep, value: false)
        try set(.trash, value: false)
        try set(.reviewed, value: false)
    }

    /// Toggle favorite state
    mutating func toggleFavorite() throws {
        try set(.favorite, value: !isFavorite)
    }

    /// Remove all sentinel files
    mutating func removeAllSentinels() throws {
        for type in SentinelType.allCases {
            try set(type, value: false)
        }
    }

    /// Copy sentinels to another image URL (for RAW pairing)
    func copySentinels(to targetURL: URL) throws {
        var targetState = SentinelState(for: targetURL)
        try targetState.set(.keep, value: isKeep)
        try targetState.set(.trash, value: isTrash)
        try targetState.set(.favorite, value: isFavorite)
        try targetState.set(.reviewed, value: isReviewed)
    }
}

/// Batch operations for sentinel files
extension SentinelState {
    /// Get all sentinel URLs for cleanup
    var allSentinelURLs: [URL] {
        SentinelType.allCases.map { sentinelURL(for: $0) }
    }

    /// Check if any triage decision has been made
    var hasTriageDecision: Bool {
        isKeep || isTrash
    }

    /// State description for display
    var stateDescription: String {
        var parts: [String] = []
        if isKeep { parts.append("kept") }
        if isTrash { parts.append("trashed") }
        if isFavorite { parts.append("favorite") }
        if isReviewed && !hasTriageDecision { parts.append("reviewed") }
        return parts.isEmpty ? "unreviewed" : parts.joined(separator: ", ")
    }
}
