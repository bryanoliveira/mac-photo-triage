import Foundation
import SwiftUI
import Combine

/// Current view mode
enum AppView: String, Equatable {
    case gallery
    case preview
    case triage
}

/// Undo action types
enum UndoAction: Equatable {
    case markKept(ImageAsset)
    case markTrashed(ImageAsset)
    case toggleFavorite(ImageAsset)
    case triageDecision(anchor: ImageAsset, candidate: ImageAsset?, anchorAction: TriageAction, candidateAction: TriageAction?)
    case cropApplied(ImageAsset, CropRect, Double)     // asset, cropRect applied, fine rotation baked in
    case rotationApplied(ImageAsset, Bool)             // asset, clockwise

    enum TriageAction {
        case kept
        case trashed
        case none
    }
}

/// Controls which candidates are eligible to appear in the right triage pane.
/// Each level maps to a maximum similarity score (lower = more similar = stricter).
/// "All" has no threshold — every non-trashed image is a candidate.
enum CandidateFilter: String, CaseIterable, Identifiable {
    case all      = "All"
    case loose    = "Loose"
    case moderate = "Moderate"
    case strict   = "Strict"

    var id: String { rawValue }

    /// Maximum score a candidate may have. `nil` means no threshold.
    var scoreThreshold: Double? {
        switch self {
        case .all:      return nil
        case .loose:    return 0.65   // excludes clearly unrelated photos
        case .moderate: return 0.45   // requires same-scene visual similarity
        case .strict:   return 0.25   // near-duplicates only
        }
    }

    var help: String {
        switch self {
        case .all:      return "Show all images as candidates regardless of similarity"
        case .loose:    return "Exclude clearly unrelated photos"
        case .moderate: return "Show candidates with strong visual or temporal similarity"
        case .strict:   return "Show near-duplicates only"
        }
    }
}

/// Global application state
@MainActor
final class AppState: ObservableObject {
    // MARK: - Published State

    /// Current folder being worked on
    @Published var folder: ImageFolder?

    /// Current view mode
    @Published var currentView: AppView = .gallery

    /// Selected image in gallery
    @Published var selectedAsset: ImageAsset?

    /// Current anchor image in triage mode
    @Published var triageAnchor: ImageAsset?

    /// Current candidate image in triage mode
    @Published var triageCandidate: ImageAsset?

    /// Index of current candidate in candidates list
    @Published var candidateIndex: Int = 0

    /// Current image in preview mode
    @Published var previewAsset: ImageAsset?

    /// Index of current preview image
    @Published var previewIndex: Int = 0

    /// Whether EXIF overlay is shown
    @Published var showEXIFOverlay: Bool = false

    /// Whether clipping warnings are shown (red = blown highlights, blue = crushed shadows)
    @Published var showClippingWarnings: Bool = false

    /// Whether the guiding grid overlay is shown (rule of thirds + center crosshair)
    @Published var showGuidingGrid: Bool = false

    /// Whether detail panel is shown in gallery
    @Published var showDetailPanel: Bool = true

    /// Gallery grid column count
    @Published var galleryColumns: Int = 4

    /// Whether the app is loading
    @Published var isLoading: Bool = false

    /// Error message to display
    @Published var errorMessage: String?

    /// Whether to show resume prompt
    @Published var showResumePrompt: Bool = false

    /// Saved progress for resume prompt
    @Published var savedProgress: ProgressRecord?

    /// Incremented after a crop undo/redo so ZoomableImageView reloads from disk
    @Published var cropVersion: Int = 0

    /// Which images are eligible to appear as triage candidates
    @Published var candidateFilter: CandidateFilter = .all {
        didSet {
            UserDefaults.standard.set(candidateFilter.rawValue, forKey: "candidateFilter")
            if currentView == .triage { updateCandidates() }
        }
    }

    // MARK: - Dependencies

    let keyBindings = KeyBindings()
    let similarityEngine = SimilarityEngine()
    let trashService = TrashService()

    private var progressStore: ProgressStore?
    private var undoStack: [UndoAction] = []
    private var redoStack: [UndoAction] = []
    private var candidatesList: [SimilarityCandidate] = []
    private var cancellables = Set<AnyCancellable>()

