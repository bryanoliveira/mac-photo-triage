import Foundation

/// Candidate image with similarity score
struct SimilarityCandidate: Identifiable, Equatable {
    let id: UUID
    let asset: ImageAsset
    let score: Double      // Lower = more similar
    let hashDistance: Int  // Hamming distance (0-256)
    let timeDistance: TimeInterval  // Seconds between captures

    var hashDistancePercent: Double {
        Double(hashDistance) / 256.0 * 100
    }
}

/// Engine for finding similar images using dHash and timestamp proximity
@MainActor
final class SimilarityEngine: ObservableObject {
    /// Progress of hash computation (0.0 - 1.0)
    @Published private(set) var hashProgress: Double = 0

    /// Whether hash computation is in progress
    @Published private(set) var isComputing = false

    /// Hash cache for persistence
    private var hashCache: HashCache?

    /// Weight for hash distance in similarity score (0.0 - 1.0)
    private let hashWeight: Double = 0.7

    /// Weight for time distance in similarity score (0.0 - 1.0)
    private let timeWeight: Double = 0.3

    /// Time normalization factor (1 hour = 1.0 score)
    private let timeNormalizationHours: Double = 1.0

    init() {}

    /// Initialize hash cache for a folder
    func initializeCache(for folderURL: URL) async throws {
        hashCache = try await HashCache(folderURL: folderURL)
    }

    /// Compute hashes for all images in a folder
    func computeHashes(for folder: ImageFolder) async {
        isComputing = true
        hashProgress = 0

        let images = folder.images
        let total = Double(images.count)

        for (index, asset) in images.enumerated() {
            // Check cache first
            if let cached = try? await hashCache?.getHash(for: asset.displayURL) {
                asset.dHash = cached.dHash
                if asset.exifMetadata == nil {
                    asset.exifMetadata = EXIFMetadata(captureDate: cached.captureDate)
                }
            } else {
                // Compute hash
                let hash = await computeHashAsync(for: asset.displayURL)
                asset.dHash = hash

                // Load EXIF if not already loaded
                if asset.exifMetadata == nil {
                    asset.exifMetadata = EXIFReader.read(from: asset.displayURL)
                }

                // Cache the result
                if let hash = hash {
                    try? await hashCache?.storeHash(
                        hash,
                        captureDate: asset.captureTime,
                        for: asset.displayURL
                    )
                }
            }

            hashProgress = Double(index + 1) / total
        }

        isComputing = false
    }

    /// Find candidates for an anchor image, sorted by similarity
    func findCandidates(
        for anchor: ImageAsset,
        in folder: ImageFolder,
        excludeTrashed: Bool = true
    ) -> [SimilarityCandidate] {
        guard let anchorHash = anchor.dHash else { return [] }

        let others = folder.images.filter { asset in
            asset.id != anchor.id &&
            (!excludeTrashed || !asset.isTrashed) &&
            asset.dHash != nil
        }

        let candidates = others.compactMap { asset -> SimilarityCandidate? in
            guard let hash = asset.dHash else { return nil }

            let hashDistance = DHash.hammingDistance(anchorHash, hash)
            let timeDistance = computeTimeDistance(anchor, asset)
            let score = computeScore(hashDistance: hashDistance, timeDistance: timeDistance)

            return SimilarityCandidate(
                id: asset.id,
                asset: asset,
                score: score,
                hashDistance: hashDistance,
                timeDistance: timeDistance
            )
        }

        return candidates.sorted { $0.score < $1.score }
    }

    /// Get the best candidate for an anchor
    func bestCandidate(for anchor: ImageAsset, in folder: ImageFolder) -> ImageAsset? {
        findCandidates(for: anchor, in: folder).first?.asset
    }

    // MARK: - Private

    private func computeHashAsync(for url: URL) async -> Data? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let hash = DHash.compute(from: url)
                continuation.resume(returning: hash)
            }
        }
    }

    private func computeTimeDistance(_ a: ImageAsset, _ b: ImageAsset) -> TimeInterval {
        guard let timeA = a.captureTime, let timeB = b.captureTime else {
            return .infinity
        }
        return abs(timeA.timeIntervalSince(timeB))
    }

    private func computeScore(hashDistance: Int, timeDistance: TimeInterval) -> Double {
        // Normalize hash distance: 0-256 → 0-1
        let normalizedHash = Double(hashDistance) / 256.0

        // Normalize time distance: cap at 1 hour
        let normalizedTime: Double
        if timeDistance.isInfinite {
            normalizedTime = 1.0  // Unknown time gets max time score
        } else {
            let hours = timeDistance / 3600.0
            normalizedTime = min(hours / timeNormalizationHours, 1.0)
        }

        // Weighted combination
        return normalizedHash * hashWeight + normalizedTime * timeWeight
    }
}

// MARK: - Batch Operations

extension SimilarityEngine {
    /// Load EXIF metadata for all images
    func loadMetadata(for folder: ImageFolder) async {
        for asset in folder.images {
            if asset.exifMetadata == nil {
                asset.exifMetadata = EXIFReader.read(from: asset.displayURL)
            }
        }
    }

    /// Check if all images have hashes computed
    func hasAllHashes(for folder: ImageFolder) -> Bool {
        folder.images.allSatisfy { $0.dHash != nil }
    }

    /// Count of images with hashes
    func hashedCount(for folder: ImageFolder) -> Int {
        folder.images.filter { $0.dHash != nil }.count
    }
}
