import SwiftUI
import CoreGraphics
import ImageIO

/// Full image preview mode with editing capabilities
struct PreviewView: View {
    @EnvironmentObject var appState: AppState

    @State private var isEditing = false
    @State private var isSaving = false
    @State private var zoomRequest = ZoomRequest()
    @State private var zoomPercent: Int?
    @State private var cropRect: CropRect?
    @State private var cropPreset: CropPreset = .free
    @State private var cropFineRotation: Double = 0
    @State private var imageAdjustments: ImageAdjustments = .init()
    @State private var imageSize: CGSize = .zero
    @State private var hasOriginalBackup: Bool = false
    /// When re-editing a previously-edited image, this points to the backup (original) file
    @State private var cropSourceURL: URL?
    /// Exact crop rect (in original pixel space) to restore when re-entering Edit mode
    @State private var cropInitialHint: CropRect?

    var body: some View {
        VStack(spacing: 0) {
            PreviewToolbar(
                isEditing: isEditing,
                isSaving: isSaving,
                hasOriginalBackup: hasOriginalBackup,
                canApply: cropRect != nil,
                onRotateCCW: { applyRotation(clockwise: false) },
                onRotateCW:  { applyRotation(clockwise: true) },
                onEnterEdit: enterEditMode,
                onApplyEdit: applyEdit,
                onCancelEdit: cancelEditMode,
                onRestoreOriginal: restoreOriginal
            )
            Divider()

            // Main image view
            ZStack {
                if let asset = appState.previewAsset {
                    if isEditing {
                        CropOverlay(
                            url: cropSourceURL ?? asset.displayURL,
                            cropRect: $cropRect,
                            preset: $cropPreset,
                            imageSize: $imageSize,
                            fineRotation: $cropFineRotation,
                            adjustments: $imageAdjustments,
                            initialCropHint: cropInitialHint,
                            showClippingWarnings: appState.showClippingWarnings
                        )
                    } else {
                        ZoomableImageView(
                            url: asset.displayURL,
                            showClippingWarnings: appState.showClippingWarnings,
                            reloadToken: appState.cropVersion,
                            request: zoomRequest,
                            onZoomPercentChange: { zoomPercent = $0 }
                        )
                        .overlay {
                            if appState.showGuidingGrid { GuidingGridOverlay() }
                        }
                        .exifOverlay(
                            asset.exifMetadata,
                            isVisible: appState.showEXIFOverlay,
                            position: .bottomLeading
                        )
                        .overlay(alignment: .top) {
                            imageOverlayBar(for: asset)
                        }
                    }
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "photo")
                            .font(.system(size: 40, weight: .light))
                        Text("No photo to show")
                            .font(.headline)
                        Button("Back to Gallery") { appState.showGallery() }
                    }
                    .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)

            if !isEditing {
                Divider()
                PreviewNavigationBar(zoomPercent: zoomPercent, zoomRequest: $zoomRequest)
            }
        }
        .focusedKeyboardHandler { action in
            handleKeyAction(action)
        }
        .onAppear {
            loadEXIF(for: appState.previewAsset)
            checkBackup()
        }
        .onChange(of: appState.previewAsset) { _, newAsset in
            if isEditing { cancelEditMode() }
            loadEXIF(for: newAsset)
            checkBackup()
        }
        .onChange(of: appState.cropVersion) { _, _ in checkBackup() }
    }

    /// Status pill (top-left) and favorite star (top-right) floating over the photo
    private func imageOverlayBar(for asset: ImageAsset) -> some View {
        HStack(alignment: .top) {
            DecisionBadge(asset: asset, style: .pill, showUnreviewed: true)
                .animation(.easeInOut(duration: 0.15), value: asset.triageState)
            Spacer()
            FavoriteButton(asset: asset, size: .large) {
                appState.toggleFavorite(on: asset)
            }
            .background(.ultraThinMaterial, in: Circle())
        }
        .padding(12)
    }

    // MARK: - Key handling

    private func handleKeyAction(_ action: KeyAction) -> Bool {
        if isEditing {
            // While editing, only edit-related keys are live; navigation/decisions would
            // silently discard the unsaved edit.
            switch action {
            case .applyCrop:
                applyEdit()
            case .cancelCrop:
                cancelEditMode()
            case .toggleClipping:
                appState.showClippingWarnings.toggle()
            case .navigateLeft, .navigateRight, .trashCurrentImage, .keepCurrentImage, .clearDecision,
                 .switchToGallery, .switchToTriage, .rotateCCW, .rotateCW:
                appState.showToast("Apply or cancel the edit first")
            default:
                return false
            }
            return true
        }

        switch action {
        case .navigateLeft:
            appState.previousPreviewImage()
        case .navigateRight:
            appState.nextPreviewImage()
        case .rotateCCW:
            applyRotation(clockwise: false)
        case .rotateCW:
            applyRotation(clockwise: true)
        case .toggleZoom:
            zoomRequest.send(.fit)
        case .zoomActualSize:
            zoomRequest.send(zoomPercent == 100 ? .fit : .actualSize)
        case .gridIncrease:
            zoomRequest.send(.zoomIn)
        case .gridDecrease:
            zoomRequest.send(.zoomOut)
        case .toggleEXIF:
            appState.showEXIFOverlay.toggle()
        case .toggleClipping:
            appState.showClippingWarnings.toggle()
        case .toggleGrid:
            appState.showGuidingGrid.toggle()
        case .switchToGallery:
            appState.showGallery()
        case .switchToTriage:
            if let asset = appState.previewAsset {
                appState.showTriage(from: asset)
            }
        case .toggleFavorite:
            if let asset = appState.previewAsset {
                appState.toggleFavorite(on: asset)
            }
        case .trashCurrentImage:
            appState.trashPreviewImage()
        case .keepCurrentImage:
            appState.keepPreviewImage()
        case .clearDecision:
            appState.clearPreviewImage()
        case .applyCrop:
            enterEditMode()
        case .cancelCrop:
            appState.showGallery()
        case .undo:
            appState.undo()
        case .redo:
            appState.redo()
        case .emptyTrash:
            appState.requestEmptyTrash()
        default:
            return false
        }
        return true
    }

    // MARK: - Actions

    private func enterEditMode() {
        guard let asset = appState.previewAsset else { return }
        guard asset.displayURL.isJPEG else {
            appState.errorMessage = CropError.rawNotSupported.localizedDescription
            return
        }
        let service = CropService()
        let backup = service.backupURL(for: asset.displayURL)
        if FileManager.default.fileExists(atPath: backup.path) {
            cropSourceURL = backup
            if let meta = service.cropMetadata(for: asset.displayURL) {
                cropFineRotation = meta.rotation
                cropInitialHint = CropRect(x: meta.cropX, y: meta.cropY,
                                           width: meta.cropWidth, height: meta.cropHeight)
                imageAdjustments = meta.adjustments ?? .init()
            } else {
                cropFineRotation = 0
                cropInitialHint = centeredCropHint(currentURL: asset.displayURL, originalURL: backup)
                imageAdjustments = .init()
            }
        } else {
            cropSourceURL = nil
            cropFineRotation = 0
            cropInitialHint = nil
            imageAdjustments = .init()
        }
        isEditing = true
    }

    private func cancelEditMode() {
        isEditing = false
        cropRect = nil
        cropFineRotation = 0
        imageAdjustments = .init()
        cropSourceURL = nil
        cropInitialHint = nil
    }

    /// Compute a crop rect centered on the original, matching the current image's display dimensions.
    private func centeredCropHint(currentURL: URL, originalURL: URL) -> CropRect? {
        guard let curr = ImagePipeline.orientedPixelSize(url: currentURL),
              let orig = ImagePipeline.orientedPixelSize(url: originalURL) else { return nil }
        let cx = (orig.width - curr.width) / 2
        let cy = (orig.height - curr.height) / 2
        return CropRect(x: max(0, cx), y: max(0, cy),
                        width: min(curr.width, orig.width),
                        height: min(curr.height, orig.height))
    }

    /// Load EXIF for `asset` on a background thread if not already cached.
    private func loadEXIF(for asset: ImageAsset?) {
        guard let asset, asset.exifMetadata == nil else { return }
        let url = asset.displayURL
        Task {
            let meta = await Task.detached { EXIFReader.read(from: url) }.value
            asset.exifMetadata = meta
        }
    }

    private func applyRotation(clockwise: Bool) {
        guard let asset = appState.previewAsset, !isEditing else { return }
        Task { await appState.rotate(asset, clockwise: clockwise) }
    }

    private func applyEdit() {
        guard let asset = appState.previewAsset, let crop = cropRect, !isSaving else { return }
        isSaving = true
        let fineRot = cropFineRotation
        let adj = imageAdjustments
        let src = cropSourceURL
        Task {
            let ok = await appState.applyEdit(to: asset, cropRect: crop, rotation: fineRot,
                                              adjustments: adj, sourceURL: src)
            isSaving = false
            if ok { cancelEditMode() }
        }
    }

    private func restoreOriginal() {
        guard let asset = appState.previewAsset else { return }
        Task { await appState.restoreOriginal(asset) }
    }

    private func checkBackup() {
        guard let asset = appState.previewAsset else {
            hasOriginalBackup = false
            return
        }
        Task {
            hasOriginalBackup = await CropService().hasBackup(for: asset.displayURL)
        }
    }
}

