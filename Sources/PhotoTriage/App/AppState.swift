import Foundation
import SwiftUI
import Combine

/// Current view mode
enum AppView: String, Equatable {
    case gallery
    case preview
    case triage
}

/// One asset's triage-state transition, recorded so undo can restore the *exact* prior state
/// (e.g. a previously-kept candidate goes back to kept, not to unreviewed).
struct StateChange: Equatable {
    let asset: ImageAsset
    let from: TriageState
    let to: TriageState
}

/// Where the user was when an undoable action happened, so undo can bring them back there.
enum UndoContext: Equatable {
    case none
    case preview(ImageAsset)
    case triage(anchor: ImageAsset, candidate: ImageAsset?)
}

/// Undo action types
enum UndoAction: Equatable {
    /// Keep / trash / clear decisions (single image or a triage pair)
    case stateChange([StateChange], label: String, context: UndoContext)
    case toggleFavorite(ImageAsset)
    /// Any on-disk edit (crop, horizon, tone, 90° rotation, restore original)
    case fileEdit(ImageAsset, before: EditSnapshot, after: EditSnapshot, label: String)

    var label: String {
        switch self {
        case .stateChange(_, let label, _): return label
        case .toggleFavorite: return "Favorite"
        case .fileEdit(_, _, _, let label): return label
        }
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

    /// True once forward navigation runs past the last image in triage
    @Published var triageFinished: Bool = false

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
    @Published var showDetailPanel: Bool = true {
        didSet { UserDefaults.standard.set(showDetailPanel, forKey: "showDetailPanel") }
    }

    /// Gallery grid column count
    @Published var galleryColumns: Int = 4 {
        didSet { UserDefaults.standard.set(galleryColumns, forKey: "galleryColumns") }
    }

    /// Whether both triage panes zoom and pan together
    @Published var syncTriageZoom: Bool = true {
        didSet { UserDefaults.standard.set(syncTriageZoom, forKey: "syncTriageZoom") }
    }

    /// Whether the app is loading
    @Published var isLoading: Bool = false

    /// Error message to display
    @Published var errorMessage: String?

    /// Short-lived confirmation message ("Kept IMG_0102.JPG", "Undo: Trash", …)
    @Published var toast: String?

    /// Whether the "Empty Trash?" confirmation is showing
    @Published var showEmptyTrashConfirmation = false

    /// Whether to show resume prompt
    @Published var showResumePrompt: Bool = false

    /// Saved progress for resume prompt
    @Published var savedProgress: ProgressRecord?

    /// Incremented after every file edit so ZoomableImageView reloads from disk
    @Published var cropVersion: Int = 0

    /// Which images are eligible to appear as triage candidates
    @Published var candidateFilter: CandidateFilter = .all {
        didSet {
            UserDefaults.standard.set(candidateFilter.rawValue, forKey: "candidateFilter")
            if currentView == .triage { updateCandidates() }
        }
    }

    /// Undo / redo availability, published so toolbar buttons and menus update
    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false

    // MARK: - Dependencies

    let keyBindings = KeyBindings()
    let similarityEngine = SimilarityEngine()
    let trashService = TrashService()

    private var progressStore: ProgressStore?
    private var undoStack: [UndoAction] = [] { didSet { canUndo = !undoStack.isEmpty } }
    private var redoStack: [UndoAction] = [] { didSet { canRedo = !redoStack.isEmpty } }
    private var candidatesList: [SimilarityCandidate] = []
    private var cancellables = Set<AnyCancellable>()
    private var toastTask: Task<Void, Never>?

    /// Background metadata + hash computation for the open folder (awaitable in tests)
    private(set) var analysisTask: Task<Void, Never>?

    init() {
        let defaults = UserDefaults.standard
        if let saved = defaults.string(forKey: "candidateFilter"),
           let filter = CandidateFilter(rawValue: saved) {
            candidateFilter = filter
        }
        if defaults.object(forKey: "galleryColumns") != nil {
            galleryColumns = min(12, max(2, defaults.integer(forKey: "galleryColumns")))
        }
        if defaults.object(forKey: "showDetailPanel") != nil {
            showDetailPanel = defaults.bool(forKey: "showDetailPanel")
        }
        if defaults.object(forKey: "syncTriageZoom") != nil {
            syncTriageZoom = defaults.bool(forKey: "syncTriageZoom")
        }
        // Resolve the screen-size decode tier on the main thread (it reads NSScreen)
        _ = ImagePipeline.screenMaxPixel
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

            // Create and scan folder
            let newFolder = ImageFolder(folderURL: url)
            await newFolder.scan()

            if let error = newFolder.errorMessage {
                errorMessage = error
                isLoading = false
                return
            }

            // Reset per-folder state
            folder = newFolder
            undoStack.removeAll()
            redoStack.removeAll()
            candidatesList = []
            triageAnchor = nil
            triageCandidate = nil
            previewAsset = nil
            triageFinished = false
            currentView = .gallery
            UserDefaults.standard.set(url.path, forKey: "lastFolderPath")

            // Check for saved progress (only meaningful if there are images to resume into)
            if !newFolder.images.isEmpty,
               let progress = try await progressStore?.loadProgress(), progress.hasProgress {
                savedProgress = progress
                showResumePrompt = true
            }

            // Initialize similarity engine
            try await similarityEngine.initializeCache(for: url)

            // Load metadata and compute hashes in background
            analysisTask?.cancel()
            analysisTask = Task {
                await similarityEngine.loadMetadata(for: newFolder)
                await similarityEngine.computeHashes(for: newFolder)
                if currentView == .triage, triageCandidate == nil { updateCandidates() }
            }

            // Set initial selection: first unreviewed image, else the first image
            let ordered = newFolder.filteredImages
            selectedAsset = ordered.first { $0.triageState == .unreviewed } ?? ordered.first

        } catch {
            errorMessage = "Failed to open folder: \(error.localizedDescription)"
        }

        isLoading = false
    }