    init() {
        if let saved = UserDefaults.standard.string(forKey: "candidateFilter"),
           let filter = CandidateFilter(rawValue: saved) {
            candidateFilter = filter
        }
        setupBindings()
    }

    // MARK: - Folder Operations

    /// Open a folder for triage
    func openFolder(_ url: URL) async {
        isLoading = true
        errorMessage = nil

        do {
            // Initialize progress store
            progressStore = try await ProgressStore(folderURL: url)

            // Check for saved progress
            if let progress = try await progressStore?.loadProgress(), progress.hasProgress {
                savedProgress = progress
                showResumePrompt = true
            }

            // Create and scan folder
            let newFolder = ImageFolder(folderURL: url)
            await newFolder.scan()

            if let error = newFolder.errorMessage {
                errorMessage = error
                isLoading = false
                return
            }

            folder = newFolder

            // Initialize similarity engine
            try await similarityEngine.initializeCache(for: url)

            // Load metadata and compute hashes in background
            Task {
                await similarityEngine.loadMetadata(for: newFolder)
                await similarityEngine.computeHashes(for: newFolder)
            }

            // Set initial selection
            if let first = newFolder.filteredImages.first {
                selectedAsset = first
            }

        } catch {
            errorMessage = "Failed to open folder: \(error.localizedDescription)"
        }

        isLoading = false
    }

    /// Resume from saved progress
    func resumeFromProgress() {
        guard let progress = savedProgress, let folder = folder else { return }

        showResumePrompt = false

        switch progress.lastView {
        case ViewType.triage.rawValue:
            if let index = progress.lastTriageIndex,
               index < folder.images.count {
                triageAnchor = folder.images[index]
                updateCandidates()
                currentView = .triage
            }
        case ViewType.preview.rawValue:
            if let index = progress.lastPreviewIndex,
               index < folder.filteredImages.count {
                previewAsset = folder.filteredImages[index]
                previewIndex = index
                currentView = .preview
            }
        default:
            break
        }
    }

    /// Start fresh (ignore saved progress)
    func startFresh() {
        showResumePrompt = false
        savedProgress = nil
    }

    // MARK: - Navigation

    /// Switch to gallery view, keeping the previously-viewed image selected and visible
    func showGallery() {
        switch currentView {
        case .preview:
            if let asset = previewAsset { selectedAsset = asset }
        case .triage:
            if let anchor = triageAnchor { selectedAsset = anchor }
        case .gallery:
            break
        }
        currentView = .gallery
        saveProgress()
    }

    /// Switch to preview view for an asset
    func showPreview(for asset: ImageAsset) {
        previewAsset = asset
        if let folder = folder, let index = folder.index(of: asset) {
            previewIndex = index
        }
        currentView = .preview
        saveProgress()
    }

    /// Switch to triage view starting from an asset
    func showTriage(from asset: ImageAsset? = nil) {
        if let asset = asset {
            triageAnchor = asset
        } else {
            // Validate retained anchor — if it was trashed since last session, pick a fresh one
            if triageAnchor == nil || triageAnchor?.isTrashed == true {
                triageAnchor = folder?.triageableImages.first
            }
        }
        updateCandidates()
        currentView = .triage
        saveProgress()
    }

    /// Navigate to next image in preview
    func nextPreviewImage() {
        guard let folder = folder else { return }
        let images = folder.filteredImages
        if previewIndex < images.count - 1 {
            previewIndex += 1
            previewAsset = images[previewIndex]
            saveProgress()
        }
    }

    /// Navigate to previous image in preview
    func previousPreviewImage() {
        guard previewIndex > 0 else { return }
        guard let folder = folder else { return }
        let images = folder.filteredImages
        previewIndex -= 1
        previewAsset = images[previewIndex]
        saveProgress()
    }

    // MARK: - Triage Operations

