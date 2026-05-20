import Foundation
import GRDB

/// Progress record for a folder
struct ProgressRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "progress"

    var folderPath: String           // Absolute folder path
    var lastTriageIndex: Int?        // Last anchor index in triage
    var lastPreviewIndex: Int?       // Last viewed image index in preview
    var lastGalleryScroll: Double?   // Last scroll position in gallery
    var lastView: String?            // Last active view: "gallery", "preview", "triage"
    var lastImagePath: String?       // Path to last viewed image
    var updatedAt: Date

    static var primaryKey: [String] { ["folderPath"] }
}

/// View types for progress tracking
enum ViewType: String {
    case gallery
    case preview
    case triage
}

/// Manages progress state persistence
actor ProgressStore {
    private let dbQueue: DatabaseQueue
    private let folderURL: URL

    init(folderURL: URL) async throws {
        self.folderURL = folderURL
        let dbPath = folderURL.appendingPathComponent(".photo-triage.db").path

        // Create database
        dbQueue = try DatabaseQueue(path: dbPath)

        // Create tables
        try await dbQueue.write { db in
            try db.create(table: ProgressRecord.databaseTableName, ifNotExists: true) { t in
                t.column("folderPath", .text).primaryKey()
                t.column("lastTriageIndex", .integer)
                t.column("lastPreviewIndex", .integer)
                t.column("lastGalleryScroll", .double)
                t.column("lastView", .text)
                t.column("lastImagePath", .text)
                t.column("updatedAt", .datetime).notNull()
            }
        }
    }

    /// Load saved progress for the folder
    func loadProgress() async throws -> ProgressRecord? {
        try await dbQueue.read { [folderURL] db in
            try ProgressRecord.fetchOne(db, key: folderURL.path)
        }
    }

    /// Save triage progress
    func saveTriageProgress(anchorIndex: Int, imagePath: String?) async throws {
        try await saveProgress { record in
            record.lastTriageIndex = anchorIndex
            record.lastView = ViewType.triage.rawValue
            if let path = imagePath {
                record.lastImagePath = path
            }
        }
    }

    /// Save preview progress
    func savePreviewProgress(imageIndex: Int, imagePath: String?) async throws {
        try await saveProgress { record in
            record.lastPreviewIndex = imageIndex
            record.lastView = ViewType.preview.rawValue
            if let path = imagePath {
                record.lastImagePath = path
            }
        }
    }

    /// Save gallery scroll position
    func saveGalleryProgress(scrollPosition: Double) async throws {
        try await saveProgress { record in
            record.lastGalleryScroll = scrollPosition
            record.lastView = ViewType.gallery.rawValue
        }
    }

    /// Save current view type
    func saveCurrentView(_ view: ViewType) async throws {
        try await saveProgress { record in
            record.lastView = view.rawValue
        }
    }

    /// Clear all progress for this folder
    func clearProgress() async throws {
        try await dbQueue.write { [folderURL] db in
            try db.execute(
                sql: "DELETE FROM \(ProgressRecord.databaseTableName) WHERE folderPath = ?",
                arguments: [folderURL.path]
            )
        }
    }

    // MARK: - Private

    private func saveProgress(_ modify: @escaping (inout ProgressRecord) -> Void) async throws {
        try await dbQueue.write { [folderURL] db in
            var record = try ProgressRecord.fetchOne(db, key: folderURL.path) ?? ProgressRecord(
                folderPath: folderURL.path,
                lastTriageIndex: nil,
                lastPreviewIndex: nil,
                lastGalleryScroll: nil,
                lastView: nil,
                lastImagePath: nil,
                updatedAt: Date()
            )

            modify(&record)
            record.updatedAt = Date()

            try record.save(db)
        }
    }
}

/// Extension for easier resume prompts
extension ProgressRecord {
    /// Human-readable description of where to resume
    var resumeDescription: String {
        var parts: [String] = []

        if let view = lastView {
            parts.append("View: \(view)")
        }

        if let index = lastTriageIndex {
            parts.append("Triage image #\(index + 1)")
        }

        if let path = lastImagePath {
            let filename = URL(fileURLWithPath: path).lastPathComponent
            parts.append("Last: \(filename)")
        }

        return parts.isEmpty ? "Resume from last session" : parts.joined(separator: " • ")
    }

    /// Check if there's meaningful progress to resume
    var hasProgress: Bool {
        lastTriageIndex != nil || lastPreviewIndex != nil || lastImagePath != nil
    }
}
