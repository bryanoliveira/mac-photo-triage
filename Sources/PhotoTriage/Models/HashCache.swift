import Foundation
import GRDB

/// Cached hash record for an image
struct HashRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "hashes"

    var filePath: String       // Relative path from folder root
    var fileModified: Date     // Last modification time (to detect changes)
    var dHash: Data            // 256-bit perceptual hash
    var captureDate: Date?     // EXIF capture date
    var colorHistogram: Data?  // 16-bucket × 3-channel normalized histogram (192 bytes)
    var imageWidth: Int?       // Pixel width (from EXIF/ImageIO, no decode needed)
    var imageHeight: Int?      // Pixel height
    var updatedAt: Date

    // Primary key
    static var primaryKey: [String] { ["filePath"] }
}

/// Manages the hash cache SQLite database
actor HashCache {
    private let dbQueue: DatabaseQueue
    private let folderURL: URL

    init(folderURL: URL) async throws {
        self.folderURL = folderURL
        let dbPath = folderURL.appendingPathComponent(".photo-triage.db").path

        // Create database
        dbQueue = try DatabaseQueue(path: dbPath)

        // Create/migrate table
        try await dbQueue.write { db in
            try db.create(table: HashRecord.databaseTableName, ifNotExists: true) { t in
                t.column("filePath", .text).primaryKey()
                t.column("fileModified", .datetime).notNull()
                t.column("dHash", .blob).notNull()
                t.column("captureDate", .datetime)
                t.column("colorHistogram", .blob)
                t.column("imageWidth", .integer)
                t.column("imageHeight", .integer)
                t.column("updatedAt", .datetime).notNull()
            }

            // Migrate existing databases that predate colorHistogram/imageWidth/imageHeight columns
            let existing = try db.columns(in: HashRecord.databaseTableName).map(\.name)
            if !existing.contains("colorHistogram") {
                try db.alter(table: HashRecord.databaseTableName) { t in
                    t.add(column: "colorHistogram", .blob)
                    t.add(column: "imageWidth", .integer)
                    t.add(column: "imageHeight", .integer)
                }
            }
        }
    }

    /// Get cached hash for a file (if still valid)
    func getHash(for url: URL) async throws -> HashRecord? {
        let relativePath = relativePathFrom(url)

        return try await dbQueue.read { db in
            guard let record = try HashRecord.fetchOne(db, key: relativePath) else {
                return nil
            }

            // Check if file has been modified
            let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
            let fileModified = attrs?[.modificationDate] as? Date ?? Date.distantPast

            if record.fileModified == fileModified {
                return record
            } else {
                return nil  // Stale cache
            }
        }
    }

    /// Store hash and supplementary analysis for a file
    func storeHash(
        _ dHash: Data,
        captureDate: Date?,
        colorHistogram: Data? = nil,
        imageWidth: Int? = nil,
        imageHeight: Int? = nil,
        for url: URL
    ) async throws {
        let relativePath = relativePathFrom(url)

        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        let fileModified = attrs?[.modificationDate] as? Date ?? Date()

        let record = HashRecord(
            filePath: relativePath,
            fileModified: fileModified,
            dHash: dHash,
            captureDate: captureDate,
            colorHistogram: colorHistogram,
            imageWidth: imageWidth,
            imageHeight: imageHeight,
            updatedAt: Date()
        )

        try await dbQueue.write { db in
            try record.save(db)
        }
    }

    /// Remove hash for a file
    func removeHash(for url: URL) async throws {
        let relativePath = relativePathFrom(url)

        try await dbQueue.write { db in
            try db.execute(sql: "DELETE FROM \(HashRecord.databaseTableName) WHERE filePath = ?", arguments: [relativePath])
        }
    }

    /// Get all cached hashes
    func getAllHashes() async throws -> [HashRecord] {
        try await dbQueue.read { db in
            try HashRecord.fetchAll(db)
        }
    }

    /// Clean up stale entries (files that no longer exist)
    func cleanupStaleEntries() async throws {
        let records = try await getAllHashes()

        for record in records {
            let fullPath = folderURL.appendingPathComponent(record.filePath)
            if !FileManager.default.fileExists(atPath: fullPath.path) {
                try await removeHash(for: fullPath)
            }
        }
    }

    // MARK: - Private

    private func relativePathFrom(_ url: URL) -> String {
        let folderPath = folderURL.path
        let filePath = url.path

        if filePath.hasPrefix(folderPath) {
            var relative = String(filePath.dropFirst(folderPath.count))
            if relative.hasPrefix("/") {
                relative = String(relative.dropFirst())
            }
            return relative
        }
        return url.lastPathComponent
    }
}