    /// Move to next anchor (forward navigation)
    func nextTriageAnchor() {
        guard let anchor = triageAnchor, let folder = folder else { return }

        // Auto-keep current anchor on forward navigation
        if !anchor.isReviewed {
            do {
                try anchor.markKept()
                undoStack.append(.markKept(anchor))
                redoStack.removeAll()
            } catch {
                errorMessage = "Failed to mark image: \(error.localizedDescription)"
            }
        }

        // Find next unreviewed image
        let images = folder.images
        if let currentIndex = images.firstIndex(where: { $0.id == anchor.id }) {
            for i in (currentIndex + 1)..<images.count {
                if !images[i].isReviewed && !images[i].isTrashed {
                    triageAnchor = images[i]
                    updateCandidates()
                    saveProgress()
                    return
                }
            }
        }

        // No more images to triage
        triageAnchor = nil
        triageCandidate = nil
    }

    /// Move to previous anchor
    func previousTriageAnchor() {
        guard let anchor = triageAnchor, let folder = folder else { return }

        let images = folder.images
        if let currentIndex = images.firstIndex(where: { $0.id == anchor.id }) {
            for i in stride(from: currentIndex - 1, through: 0, by: -1) {
                if !images[i].isTrashed {
                    triageAnchor = images[i]
                    updateCandidates()
                    saveProgress()
                    return
                }
            }
        }
    }

    /// Move to next candidate (down)
    func nextCandidate() {
        if candidateIndex < candidatesList.count - 1 {
            candidateIndex += 1
            triageCandidate = candidatesList[candidateIndex].asset
        }
    }

    /// Move to previous candidate (up)
    func previousCandidate() {
        if candidateIndex > 0 {
            candidateIndex -= 1
            triageCandidate = candidatesList[candidateIndex].asset
        }
    }

    /// Keep left (anchor), trash right (candidate), show next candidate for same anchor
    func keepLeft() {
        guard let anchor = triageAnchor, let candidate = triageCandidate else { return }

        do {
            try anchor.markKept()
            try candidate.markTrashed()

            undoStack.append(.triageDecision(
                anchor: anchor,
                candidate: candidate,
                anchorAction: .kept,
                candidateAction: .trashed
            ))
            redoStack.removeAll()

            advanceToNextCandidate(skipping: candidate.id)
        } catch {
            errorMessage = "Failed to update images: \(error.localizedDescription)"
        }
    }

    /// Keep right (candidate), trash left (anchor)
    func keepRight() {
        guard let anchor = triageAnchor, let candidate = triageCandidate else { return }

        do {
            try candidate.markKept()
            try anchor.markTrashed()

            undoStack.append(.triageDecision(
                anchor: anchor,
                candidate: candidate,
                anchorAction: .trashed,
                candidateAction: .kept
            ))
            redoStack.removeAll()

            // Right becomes new anchor
            triageAnchor = candidate
            updateCandidates()
            saveProgress()
        } catch {
            errorMessage = "Failed to update images: \(error.localizedDescription)"
        }
    }

    /// Keep both images and stay on the same pair so the user can swap / continue manually
    func keepBoth() {
        guard let anchor = triageAnchor, let candidate = triageCandidate else { return }

        do {
            try anchor.markKept()
            try candidate.markKept()

            undoStack.append(.triageDecision(
                anchor: anchor,
                candidate: candidate,
                anchorAction: .kept,
                candidateAction: .kept
            ))
            redoStack.removeAll()
        } catch {
            errorMessage = "Failed to update images: \(error.localizedDescription)"
        }
    }

    /// Trash both images
    func keepNone() {
        guard let anchor = triageAnchor, let candidate = triageCandidate else { return }

        do {
            try anchor.markTrashed()
            try candidate.markTrashed()

            undoStack.append(.triageDecision(
                anchor: anchor,
                candidate: candidate,
                anchorAction: .trashed,
                candidateAction: .trashed
            ))
            redoStack.removeAll()

            // Find next unreviewed image
            nextTriageAnchor()
        } catch {
            errorMessage = "Failed to update images: \(error.localizedDescription)"
        }
    }

    /// Promote the current candidate to anchor and rebuild the candidate list for it.
    func swapTriagePair() {
        guard let candidate = triageCandidate else { return }
        let oldAnchor = triageAnchor
        triageAnchor = candidate
        updateCandidates()
        // If hashes aren't ready yet (or no other images qualify), fall back to showing the old anchor
        if triageCandidate == nil {
            triageCandidate = oldAnchor
        }
        saveProgress()
    }