    /// Re-open the most recently used folder, if it still exists
    func reopenLastFolder() async {
        guard folder == nil,
              let path = UserDefaults.standard.string(forKey: "lastFolderPath"),
              FileManager.default.fileExists(atPath: path) else { return }
        await openFolder(URL(fileURLWithPath: path))
    }

    /// Resume from saved progress
    func resumeFromProgress() {
        guard let progress = savedProgress, let folder = folder else { return }

        showResumePrompt = false
        let byPath = progress.lastImagePath.flatMap { path in
            folder.images.first { $0.displayURL.path == path }
        }

        switch progress.lastView {
        case ViewType.triage.rawValue:
            if let asset = byPath ?? progress.lastTriageIndex.flatMap({ folder.images.indices.contains($0) ? folder.images[$0] : nil }) {
                showTriage(from: asset)
            }
        case ViewType.preview.rawValue:
            let images = folder.filteredImages
            if let asset = byPath ?? progress.lastPreviewIndex.flatMap({ images.indices.contains($0) ? images[$0] : nil }) {
                showPreview(for: asset)
            }
        default:
            if let asset = byPath { selectedAsset = asset }
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
        prefetchPreviewNeighbors()
        saveProgress()
    }

    /// Switch to triage view starting from an asset.
    /// Without an explicit asset, resumes the previous anchor, else the gallery selection,
    /// else the first unreviewed image, else the first image — reviewed images are never skipped.
    func showTriage(from asset: ImageAsset? = nil) {
        guard let folder else { return }
        let order = folder.sortedImages
        let stillPresent: (ImageAsset?) -> ImageAsset? = { candidate in
            candidate.flatMap { c in order.contains(c) ? c : nil }
        }

        let origin: ImageAsset?
        switch currentView {
        case .preview: origin = previewAsset
        case .gallery: origin = selectedAsset
        case .triage:  origin = nil
        }

        triageAnchor = stillPresent(asset)
            ?? stillPresent(origin)
            ?? stillPresent(triageAnchor)
            ?? order.first { $0.triageState == .unreviewed }
            ?? order.first
        triageFinished = false
        updateCandidates()
        currentView = .triage
        saveProgress()
    }

    /// Navigate to next image in preview. The image being left is marked kept if it had no decision.
    func nextPreviewImage() {
        stepPreview(by: 1)
    }

    /// Navigate to previous image in preview. The image being left is marked kept if it had no decision.
    func previousPreviewImage() {
        stepPreview(by: -1)
    }

    /// Position of the preview image within the current filter, e.g. (3, 120). Nil if it was filtered out.
    var previewPosition: (index: Int, count: Int)? {
        guard let folder, let asset = previewAsset else { return nil }
        let images = folder.filteredImages
        guard let i = images.firstIndex(of: asset) else { return nil }
        return (i, images.count)
    }

    private func stepPreview(by delta: Int) {
        guard let folder, let current = previewAsset else { return }

        // Resolve the destination from the list *before* auto-keeping, because under a filter
        // like "Unreviewed" the current image disappears from the list once it is kept.
        let before = folder.filteredImages
        let target: ImageAsset? = before.firstIndex(of: current).flatMap { i in
            before.indices.contains(i + delta) ? before[i + delta] : nil
        }

        autoKeep(current, context: .preview(current))

        if let target {
            previewAsset = target
        } else {
            showToast(delta > 0 ? "Last photo" : "First photo")
        }
        if let asset = previewAsset, let i = folder.filteredImages.firstIndex(of: asset) {
            previewIndex = i
        }
        prefetchPreviewNeighbors()
        saveProgress()
    }

    /// Warm the image cache for the photos either side of the preview image.
    private func prefetchPreviewNeighbors() {
        guard let folder, let asset = previewAsset else { return }
        let images = folder.filteredImages
        guard let i = images.firstIndex(of: asset) else { return }
        let neighbors = [i + 1, i - 1, i + 2].filter { images.indices.contains($0) }.map { images[$0].displayURL }
        ImagePipeline.shared.prefetch(neighbors)
    }

    // MARK: - Single-image decisions (Gallery / Preview)

    /// Mark the preview image kept and advance
    func keepPreviewImage() {
        decidePreviewImage(.kept)
    }

    /// Mark the preview image for trash and advance
    func trashPreviewImage() {
        decidePreviewImage(.trashed)
    }

    /// Remove any keep/trash decision from the preview image (stays on it)
    func clearPreviewImage() {
        guard let asset = previewAsset else { return }
        setState(.unreviewed, on: asset, label: "Clear Decision", context: .preview(asset))
    }

    private func decidePreviewImage(_ state: TriageState) {
        guard let asset = previewAsset, let folder = folder else { return }

        // Capture the neighbour from the PRE-change list so we don't skip or stall
        let images = folder.filteredImages
        let target = Self.neighbor(of: asset, in: images)

        guard setState(state, on: asset, label: state == .kept ? "Keep" : "Trash",
                       context: .preview(asset)) else { return }

        // Find target in the POST-change list (the filter may have removed the current image)
        let newImages = folder.filteredImages
        if let target, let newIndex = newImages.firstIndex(of: target) {
            previewIndex = newIndex
            previewAsset = target
        } else if !newImages.contains(asset) {
            previewAsset = newImages.first
            previewIndex = 0
        }
        prefetchPreviewNeighbors()
        saveProgress()
    }

    /// Set a decision on the gallery selection, then move the selection to the next image.
    func decideSelected(_ state: TriageState) {
        guard let asset = selectedAsset, let folder = folder else { return }
        let target = Self.neighbor(of: asset, in: folder.filteredImages)
        let label: String
        switch state {
        case .kept: label = "Keep"
        case .trashed: label = "Trash"
        default: label = "Clear Decision"
        }
        guard setState(state, on: asset, label: label, context: .none) else { return }
        if state.isDecided, let target { selectedAsset = target }
        else if !folder.filteredImages.contains(asset) { selectedAsset = target }
    }

    /// Set the triage state of any asset with undo (used by detail panel / context menus).
    @discardableResult
    func setState(_ state: TriageState, on asset: ImageAsset, label: String, context: UndoContext = .none) -> Bool {
        let from = asset.triageState
        guard from != state else { return true }
        do {
            try asset.setTriageState(state)
            pushUndo(.stateChange([StateChange(asset: asset, from: from, to: state)], label: label, context: context))
            showToast("\(state.label) · \(asset.displayName)")
            return true
        } catch {
            errorMessage = "Failed to update \(asset.displayName): \(error.localizedDescription)"
            return false
        }
    }

    /// Next image in `list` after `asset`, falling back to the previous one.
    static func neighbor(of asset: ImageAsset, in list: [ImageAsset]) -> ImageAsset? {
        guard let i = list.firstIndex(of: asset) else { return nil }
        if i + 1 < list.count { return list[i + 1] }
        if i - 1 >= 0 { return list[i - 1] }
        return nil
    }

    /// Mark `asset` kept if it has no decision yet (arrow-key navigation in Preview and Triage).
    private func autoKeep(_ asset: ImageAsset, context: UndoContext) {
        guard !asset.triageState.isDecided else { return }
        let from = asset.triageState
        do {
            try asset.setTriageState(.kept)
            pushUndo(.stateChange([StateChange(asset: asset, from: from, to: .kept)], label: "Keep", context: context))
        } catch {
            errorMessage = "Failed to mark image: \(error.localizedDescription)"
        }
    }

    // MARK: - Triage Operations

    /// Similarity details for the current candidate (score, time gap, …)
    var currentCandidateInfo: SimilarityCandidate? {
        guard candidatesList.indices.contains(candidateIndex),
              candidatesList[candidateIndex].asset == triageCandidate else { return nil }
        return candidatesList[candidateIndex]
    }

    /// Number of candidates available for the current anchor
    var candidateCount: Int { candidatesList.count }

    /// Position of the anchor in the triage order, e.g. (11, 340)
    var triagePosition: (index: Int, count: Int)? {
        guard let folder, let anchor = triageAnchor else { return nil }
        let order = folder.sortedImages
        guard let i = order.firstIndex(of: anchor) else { return nil }
        return (i, order.count)
    }

    /// Move to next anchor (forward navigation). Every image is visited — kept and trashed
    /// ones included — so earlier decisions can be revisited. An undecided anchor is auto-kept.
    func nextTriageAnchor() {
        guard let anchor = triageAnchor, let folder = folder else { return }

        autoKeep(anchor, context: .triage(anchor: anchor, candidate: triageCandidate))

        let order = folder.sortedImages
        if let i = order.firstIndex(of: anchor), i + 1 < order.count {
            triageAnchor = order[i + 1]
            triageFinished = false
            updateCandidates()
            saveProgress()
        } else {
            triageFinished = true
        }
    }

    /// Move to previous anchor
    func previousTriageAnchor() {
        guard let anchor = triageAnchor, let folder = folder else { return }
        if triageFinished {
            triageFinished = false
            return
        }
        let order = folder.sortedImages
        if let i = order.firstIndex(of: anchor), i > 0 {
            triageAnchor = order[i - 1]
            updateCandidates()
            saveProgress()
        } else {
            showToast("First photo")
        }
    }

    /// Restart triage from the first image (used by the completion screen)
    func restartTriage() {
        triageFinished = false
        showTriage(from: folder?.sortedImages.first)
    }

    /// Move to next candidate (down)
    func nextCandidate() {
        if candidateIndex < candidatesList.count - 1 {
            candidateIndex += 1
            triageCandidate = candidatesList[candidateIndex].asset
            prefetchTriage()
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
        guard let candidate = triageCandidate else { return }
        guard applyTriageDecision(anchor: .kept, candidate: .trashed, label: "Keep Left") else { return }
        advanceToNextCandidate(skipping: candidate.id)
    }

    /// Keep right (candidate), trash left (anchor)
    func keepRight() {
        guard let candidate = triageCandidate else { return }
        guard applyTriageDecision(anchor: .trashed, candidate: .kept, label: "Keep Right") else { return }
        // Right becomes new anchor
        triageAnchor = candidate
        updateCandidates()
        saveProgress()
    }

    /// Keep both images and stay on the same pair so the user can swap / continue manually
    func keepBoth() {
        _ = applyTriageDecision(anchor: .kept, candidate: .kept, label: "Keep Both")
    }

    /// Trash both images
    func keepNone() {
        guard applyTriageDecision(anchor: .trashed, candidate: .trashed, label: "Trash Both") else { return }
        nextTriageAnchor()
    }

    /// Apply a decision to both triage panes as one undoable step.
    private func applyTriageDecision(anchor anchorState: TriageState, candidate candidateState: TriageState,
                                     label: String) -> Bool {
        guard let anchor = triageAnchor, let candidate = triageCandidate else { return false }
        let changes = [
            StateChange(asset: anchor, from: anchor.triageState, to: anchorState),
            StateChange(asset: candidate, from: candidate.triageState, to: candidateState)
        ]
        do {
            try anchor.setTriageState(anchorState)
            try candidate.setTriageState(candidateState)
            pushUndo(.stateChange(changes, label: label, context: .triage(anchor: anchor, candidate: candidate)))
            showToast(label)
            return true
        } catch {
            errorMessage = "Failed to update images: \(error.localizedDescription)"
            return false
        }
    }

    /// Promote the current candidate to anchor and rebuild the candidate list for it.
    func swapTriagePair() {
        guard let candidate = triageCandidate else { return }
        let oldAnchor = triageAnchor
        triageAnchor = candidate
        updateCandidates()
        // Keep the old anchor visible on the right so the swap reads as a swap
        if let oldAnchor, let idx = candidatesList.firstIndex(where: { $0.asset == oldAnchor }) {
            candidateIndex = idx
            triageCandidate = oldAnchor
        } else if triageCandidate == nil {
            triageCandidate = oldAnchor
        }
        saveProgress()
    }

    /// Number of photos currently marked for trash
    var trashedCount: Int {
        folder?.images.filter(\.isTrashed).count ?? 0
    }

    /// Ask for confirmation before emptying the trash (toolbar, menu and ⌘⌫ all come here)
    func requestEmptyTrash() {
        if trashedCount > 0 {
            showEmptyTrashConfirmation = true
        } else {
            showToast("Nothing is marked for trash")
        }
    }

    /// Move all .trash-marked images in the current folder to macOS Trash
    func emptyTrash() {
        guard let folder = folder else { return }
        Task {
            let result = await trashService.executeTrash(for: folder)
            if !result.isSuccess {
                errorMessage = "Failed to trash some files: \(result.errors.joined(separator: ", "))"
            } else if result.trashedCount > 0 {
                showToast("Moved \(result.trashedCount) photo\(result.trashedCount == 1 ? "" : "s") to the Trash")
            }
            // Rescan so removed files disappear from the images list
            await folder.scan()
            // Drop references to assets that no longer exist
            let remaining = Set(folder.images.map(\.displayURL))
            if let s = selectedAsset, !remaining.contains(s.displayURL) { selectedAsset = folder.filteredImages.first }
            if let p = previewAsset, !remaining.contains(p.displayURL) { previewAsset = folder.filteredImages.first }
            if let a = triageAnchor, !remaining.contains(a.displayURL) { triageAnchor = nil }
            // Undo entries point at deleted files
            undoStack.removeAll()
            redoStack.removeAll()
            if currentView == .triage { showTriage() }
        }
    }

    /// Toggle favorite on an asset
    func toggleFavorite(on asset: ImageAsset) {
        do {
            try asset.toggleFavorite()
            pushUndo(.toggleFavorite(asset))
        } catch {
            errorMessage = "Failed to toggle favorite: \(error.localizedDescription)"
        }
    }

    // MARK: - File edits

    /// Rotate 90° and bake it into the JPEG
    func rotate(_ asset: ImageAsset, clockwise: Bool) async {
        await performFileEdit(on: asset, label: clockwise ? "Rotate Right" : "Rotate Left") {
            _ = try await CropService().applyRotation(to: asset.displayURL, clockwise: clockwise)
        }
    }

    /// Bake crop + horizon + tone adjustments into the JPEG. Returns true on success.
    @discardableResult
    func applyEdit(to asset: ImageAsset, cropRect: CropRect, rotation: Double,
                   adjustments: ImageAdjustments, sourceURL: URL?) async -> Bool {
        await performFileEdit(on: asset, label: "Edit") {
            _ = try await CropService().applyCrop(to: asset.displayURL, cropRect: cropRect, rotation: rotation,
                                                  adjustments: adjustments, sourceURL: sourceURL)
        }
    }

    /// Replace the file with its pristine backup (undoable)
    func restoreOriginal(_ asset: ImageAsset) async {
        await performFileEdit(on: asset, label: "Restore Original") {
            try await CropService().restoreOriginal(for: asset.displayURL)
        }
    }

    /// Snapshot → edit → snapshot, then record the edit for undo and refresh every view of the file.
    @discardableResult
    private func performFileEdit(on asset: ImageAsset, label: String,
                                 _ operation: () async throws -> Void) async -> Bool {
        let url = asset.displayURL
        guard url.isJPEG else {
            errorMessage = CropError.rawNotSupported.localizedDescription
            return false
        }
        var before: EditSnapshot?
        do {
            before = try EditHistory.capture(url)
            try await operation()
            let after = try EditHistory.capture(url)
            pushUndo(.fileEdit(asset, before: before!, after: after, label: label))
            didModifyFile(asset)
            showToast(label == "Edit" ? "Edit saved" : label)
            return true
        } catch {
            if let before { EditHistory.discard(before) }
            errorMessage = "\(label) failed: \(error.localizedDescription)"
            return false
        }
    }

    /// Invalidate every cache derived from the file's pixels and bump reload tokens.
    private func didModifyFile(_ asset: ImageAsset) {
        let url = asset.displayURL
        ImagePipeline.shared.invalidate(url)
        Task { await ClippingAnalyzer.shared.invalidate(url: url) }
        cropVersion += 1
        asset.thumbnailVersion += 1
        let exif = EXIFReader.read(from: url)
        asset.exifMetadata = exif
        if let w = exif.imageWidth, let h = exif.imageHeight {
            asset.imageSize = CGSize(width: w, height: h)
        }
    }

    // MARK: - Undo/Redo

    private func pushUndo(_ action: UndoAction) {
        undoStack.append(action)
        redoStack.removeAll()
    }

    func undo() {
        guard let action = undoStack.popLast() else { return }

        if case .fileEdit(let asset, let before, _, let label) = action {
            do {
                try EditHistory.restore(before, to: asset.displayURL)
                redoStack.append(action)
                didModifyFile(asset)
                reveal(asset)
                showToast("Undo \(label)")
            } catch {
                undoStack.append(action)
                errorMessage = "Undo failed: \(error.localizedDescription)"
            }
            return
        }

        do {
            switch action {
            case .toggleFavorite(let asset):
                try asset.toggleFavorite()
                reveal(asset)
            case .stateChange(let changes, _, let context):
                for change in changes.reversed() {
                    try change.asset.setTriageState(change.from)
                }
                restore(context)
            case .fileEdit:
                break  // handled above
            }
            redoStack.append(action)
            showToast("Undo \(action.label)")
        } catch {
            errorMessage = "Undo failed: \(error.localizedDescription)"
        }
    }

    func redo() {
        guard let action = redoStack.popLast() else { return }

        if case .fileEdit(let asset, let before, let after, let label) = action {
            do {
                // If undo removed the backup (first edit), the "before" copy *is* the original
                try EditHistory.restore(after, to: asset.displayURL,
                                        originalIfMissing: before.hadBackup ? nil : before.imageCopy)
                undoStack.append(action)
                didModifyFile(asset)
                reveal(asset)
                showToast("Redo \(label)")
            } catch {
                redoStack.append(action)
                errorMessage = "Redo failed: \(error.localizedDescription)"
            }
            return
        }

        do {
            switch action {
            case .toggleFavorite(let asset):
                try asset.toggleFavorite()
            case .stateChange(let changes, _, _):
                for change in changes {
                    try change.asset.setTriageState(change.to)
                }
            case .fileEdit:
                break  // handled above
            }
            undoStack.append(action)
            showToast("Redo \(action.label)")
        } catch {
            errorMessage = "Redo failed: \(error.localizedDescription)"
        }
    }

    /// Label of the action ⌘Z would undo (for menu titles)
    var undoLabel: String? { undoStack.last?.label }
    /// Label of the action ⌘⇧Z would redo
    var redoLabel: String? { redoStack.last?.label }

    /// Bring the user back to where an undone action happened
    private func restore(_ context: UndoContext) {
        switch context {
        case .none:
            break
        case .preview(let asset):
            reveal(asset)
        case .triage(let anchor, let candidate):
            guard currentView == .triage else { return }
            triageFinished = false
            triageAnchor = anchor
            updateCandidates()
            if let candidate {
                if let idx = candidatesList.firstIndex(where: { $0.asset == candidate }) {
                    candidateIndex = idx
                }
                triageCandidate = candidate
            }
        }
    }

    /// Show `asset` in the current view (preview navigates to it; gallery selects it)
    private func reveal(_ asset: ImageAsset) {
        switch currentView {
        case .preview:
            if folder?.filteredImages.contains(asset) == true {
                previewAsset = asset
                previewIndex = folder?.index(of: asset) ?? previewIndex
            }
        case .gallery:
            selectedAsset = asset
        case .triage:
            break
        }
    }

    // MARK: - Toast

    /// Flash a brief confirmation message over the current view
    func showToast(_ message: String) {
        toast = message
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            guard !Task.isCancelled else { return }
            self?.toast = nil
        }
    }

    // MARK: - Private

    /// Stay on the current anchor but move to the next viable candidate.
    /// Skips only `excludedID` (the one just acted on); kept/reviewed images remain visible
    /// so the user can compare the anchor against previously-kept similar shots.
    /// Falls through to nextTriageAnchor() when no candidates remain.
    private func advanceToNextCandidate(skipping excludedID: UUID) {
        guard let anchor = triageAnchor, let folder = folder else { return }

        let all = similarityEngine.findCandidates(for: anchor, in: folder)
        let filtered = applyFilter(all)
        if let idx = filtered.firstIndex(where: { $0.asset.id != excludedID }) {
            candidatesList = filtered
            candidateIndex = idx
            triageCandidate = filtered[idx].asset
            prefetchTriage()
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
        prefetchTriage()
    }

    /// Warm the cache for the next candidate and the next anchor.
    private func prefetchTriage() {
        var urls: [URL] = []
        if candidatesList.indices.contains(candidateIndex + 1) {
            urls.append(candidatesList[candidateIndex + 1].asset.displayURL)
        }
        if let folder, let anchor = triageAnchor {
            let order = folder.sortedImages
            if let i = order.firstIndex(of: anchor), i + 1 < order.count {
                urls.append(order[i + 1].displayURL)
            }
        }
        ImagePipeline.shared.prefetch(urls)
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