// MARK: - Toolbar

/// Preview toolbar with rotation and edit controls. Collapses to icons on narrow windows.
struct PreviewToolbar: View {
    @EnvironmentObject var appState: AppState
    let isEditing: Bool
    let isSaving: Bool
    let hasOriginalBackup: Bool
    let canApply: Bool
    var onRotateCCW: () -> Void = {}
    var onRotateCW: () -> Void = {}
    var onEnterEdit: () -> Void = {}
    var onApplyEdit: () -> Void = {}
    var onCancelEdit: () -> Void = {}
    var onRestoreOriginal: () -> Void = {}

    var body: some View {
        ViewThatFits(in: .horizontal) {
            row(compact: false)
            row(compact: true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private func row(compact: Bool) -> some View {
        HStack(spacing: 8) {
            ToolbarButton(title: "Gallery", systemImage: "square.grid.2x2", compact: compact,
                          help: "Back to Gallery (G)") { appState.showGallery() }
                .disabled(isEditing)

            Divider().frame(height: 18)

            ToolbarButton(title: "Undo", systemImage: "arrow.uturn.backward", compact: true,
                          help: appState.undoLabel.map { "Undo \($0) (⌘Z)" } ?? "Undo (⌘Z)") { appState.undo() }
                .disabled(!appState.canUndo || isEditing)
            ToolbarButton(title: "Redo", systemImage: "arrow.uturn.forward", compact: true,
                          help: appState.redoLabel.map { "Redo \($0) (⌘⇧Z)" } ?? "Redo (⌘⇧Z)") { appState.redo() }
                .disabled(!appState.canRedo || isEditing)

            Divider().frame(height: 18)

            ToolbarButton(title: "Rotate Left", systemImage: "rotate.left", compact: true,
                          help: "Rotate 90° left — saved to file (⌘←)", action: onRotateCCW)
                .disabled(isEditing)
            ToolbarButton(title: "Rotate Right", systemImage: "rotate.right", compact: true,
                          help: "Rotate 90° right — saved to file (⌘→)", action: onRotateCW)
                .disabled(isEditing)

            Divider().frame(height: 18)

            if isEditing {
                Button("Cancel", action: onCancelEdit)
                    .keyboardShortcut(.cancelAction)
                    .fixedSize()
                Button(action: onApplyEdit) {
                    if isSaving {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Apply")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canApply || isSaving)
                .help("Save crop, horizon and tone changes to the file (↩)")
                .fixedSize()
            } else {
                ToolbarButton(title: "Edit", systemImage: "slider.horizontal.3", compact: compact,
                              help: "Crop, straighten and adjust tone (↩)", action: onEnterEdit)
                    .disabled(appState.previewAsset?.displayURL.isJPEG != true)

                if hasOriginalBackup {
                    ToolbarButton(title: "Restore Original", systemImage: "arrow.counterclockwise", compact: compact,
                                  help: "Replace the edited file with the unedited original (undoable)",
                                  action: onRestoreOriginal)
                }
            }

            Spacer(minLength: 8)

            ToggleIconButton(isOn: appState.showEXIFOverlay, systemImage: "info.circle",
                             help: "Photo info (I)") { appState.showEXIFOverlay.toggle() }
                .disabled(isEditing)
            ToggleIconButton(isOn: appState.showGuidingGrid, systemImage: "grid",
                             help: "Guiding grid (H)") { appState.showGuidingGrid.toggle() }
                .disabled(isEditing)
            ToggleIconButton(isOn: appState.showClippingWarnings, systemImage: "exclamationmark.triangle",
                             help: "Clipping warnings — red: blown highlights, blue: crushed shadows (W)") {
                appState.showClippingWarnings.toggle()
            }

            Divider().frame(height: 18)

            ToolbarButton(title: "Triage", systemImage: "square.split.2x1", compact: compact,
                          help: "Compare with similar photos (T)") {
                if let asset = appState.previewAsset { appState.showTriage(from: asset) }
            }
            .disabled(isEditing)
        }
    }
}

// MARK: - Navigation bar

/// Bottom bar: previous/next, keep/trash decision, position and zoom.
struct PreviewNavigationBar: View {
    @EnvironmentObject var appState: AppState
    let zoomPercent: Int?
    @Binding var zoomRequest: ZoomRequest

    var body: some View {
        ViewThatFits(in: .horizontal) {
            row(showName: true)
            row(showName: false)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private func row(showName: Bool) -> some View {
        HStack(spacing: 12) {
            Button(action: { appState.previousPreviewImage() }) {
                Image(systemName: "chevron.left")
                    .frame(width: 18)
            }
            .help("Previous photo (←) — keeps the current photo if undecided")
            .disabled(appState.previewPosition?.index == 0)

            if let asset = appState.previewAsset {
                DecisionControl(asset: asset)
                    .fixedSize()
            }

            Spacer(minLength: 8)

            VStack(spacing: 1) {
                if let pos = appState.previewPosition {
                    Text("\(pos.index + 1) of \(pos.count)")
                        .font(.caption.monospacedDigit())
                } else if let folder = appState.folder {
                    Text("Not in “\(folder.filter.rawValue)”")
                        .font(.caption)
                }
                if showName, let asset = appState.previewAsset {
                    Text(asset.displayName)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .fixedSize()

            Spacer(minLength: 8)

            ZoomControls(zoomPercent: zoomPercent, zoomRequest: $zoomRequest)
                .fixedSize()

            Button(action: { appState.nextPreviewImage() }) {
                Image(systemName: "chevron.right")
                    .frame(width: 18)
            }
            .help("Next photo (→) — keeps the current photo if undecided")
        }
    }
}

/// Keep / Undecided / Trash segmented control reflecting (and changing) an image's decision.
struct DecisionControl: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var asset: ImageAsset

    var body: some View {
        HStack(spacing: 0) {
            segment(.kept, title: "Keep", icon: "checkmark", help: "Keep (K)")
            segment(.unreviewed, title: "Undecided", icon: "minus", help: "Clear decision (U)")
            segment(.trashed, title: "Trash", icon: "trash", help: "Mark for trash (⌫)")
        }
        .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.primary.opacity(0.12)))
    }

    private func segment(_ state: TriageState, title: String, icon: String, help: String) -> some View {
        let current = asset.triageState.isDecided ? asset.triageState : .unreviewed
        let isOn = current == state
        return Button {
            switch state {
            case .kept: appState.keepPreviewImage()
            case .trashed: appState.trashPreviewImage()
            default: appState.clearPreviewImage()
            }
        } label: {
            Label(title, systemImage: icon)
                .font(.callout.weight(isOn ? .semibold : .regular))
                .foregroundStyle(isOn ? (state == .unreviewed ? Color.primary : Color.white) : Color.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(isOn ? (state == .unreviewed ? Color.primary.opacity(0.15) : state.color) : .clear,
                            in: RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(2)
        .help(help)
    }
}

/// Zoom percentage with fit / 100% / ± controls
struct ZoomControls: View {
    let zoomPercent: Int?
    @Binding var zoomRequest: ZoomRequest

    var body: some View {
        HStack(spacing: 4) {
            Button { zoomRequest.send(.zoomOut) } label: { Image(systemName: "minus.magnifyingglass") }
                .buttonStyle(.borderless)
                .help("Zoom out (−)")
            Menu {
                Button("Fit to Window") { zoomRequest.send(.fit) }
                Button("Actual Size (100%)") { zoomRequest.send(.actualSize) }
            } label: {
                Text(zoomPercent.map { "\($0)%" } ?? "Fit")
                    .font(.caption.monospacedDigit())
                    .frame(minWidth: 38)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Space: fit · Z: 100% · double-click to toggle")
            Button { zoomRequest.send(.zoomIn) } label: { Image(systemName: "plus.magnifyingglass") }
                .buttonStyle(.borderless)
                .help("Zoom in (+)")
        }
    }
}

// MARK: - Shared toolbar controls

/// Toolbar button that shows a label when there is room and just the icon when compact.
struct ToolbarButton: View {
    let title: String
    let systemImage: String
    var compact: Bool = false
    var help: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            if compact {
                Image(systemName: systemImage)
                    .frame(minWidth: 16)
            } else {
                Label(title, systemImage: systemImage)
            }
        }
        .help(help ?? title)
        .accessibilityLabel(title)
        .fixedSize()
    }
}

/// Icon button that renders filled + tinted while its option is on.
struct ToggleIconButton: View {
    let isOn: Bool
    let systemImage: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .symbolVariant(isOn ? .fill : .none)
                .foregroundStyle(isOn ? Color.accentColor : Color.primary)
                .frame(minWidth: 16)
        }
        .help(help)
        .fixedSize()
    }
}
