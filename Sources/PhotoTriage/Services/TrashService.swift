import Foundation
import AppKit

/// Result of trash operation
struct TrashResult: Equatable {
    let trashedCount: Int
    let failedCount: Int
    let errors: [String]

    var isSuccess: Bool { failedCount == 0 }
}

/// Service for moving trashed images to macOS Trash
@MainActor
final class TrashService: ObservableObject {
    @Published private(set) var isExecuting = false
    @Published private(set) var progress: Double = 0
    @Published var lastResult: TrashResult?

    /// Execute trash for all marked images in folder
    func executeTrash(for folder: ImageFolder) async -> TrashResult {
        isExecuting = true
        progress = 0
        defer { isExecuting = false }

        let trashedAssets = folder.images.filter { $0.isTrashed }
        let total = Double(trashedAssets.count)

        guard total > 0 else {
            let result = TrashResult(trashedCount: 0, failedCount: 0, errors: [])
            lastResult = result
            return result
        }

        var trashedCount = 0
        var failedCount = 0
        var errors: [String] = []

        for (index, asset) in trashedAssets.enumerated() {
            do {
                try await trashAsset(asset)
                trashedCount += 1
            } catch {
                failedCount += 1
                errors.append("\(asset.displayName): \(error.localizedDescription)")
            }

            progress = Double(index + 1) / total
        }

        // Refresh folder after deletion
        folder.refreshStates()

        let result = TrashResult(
            trashedCount: trashedCount,
            failedCount: failedCount,
            errors: errors
        )
        lastResult = result
        return result
    }

    /// Trash a single asset (image files + sentinels)
    private func trashAsset(_ asset: ImageAsset) async throws {
        var urls: [URL] = []

        // Add image files
        urls.append(contentsOf: asset.allFileURLs)

        // Add sentinel files
        urls.append(contentsOf: asset.allSentinelURLs.filter {
            FileManager.default.fileExists(atPath: $0.path)
        })

        // Move to trash using NSWorkspace
        for url in urls {
            try await recycleItem(at: url)
        }
    }

    /// Move item to macOS Trash
    private func recycleItem(at url: URL) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            NSWorkspace.shared.recycle([url]) { trashedURLs, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    /// Count of images marked for trash
    func trashedCount(in folder: ImageFolder) -> Int {
        folder.images.filter { $0.isTrashed }.count
    }

    /// Preview of what will be trashed
    func trashedPreview(in folder: ImageFolder) -> [ImageAsset] {
        folder.images.filter { $0.isTrashed }
    }
}
