import SwiftUI

/// Full image preview mode with editing capabilities
struct PreviewView: View {
    @EnvironmentObject var appState: AppState

    @State private var rotation: Angle = .zero
    @State private var showRotationPanel = false
    @State private var isCropping = false
    @State private var cropRect: CropRect?
    @State private var cropPreset: CropPreset = .free
    @State private var imageSize: CGSize = .zero

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            PreviewToolbar(
                rotation: $rotation,
                showRotationPanel: $showRotationPanel,
                isCropping: $isCropping,
                cropPreset: $cropPreset
            )

            // Main image view
            ZStack {
                if let asset = appState.previewAsset {
                    if isCropping {
                        CropOverlay(
                            url: asset.displayURL,
                            cropRect: $cropRect,
                            preset: cropPreset,
                            imageSize: $imageSize
                        )
                    } else {
                        ZoomableImageView(
                            url: asset.displayURL,
                            showClippingWarnings: appState.showClippingWarnings
                        )
                        .rotationEffect(rotation)
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

                    // Fine rotation panel
                    if showRotationPanel {
                        VStack {
                            Spacer()
                            RotationControls(rotation: $rotation) {
                                showRotationPanel = false
                            }
                            .padding(.bottom, 16)
                        }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                } else {
                    Text("No image selected")
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
            .animation(.easeInOut(duration: 0.2), value: showRotationPanel)

            // Navigation bar
            PreviewNavigationBar()
        }
        .focusedKeyboardHandler { action in
            handleKeyAction(action)
        }
        .onAppear {
            // Load EXIF if needed
            if let asset = appState.previewAsset, asset.exifMetadata == nil {
                asset.exifMetadata = EXIFReader.read(from: asset.displayURL)
            }
        }
    }

    private func handleKeyAction(_ action: KeyAction) -> Bool {
        switch action {
        case .navigateLeft:
            appState.previousPreviewImage()
            return true
        case .navigateRight:
            appState.nextPreviewImage()
            return true
        case .rotateCCW:
            rotation -= .degrees(90)
            return true
        case .rotateCW:
            rotation += .degrees(90)
            return true
        case .toggleZoom:
            // Handled by ZoomableImageView
            return false
        case .toggleEXIF:
            appState.showEXIFOverlay.toggle()
            return true
        case .toggleClipping:
            appState.showClippingWarnings.toggle()
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
            if isCropping {
                applyCrop()
            }
            return true
        case .cancelCrop:
            if isCropping {
                isCropping = false
                cropRect = nil
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

    private func applyCrop() {
        guard let asset = appState.previewAsset,
              let crop = cropRect else { return }

        Task {
            let service = CropService()
            do {
                _ = try await service.applyCrop(to: asset.displayURL, cropRect: crop)
                isCropping = false
                cropRect = nil
            } catch {
                appState.errorMessage = error.localizedDescription
            }
        }
    }
}

/// Preview toolbar with rotation and crop controls
struct PreviewToolbar: View {
    @EnvironmentObject var appState: AppState
    @Binding var rotation: Angle
    @Binding var showRotationPanel: Bool
    @Binding var isCropping: Bool
    @Binding var cropPreset: CropPreset

    var body: some View {
        HStack {
            // Back button
            Button(action: { appState.showGallery() }) {
                Label("Gallery", systemImage: "square.grid.2x2")
            }

            Divider()
                .frame(height: 20)

            // Rotation buttons
            Button(action: { rotation -= .degrees(90) }) {
                Image(systemName: "rotate.left")
            }
            .help("Rotate CCW (Cmd+Left)")

            Button(action: { rotation += .degrees(90) }) {
                Image(systemName: "rotate.right")
            }
            .help("Rotate CW (Cmd+Right)")

            // Fine horizon-level button
            Button(action: { showRotationPanel.toggle() }) {
                Image(systemName: showRotationPanel ? "level.fill" : "level")
            }
            .help("Fine rotation / horizon level")

            Divider()
                .frame(height: 20)

            // Crop button
            Button(action: { isCropping.toggle() }) {
                Label("Crop", systemImage: "crop")
            }
            .help("Toggle Crop Mode")

            if isCropping {
                Picker("Aspect", selection: $cropPreset) {
                    ForEach(CropPreset.allCases) { preset in
                        Text(preset.rawValue).tag(preset)
                    }
                }
                .frame(width: 100)

                Button("Apply") {
                    // Handled in PreviewView
                }
                .keyboardShortcut(.return, modifiers: [])

                Button("Cancel") {
                    isCropping = false
                }
                .keyboardShortcut(.escape, modifiers: [])
            }

            Spacer()

            // EXIF toggle
            Button(action: { appState.showEXIFOverlay.toggle() }) {
                Image(systemName: appState.showEXIFOverlay ? "info.circle.fill" : "info.circle")
            }
            .help("Toggle EXIF (I)")

            // Clipping warnings toggle
            Button(action: { appState.showClippingWarnings.toggle() }) {
                Image(systemName: appState.showClippingWarnings
                    ? "exclamationmark.triangle.fill"
                    : "exclamationmark.triangle")
                .foregroundStyle(appState.showClippingWarnings ? .yellow : .primary)
            }
            .help("Toggle Clipping Warnings — red: blown highlights, blue: crushed shadows (W)")

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
