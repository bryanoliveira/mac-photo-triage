import SwiftUI
import CoreGraphics
import ImageIO

/// Full image preview mode with editing capabilities
struct PreviewView: View {
    @EnvironmentObject var appState: AppState

    @State private var isEditing = false
    @State private var zoomResetToken: Int = 0
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
            // Toolbar
            PreviewToolbar(
                isEditing: $isEditing,
                hasOriginalBackup: hasOriginalBackup,
                onRotateCCW: { applyRotation(clockwise: false) },
                onRotateCW:  { applyRotation(clockwise: true) },
                onEnterEdit: enterEditMode,
                onApplyEdit: applyEdit,
                onCancelEdit: cancelEditMode,
                onRestoreOriginal: restoreOriginal
            )

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
                            initialCropHint: cropInitialHint
                        )
                    } else {
                        ZoomableImageView(
                            url: asset.displayURL,
                            showClippingWarnings: appState.showClippingWarnings,
                            reloadToken: appState.cropVersion,
                            resetZoomToken: zoomResetToken
                        )
                        .overlay {
                            if appState.showGuidingGrid { GuidingGridOverlay() }
                        }
                        .exifOverlay(
                            asset.exifMetadata,
                            isVisible: appState.showEXIFOverlay,
                            position: .bottomLeading
                        )
                    }

                    // Favorite button
                    VStack {
                        HStack {
                            Spacer()
                            FavoriteButton(asset: asset, size: .large) {
                                appState.toggleFavorite(on: asset)
                            }
                            .background(.ultraThinMaterial, in: Circle())
                        }
                        Spacer()
                    }
                    .padding()
                } else {
                    Text("No image selected")
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)

            // Navigation bar
            PreviewNavigationBar()
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

    // MARK: - Key handling

    private func handleKeyAction(_ action: KeyAction) -> Bool {
        switch action {
        case .navigateLeft:
            appState.previousPreviewImage()
            return true
        case .navigateRight:
            appState.nextPreviewImage()
            return true
        case .rotateCCW:
            applyRotation(clockwise: false)
            return true
        case .rotateCW:
            applyRotation(clockwise: true)
            return true
        case .toggleZoom:
            zoomResetToken += 1
            return true
        case .toggleEXIF:
            appState.showEXIFOverlay.toggle()
            return true
        case .toggleClipping:
            appState.showClippingWarnings.toggle()
            return true
        case .toggleGrid:
            appState.showGuidingGrid.toggle()
            return true
        case .switchToGallery:
            appState.showGallery()
            return true
        case .switchToTriage:
            if let asset = appState.previewAsset {
                appState.showTriage(from: asset)
            }
            return true
        case .toggleFavorite:
            if let asset = appState.previewAsset {
                appState.toggleFavorite(on: asset)
            }
            return true
        case .trashCurrentImage:
            appState.trashPreviewImage()
            return true
        case .applyCrop:
            if isEditing { applyEdit() }
            return true
        case .cancelCrop:
            if isEditing {
                cancelEditMode()
            } else {
                appState.showGallery()
            }
            return true
        case .undo:
            appState.undo()
            return true
        case .redo:
            appState.redo()
            return true
        default:
            return false
        }
    }

    // MARK: - Actions

    private func enterEditMode() {
        guard let asset = appState.previewAsset else { return }
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
        guard let curr = displayPixelSize(for: currentURL),
              let orig = displayPixelSize(for: originalURL) else { return nil }
        let cx = (orig.width - curr.width) / 2
        let cy = (orig.height - curr.height) / 2
        return CropRect(x: max(0, cx), y: max(0, cy),
                        width: min(curr.width, orig.width),
                        height: min(curr.height, orig.height))
    }

    /// Pixel dimensions in display space (EXIF orientation applied — may swap W/H).
    private func displayPixelSize(for url: URL) -> CGSize? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? CGFloat,
              let h = props[kCGImagePropertyPixelHeight] as? CGFloat else { return nil }
        switch source.exifOrientation {
        case .right, .left, .rightMirrored, .leftMirrored: return CGSize(width: h, height: w)
        default: return CGSize(width: w, height: h)
        }
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
        guard let asset = appState.previewAsset else { return }
        Task {
            let service = CropService()
            do {
                _ = try await service.applyRotation(to: asset.displayURL, clockwise: clockwise)
                appState.recordRotationApplied(to: asset, clockwise: clockwise)
            } catch {
                appState.errorMessage = error.localizedDescription
            }
        }
    }

    private func applyEdit() {
        guard let asset = appState.previewAsset,
              let crop = cropRect else { return }

        let fineRot = cropFineRotation
        let adj = imageAdjustments
        let src = cropSourceURL
        Task {
            let service = CropService()
            do {
                _ = try await service.applyCrop(to: asset.displayURL, cropRect: crop,
                                                rotation: fineRot, adjustments: adj, sourceURL: src)
                appState.recordCropApplied(to: asset, cropRect: crop, rotation: fineRot)
                cancelEditMode()
            } catch {
                appState.errorMessage = error.localizedDescription
            }
        }
    }

    private func restoreOriginal() {
        guard let asset = appState.previewAsset else { return }
        Task {
            let service = CropService()
            do {
                try await service.restoreOriginal(for: asset.displayURL)
                appState.cropVersion += 1
                asset.thumbnailVersion += 1
                hasOriginalBackup = false
            } catch {
                appState.errorMessage = error.localizedDescription
            }
        }
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

/// Preview toolbar with rotation and edit controls
struct PreviewToolbar: View {
    @EnvironmentObject var appState: AppState
    @Binding var isEditing: Bool
    let hasOriginalBackup: Bool
    var onRotateCCW: () -> Void = {}
    var onRotateCW: () -> Void = {}
    var onEnterEdit: () -> Void = {}
    var onApplyEdit: () -> Void = {}
    var onCancelEdit: () -> Void = {}
    var onRestoreOriginal: () -> Void = {}

    var body: some View {
        HStack {
            // Back button
            Button(action: { appState.showGallery() }) {
                Label("Gallery", systemImage: "square.grid.2x2")
            }

            Divider().frame(height: 20)

            // Undo / Redo
            Button(action: { appState.undo() }) {
                Image(systemName: "arrow.uturn.backward")
            }
            .disabled(!appState.canUndo)
            .help("Undo (Cmd+Z)")

            Button(action: { appState.redo() }) {
                Image(systemName: "arrow.uturn.forward")
            }
            .disabled(!appState.canRedo)
            .help("Redo (Cmd+Shift+Z)")

            Divider().frame(height: 20)

            // 90° rotation — baked to file immediately
            Button(action: onRotateCCW) {
                Image(systemName: "rotate.left")
            }
            .help("Rotate 90° CCW — saved to file (Cmd+Left)")
            .disabled(isEditing)

            Button(action: onRotateCW) {
                Image(systemName: "rotate.right")
            }
            .help("Rotate 90° CW — saved to file (Cmd+Right)")
            .disabled(isEditing)

            Divider().frame(height: 20)

            // Restore original
            if hasOriginalBackup {
                Button(action: onRestoreOriginal) {
                    Label("Restore Original", systemImage: "arrow.counterclockwise")
                }
                .help("Restore the unedited original file")
                .disabled(isEditing)

                Divider().frame(height: 20)
            }

            // Edit button
            Button(action: { if isEditing { onCancelEdit() } else { onEnterEdit() } }) {
                Label(isEditing ? "Editing…" : "Edit", systemImage: "slider.horizontal.3")
            }
            .help("Toggle Edit Mode (crop, horizon, exposure)")

            if isEditing {
                Button("Apply", action: onApplyEdit)
                Button("Cancel", action: onCancelEdit)
            }

            Spacer()

            // EXIF toggle
            Button(action: { appState.showEXIFOverlay.toggle() }) {
                Image(systemName: appState.showEXIFOverlay ? "info.circle.fill" : "info.circle")
            }
            .help("Toggle EXIF (I)")

            // Guiding grid toggle
            Button(action: { appState.showGuidingGrid.toggle() }) {
                Image(systemName: "grid")
                    .foregroundStyle(appState.showGuidingGrid ? .blue : .primary)
            }
            .help("Toggle guiding grid (H)")
            .disabled(isEditing)

            // Clipping warnings toggle
            Button(action: { appState.showClippingWarnings.toggle() }) {
                Image(systemName: appState.showClippingWarnings
                    ? "exclamationmark.triangle.fill"
                    : "exclamationmark.triangle")
                .foregroundStyle(appState.showClippingWarnings ? .yellow : .primary)
            }
            .help("Toggle Clipping Warnings (W)")

            // Trash button
            Button(action: { appState.trashPreviewImage() }) {
                Image(systemName: "trash")
                    .foregroundStyle(.red)
            }
            .help("Trash this image (Delete)")
            .disabled(appState.previewAsset == nil)

            // Triage button
            Button(action: {
                if let asset = appState.previewAsset {
                    appState.showTriage(from: asset)
                }
            }) {
                Label("Triage", systemImage: "square.split.2x1")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

// MARK: - Navigation bar

/// Bottom navigation bar showing position
struct PreviewNavigationBar: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        HStack {
            Button(action: { appState.previousPreviewImage() }) {
                Image(systemName: "chevron.left")
            }
            .disabled(appState.previewIndex == 0)

            Spacer()

            if let folder = appState.folder {
                Text("\(appState.previewIndex + 1) / \(folder.filteredImages.count)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button(action: { appState.nextPreviewImage() }) {
                Image(systemName: "chevron.right")
            }
            .disabled(appState.folder.map { appState.previewIndex >= $0.filteredImages.count - 1 } ?? true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(NSColor.windowBackgroundColor))
    }
}