    /// Move all .trash-marked images in the current folder to macOS Trash
    func emptyTrash() {
        guard let folder = folder else { return }
        Task {
            _ = await trashService.executeTrash(for: folder)
            // Rescan so removed files disappear from the images list
            await folder.scan()
        }
    }

    /// Trash the current preview image and advance to the next one
    func trashPreviewImage() {
        guard let asset = previewAsset, let folder = folder else { return }

        // Capture the neighbour from the PRE-TRASH list so we don't skip or stall
        let images = folder.filteredImages
        let currentIndex = images.firstIndex(where: { $0.id == asset.id }) ?? previewIndex
        let targetAsset: ImageAsset?
        if currentIndex + 1 < images.count {
            targetAsset = images[currentIndex + 1]   // prefer the image after
        } else if currentIndex - 1 >= 0 {
            targetAsset = images[currentIndex - 1]   // fall back to image before
        } else {
            targetAsset = nil                        // was the only image
        }

        do {
            try asset.markTrashed()
            undoStack.append(.markTrashed(asset))
            redoStack.removeAll()

            // Find target in the POST-TRASH list (filter may have already removed the trashed image)
            let newImages = folder.filteredImages
            if let target = targetAsset,
               let newIndex = newImages.firstIndex(where: { $0.id == target.id }) {
                previewIndex = newIndex
                previewAsset = target
            } else {
                previewAsset = nil
                previewIndex = 0
            }
            saveProgress()
        } catch {
            errorMessage = "Failed to trash image: \(error.localizedDescription)"
        }
    }

    /// Toggle favorite on an asset
    func toggleFavorite(on asset: ImageAsset) {
        do {
            try asset.toggleFavorite()
            undoStack.append(.toggleFavorite(asset))
            redoStack.removeAll()
        } catch {
            errorMessage = "Failed to toggle favorite: \(error.localizedDescription)"
        }
    }

    /// Record that a crop was applied (for undo/redo)
    func recordCropApplied(to asset: ImageAsset, cropRect: CropRect, rotation: Double) {
        undoStack.append(.cropApplied(asset, cropRect, rotation))
        redoStack.removeAll()
        cropVersion += 1
        asset.thumbnailVersion += 1
    }

    /// Record that a 90° rotation was applied (for undo/redo)
    func recordRotationApplied(to asset: ImageAsset, clockwise: Bool) {
        undoStack.append(.rotationApplied(asset, clockwise))
        redoStack.removeAll()
        cropVersion += 1
        asset.thumbnailVersion += 1
    }

    // MARK: - Undo/Redo

    func undo() {
        guard let action = undoStack.popLast() else { return }

        // File-modifying operations are async — restore from backup, then move to redoStack.
        if case .cropApplied(let asset, _, _) = action {
            Task {
                let service = CropService()
                do {
                    try await service.restoreOriginal(for: asset.displayURL)
                    redoStack.append(action)
                    cropVersion += 1
                    asset.thumbnailVersion += 1
                } catch {
                    undoStack.append(action)
                    errorMessage = "Undo failed: \(error.localizedDescription)"
                }
            }
            return
        }
        if case .rotationApplied(let asset, _) = action {
            Task {
                let service = CropService()
                do {
                    try await service.restoreOriginal(for: asset.displayURL)
                    redoStack.append(action)
                    cropVersion += 1
                    asset.thumbnailVersion += 1
                } catch {
                    undoStack.append(action)
                    errorMessage = "Undo failed: \(error.localizedDescription)"
                }
            }
            return
        }

        do {
            switch action {
            case .markKept(let asset):
                try asset.clearTriageState()
            case .markTrashed(let asset):
                try asset.clearTriageState()
            case .toggleFavorite(let asset):
                try asset.toggleFavorite()
            case .triageDecision(let anchor, let candidate, _, _):
                try anchor.clearTriageState()
                try candidate?.clearTriageState()
            case .cropApplied:
                break  // handled above
            case .rotationApplied:
                break  // handled above
            }
            redoStack.append(action)
        } catch {
            errorMessage = "Undo failed: \(error.localizedDescription)"
        }
    }

