import Foundation

/// Candidate image with similarity score and per-component breakdown
struct SimilarityCandidate: Identifiable, Equatable {
    let id: UUID
    let asset: ImageAsset
    let score: Double           // Lower = more similar
    let hashDistance: Int       // Hamming distance (0-256)
    let histogramDistance: Double?  // Color histogram L1 distance (0-1), nil if unavailable
    let timeDistance: TimeInterval  // Seconds between captures
    let aspectDistance: Double  // Aspect ratio difference (0-1)

    var hashDistancePercent: Double {
        Double(hashDistance) / 256.0 * 100
    }
}

/// Engine for finding similar images using dHash, color histogram, timestamp, and aspect ratio
@MainActor
final class SimilarityEngine: ObservableObject {
    /// Progress of hash computation (0.0 - 1.0)
    @Published private(set) var hashProgress: Double = 0

    /// Whether hash computation is in progress
    @Published private(set) var isComputing = false

    /// Hash cache for persistence
    private var hashCache: HashCache?

    // Scoring weights (must sum to 1.0)
    // Priority: content similarity > time proximity > aspect ratio
    private let contentWeight: Double = 0.60   // dHash + histogram
    private let timeWeight: Double = 0.30
    private let aspectWeight: Double = 0.10

    /// Time normalization cap (images taken within this window score best on time)
    private let timeNormalizationHours: Double = 1.0

    init() {}

    /// Initialize hash cache for a folder
    func initializeCache(for folderURL: URL) async throws {
        hashCache = try await HashCache(folderURL: folderURL)
    }

    /// Compute hashes, histograms, and dimensions for all images in a folder
    func computeHashes(for folder: ImageFolder) async {
        isComputing = true
        hashProgress = 0

        let images = folder.images
        let total = Double(images.count)

        for (index, asset) in images.enumerated() {
            if let cached = try? await hashCache?.getHash(for: asset.displayURL) {
                // Apply cached values
                asset.dHash = cached.dHash
                if asset.exifMetadata == nil {
                    asset.exifMetadata = EXIFMetadata(captureDate: cached.captureDate)
                }

                if let hist = cached.colorHistogram {
                    asset.colorHistogram = hist
                    if let w = cached.imageWidth, let h = cached.imageHeight {
                        asset.imageSize = CGSize(width: w, height: h)
                    }
                } else {
                    // Backfill histogram for records written before this feature
                    let analysis = await computeAnalysisAsync(for: asset.displayURL)
                    asset.colorHistogram = analysis?.histogram
                    asset.imageSize = analysis?.imageSize
                    try? await hashCache?.storeHash(
                        cached.dHash,
                        captureDate: cached.captureDate,
                        colorHistogram: analysis?.histogram,
                        imageWidth: analysis.map { Int($0.imageSize.width) },
                        imageHeight: analysis.map { Int($0.imageSize.height) },
                        for: asset.displayURL
                    )
                }
            } else {
                // Cache miss — compute everything
                async let hashTask = computeHashAsync(for: asset.displayURL)
                async let analysisTask = computeAnalysisAsync(for: asset.displayURL)
                let (hash, analysis) = await (hashTask, analysisTask)

                asset.dHash = hash
                asset.colorHistogram = analysis?.histogram
                asset.imageSize = analysis?.imageSize

                if asset.exifMetadata == nil {
                    asset.exifMetadata = EXIFReader.read(from: asset.displayURL)
                }

                if let hash = hash {
                    try? await hashCache?.storeHash(
                        hash,
                        captureDate: asset.captureTime,
                        colorHistogram: analysis?.histogram,
                        imageWidth: analysis.map { Int($0.imageSize.width) },
                        imageHeight: analysis.map { Int($0.imageSize.height) },
                        for: asset.displayURL
                    )
                }
            }

            hashProgress = Double(index + 1) / total
        }

        isComputing = false
    }

    /// Find candidates for an anchor image, sorted by similarity (lower score = more similar)
    func findCandidates(
        for anchor: ImageAsset,
        in folder: ImageFolder,
        excludeTrashed: Bool = true
    ) -> [SimilarityCandidate] {
        let others = folder.images.filter { asset in
            asset.id != anchor.id &&
            (!excludeTrashed || !asset.isTrashed)
        }

        let candidates = others.map { asset -> SimilarityCandidate in
            let hashDist: Int
            let histDist: Double?

            if let ah = anchor.dHash, let bh = asset.dHash {
                hashDist = DHash.hammingDistance(ah, bh)
                histDist = {
                    guard let h1 = anchor.colorHistogram, let h2 = asset.colorHistogram else { return nil }
                    return ColorHistogram.distance(h1, h2)
                }()
            } else {
                hashDist = 128  // neutral: no visual info yet, sort by time instead
                histDist = nil
            }

            let timeDistance = computeTimeDistance(anchor, asset)
            let aspectDistance = computeAspectDistance(anchor, asset)
            let score = computeScore(
                hashDistance: hashDist,
                histogramDistance: histDist,
                timeDistance: timeDistance,
                aspectDistance: aspectDistance
            )

            return SimilarityCandidate(
                id: asset.id,
                asset: asset,
                score: score,
                hashDistance: hashDist,
                histogramDistance: histDist,
                timeDistance: timeDistance,
                aspectDistance: aspectDistance
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
                continuation.resume(returning: DHash.compute(from: url))
            }
        }
    }

    private func computeAnalysisAsync(for url: URL) async -> ColorHistogram.Analysis? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: ColorHistogram.analyze(from: url))
            }
        }
    }

    private func computeTimeDistance(_ a: ImageAsset, _ b: ImageAsset) -> TimeInterval {
        guard let timeA = a.captureTime, let timeB = b.captureTime else { return .infinity }
        return abs(timeA.timeIntervalSince(timeB))
    }

    private func computeAspectDistance(_ a: ImageAsset, _ b: ImageAsset) -> Double {
        guard let sA = a.imageSize, let sB = b.imageSize,
              sA.height > 0, sB.height > 0 else { return 0.0 }
        let arA = Double(sA.width / sA.height)
        let arB = Double(sB.width / sB.height)
        let maxAR = max(arA, arB)
        guard maxAR > 0 else { return 0.0 }
        return min(abs(arA - arB) / maxAR, 1.0)
    }

    private func computeScore(
        hashDistance: Int,
        histogramDistance: Double?,
        timeDistance: TimeInterval,
        aspectDistance: Double
    ) -> Double {
        // Content: blend dHash and histogram equally when both available
        let normalizedHash = Double(hashDistance) / 256.0
        let contentScore: Double
        if let histDist = histogramDistance {
            contentScore = (normalizedHash + histDist) / 2.0
        } else {
            contentScore = normalizedHash
        }

        // Time proximity: cap at 1 hour
        let normalizedTime: Double
        if timeDistance.isInfinite {
            normalizedTime = 1.0
        } else {
            normalizedTime = min(timeDistance / (timeNormalizationHours * 3600.0), 1.0)
        }

        return contentScore * contentWeight
             + normalizedTime * timeWeight
             + aspectDistance * aspectWeight
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
