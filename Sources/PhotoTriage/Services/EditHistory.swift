import Foundation

/// A point-in-time copy of an edited image's on-disk state: the image file itself, its edit
/// sidecar (`.photo-triage-originals/<name>.json`), and whether the pristine backup existed.
///
/// File edits (crop, rotation, tone, restore) are undone by restoring the snapshot taken just
/// before the edit and redone by restoring the one taken just after — so undo always returns to
/// the *previous* state, not all the way back to the original.
struct EditSnapshot: Equatable {
    let imageCopy: URL
    let sidecarCopy: URL?
    let hadBackup: Bool
}

/// Captures and restores `EditSnapshot`s. Snapshot files live in a per-session temporary
/// directory and are discarded with it.
enum EditHistory {
    static let directory: URL = FileManager.default.temporaryDirectory
        .appendingPathComponent("PhotoTriage-Undo-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)

    /// Copy the current state of `url` into a new snapshot.
    static func capture(_ url: URL, in directory: URL = directory) throws -> EditSnapshot {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let id = UUID().uuidString
        let imageCopy = directory.appendingPathComponent("\(id)-\(url.lastPathComponent)")
        try fm.copyItem(at: url, to: imageCopy)

        let service = CropService()
        let sidecar = service.sidecarURL(for: url)
        var sidecarCopy: URL?
        if fm.fileExists(atPath: sidecar.path) {
            let copy = directory.appendingPathComponent("\(id)-\(sidecar.lastPathComponent)")
            try fm.copyItem(at: sidecar, to: copy)
            sidecarCopy = copy
        }
        let hadBackup = fm.fileExists(atPath: service.backupURL(for: url).path)
        return EditSnapshot(imageCopy: imageCopy, sidecarCopy: sidecarCopy, hadBackup: hadBackup)
    }

    /// Put `url` (and its sidecar/backup bookkeeping) back into the state recorded by `snapshot`.
    /// - Parameter originalIfMissing: when the snapshot expects a backup that no longer exists
    ///   (it was removed by undoing the first edit), the backup is recreated from this file.
    static func restore(_ snapshot: EditSnapshot, to url: URL, originalIfMissing: URL? = nil) throws {
        let fm = FileManager.default
        let service = CropService()

        try replace(url, with: snapshot.imageCopy)

        let sidecar = service.sidecarURL(for: url)
        if let copy = snapshot.sidecarCopy {
            try fm.createDirectory(at: sidecar.deletingLastPathComponent(), withIntermediateDirectories: true)
            try replace(sidecar, with: copy)
        } else if fm.fileExists(atPath: sidecar.path) {
            try fm.removeItem(at: sidecar)
        }

        let backup = service.backupURL(for: url)
        if snapshot.hadBackup {
            if !fm.fileExists(atPath: backup.path), let original = originalIfMissing {
                try fm.createDirectory(at: backup.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fm.copyItem(at: original, to: backup)
            }
        } else if fm.fileExists(atPath: backup.path) {
            // The file had never been edited at this point — drop the backup so the
            // "Restore Original" affordance disappears again.
            try fm.removeItem(at: backup)
        }
    }

    /// Delete a snapshot's files (e.g. when the edit it belonged to failed).
    static func discard(_ snapshot: EditSnapshot) {
        try? FileManager.default.removeItem(at: snapshot.imageCopy)
        if let s = snapshot.sidecarCopy { try? FileManager.default.removeItem(at: s) }
    }

    private static func replace(_ destination: URL, with source: URL) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: destination.path) {
            try fm.removeItem(at: destination)
        }
        try fm.copyItem(at: source, to: destination)
    }
}