    func redo() {
        guard let action = redoStack.popLast() else { return }

        // File-modifying operations are async — reapply, then move to undoStack.
        if case .cropApplied(let asset, let cropRect, let rotation) = action {
            Task {
                let service = CropService()
                do {
                    _ = try await service.applyCrop(to: asset.displayURL, cropRect: cropRect, rotation: rotation)
                    undoStack.append(action)
                    cropVersion += 1
                    asset.thumbnailVersion += 1
                } catch {
                    redoStack.append(action)
                    errorMessage = "Redo failed: \(error.localizedDescription)"
                }
            }
            return
        }
        if case .rotationApplied(let asset, let clockwise) = action {
            Task {
                let service = CropService()
                do {
                    _ = try await service.applyRotation(to: asset.displayURL, clockwise: clockwise)
                    undoStack.append(action)
                    cropVersion += 1
                    asset.thumbnailVersion += 1
                } catch {
                    redoStack.append(action)
                    errorMessage = "Redo failed: \(error.localizedDescription)"
                }
            }
            return
        }

        do {
            switch action {
            case .markKept(let asset):
                try asset.markKept()
            case .markTrashed(let asset):
                try asset.markTrashed()
            case .toggleFavorite(let asset):
                try asset.toggleFavorite()
            case .triageDecision(let anchor, let candidate, let anchorAction, let candidateAction):
                switch anchorAction {
                case .kept: try anchor.markKept()
                case .trashed: try anchor.markTrashed()
                case .none: break
                }
                if let candidate = candidate, let candidateAction = candidateAction {
                    switch candidateAction {
                    case .kept: try candidate.markKept()
                    case .trashed: try candidate.markTrashed()
                    case .none: break
                    }
                }
            case .cropApplied:
                break  // handled above
            case .rotationApplied:
                break  // handled above
            }
            undoStack.append(action)
        } catch {
            errorMessage = "Redo failed: \(error.localizedDescription)"
        }
    }

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    // MARK: - Private

    /// Stay on the current anchor but move to the next viable candidate.
    /// Skips only `excludedID` (the one just acted on); kept/reviewed images remain visible
    /// so the user can compare the anchor against previously-kept similar shots.
    /// Falls through to nextTriageAnchor() when no candidates remain.
    private func advanceToNextCandidate(skipping excludedID: UUID) {
        guard let anchor = triageAnchor, let folder = folder else { return }

        let all = similarityEngine.findCandidates(for: anchor, in: folder)
        let filtered = applyFilter(all)
        if let next = filtered.first(where: { $0.asset.id != excludedID }),
           let idx = filtered.firstIndex(where: { $0.asset.id == next.asset.id }) {
            candidatesList = filtered
            candidateIndex = idx
            triageCandidate = next.asset
            saveProgress()
        } else {
            nextTriageAnchor()
        }
    }

    private func updateCandidates() {
        guard let anchor = triageAnchor, let folder = folder else {
            candidatesList = []
            triageCandidate = nil
            return
        }

        candidatesList = applyFilter(similarityEngine.findCandidates(for: anchor, in: folder))
        candidateIndex = 0
        triageCandidate = candidatesList.first?.asset
    }

    private func applyFilter(_ candidates: [SimilarityCandidate]) -> [SimilarityCandidate] {
        guard let threshold = candidateFilter.scoreThreshold else { return candidates }
        return candidates.filter { $0.score <= threshold }
    }

    private func saveProgress() {
        guard let store = progressStore else { return }

        Task {
            switch currentView {
            case .triage:
                if let anchor = triageAnchor, let folder = folder,
                   let index = folder.images.firstIndex(where: { $0.id == anchor.id }) {
                    try? await store.saveTriageProgress(
                        anchorIndex: index,
                        imagePath: anchor.displayURL.path
                    )
                }
            case .preview:
                if let asset = previewAsset {
                    try? await store.savePreviewProgress(
                        imageIndex: previewIndex,
                        imagePath: asset.displayURL.path
                    )
                }
            case .gallery:
                try? await store.saveCurrentView(.gallery)
            }
        }
    }

    private func setupBindings() {
        // React to folder filter/sort changes
        $folder
            .compactMap { $0 }
            .flatMap { folder in
                Publishers.CombineLatest(folder.$filter, folder.$sort)
            }
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        // React to image list changes (e.g. after emptyTrash rescan)
        $folder
            .compactMap { $0 }
            .flatMap { $0.$images }
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }
}
