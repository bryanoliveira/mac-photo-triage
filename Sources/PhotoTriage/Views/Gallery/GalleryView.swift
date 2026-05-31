import SwiftUI

/// Main gallery view with resizable thumbnail grid
struct GalleryView: View {
    @EnvironmentObject var appState: AppState
    @State private var showingOpenPanel = false

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 4), count: appState.galleryColumns)
    }

    var body: some View {
        HSplitView {
            // Main grid
            VStack(spacing: 0) {
                // Toolbar
                GalleryToolbar(showingOpenPanel: $showingOpenPanel)

                // Grid or empty state
                if let folder = appState.folder {
                    if folder.filteredImages.isEmpty {
                        emptyState(for: folder)
                    } else {
                        gridView(for: folder)
                    }
                } else {
                    noFolderState
                }
            }
            .frame(minWidth: 400)

            // Detail panel
            if appState.showDetailPanel, let selected = appState.selectedAsset {
                DetailPanel(asset: selected)
                    .frame(minWidth: 280, maxWidth: 400)
            }
        }
        .fileImporter(
            isPresented: $showingOpenPanel,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    Task {
                        await appState.openFolder(url)
                    }
                }
            case .failure(let error):
                appState.errorMessage = error.localizedDescription
            }
        }
        .focusedKeyboardHandler { action in
            handleKeyAction(action)
        }
    }

    @ViewBuilder
    private func gridView(for folder: ImageFolder) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(columns: columns, spacing: 4) {
                    ForEach(folder.filteredImages) { asset in
                        GalleryThumbnail(
                            asset: asset,
                            isSelected: appState.selectedAsset?.id == asset.id
                        )
                        .id(asset.id)
                        .onTapGesture {
                            appState.selectedAsset = asset
                        }
                        .onTapGesture(count: 2) {
                            appState.showPreview(for: asset)
                        }
                    }
                }
                .padding(8)
            }
            .background(Color(NSColor.controlBackgroundColor))
            .onAppear {
                scrollToSelected(proxy: proxy)
            }
            .onChange(of: appState.currentView) { _, view in
                if view == .gallery { scrollToSelected(proxy: proxy) }
            }
        }
    }

    private func scrollToSelected(proxy: ScrollViewProxy) {
        guard let id = appState.selectedAsset?.id else { return }
        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.25)) {
                proxy.scrollTo(id, anchor: .center)
            }
        }
    }

    @ViewBuilder
    private func emptyState(for folder: ImageFolder) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text("No images match the current filter")
                .font(.headline)
                .foregroundColor(.secondary)

            if folder.filter != .all {
                Button("Show All Images") {
                    folder.filter = .all
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.controlBackgroundColor))
    }

    private var noFolderState: some View {
        VStack(spacing: 16) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text("Open a folder to get started")
                .font(.headline)
                .foregroundColor(.secondary)

            Button("Open Folder...") {
                showingOpenPanel = true
            }
            .keyboardShortcut("o", modifiers: .command)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.controlBackgroundColor))
    }

    private func handleKeyAction(_ action: KeyAction) -> Bool {
        switch action {
        case .navigateLeft:
            selectPrevious()
            return true
        case .navigateRight:
            selectNext()
            return true
        case .gridIncrease:
            appState.galleryColumns = max(2, appState.galleryColumns - 1)
            return true
        case .gridDecrease:
            appState.galleryColumns = min(12, appState.galleryColumns + 1)
            return true
        case .toggleFavorite:
            if let asset = appState.selectedAsset {
                appState.toggleFavorite(on: asset)
            }
            return true
        case .switchToTriage:
            if let asset = appState.selectedAsset {
                appState.showTriage(from: asset)
            }
            return true
        case .toggleEXIF:
            appState.showEXIFOverlay.toggle()
            return true
        case .undo:
            appState.undo()
            return true
        case .redo:
            appState.redo()
            return true
        case .openFolder:
            showingOpenPanel = true
            return true
        case .emptyTrash:
            if appState.folder != nil {
                appState.emptyTrash()
            }
            return true
        default:
            return false
        }
    }

    private func selectNext() {
        guard let folder = appState.folder,
              let current = appState.selectedAsset,
              let index = folder.index(of: current) else { return }

        let images = folder.filteredImages
        if index < images.count - 1 {
            appState.selectedAsset = images[index + 1]
        }
    }

    private func selectPrevious() {
        guard let folder = appState.folder,
              let current = appState.selectedAsset,
              let index = folder.index(of: current) else { return }

        if index > 0 {
            let images = folder.filteredImages
            appState.selectedAsset = images[index - 1]
        }
    }
}

/// Gallery toolbar with filter/sort controls
struct GalleryToolbar: View {
    @EnvironmentObject var appState: AppState
    @Binding var showingOpenPanel: Bool
    @State private var showingEmptyTrashAlert = false

    private var trashedCount: Int {
        appState.folder?.images.filter { $0.isTrashed }.count ?? 0
    }

    var body: some View {
        HStack {
            // Open folder button
            Button(action: { showingOpenPanel = true }) {
                Label("Open", systemImage: "folder")
            }

            Divider()
                .frame(height: 20)

            // Empty trash button
            if appState.folder != nil {
                Button(action: { showingEmptyTrashAlert = true }) {
                    Label("Empty Trash (\(trashedCount))", systemImage: "trash")
                        .foregroundStyle(trashedCount > 0 ? .red : .secondary)
                }
                .disabled(trashedCount == 0)
                .help("Move all trash-marked images to macOS Trash (⌘⌫)")
                .alert("Empty Trash?", isPresented: $showingEmptyTrashAlert) {
                    Button("Move \(trashedCount) image(s) to Trash", role: .destructive) {
                        appState.emptyTrash()
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This moves \(trashedCount) image(s) marked for trash to the macOS Trash. The files can be recovered from Trash before you empty it.")
                }

                Divider()
                    .frame(height: 20)
            }

            // Filter picker
            if let folder = appState.folder {
                Picker("Filter", selection: Binding(
                    get: { appState.folder?.filter ?? .all },
                    set: { appState.folder?.filter = $0 }
                )) {
                    ForEach(ImageFilter.allCases) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 300)

                Spacer()

                // Sort picker
                Picker("Sort", selection: Binding(
                    get: { appState.folder?.sort ?? .dateAscending },
                    set: { appState.folder?.sort = $0 }
                )) {
                    ForEach(ImageSort.allCases) { sort in
                        Text(sort.rawValue).tag(sort)
                    }
                }
                .frame(width: 120)

                Divider()
                    .frame(height: 20)

                // Statistics
                let stats = folder.statistics
                Text(stats.summary)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Detail panel toggle
            Button(action: { appState.showDetailPanel.toggle() }) {
                Image(systemName: appState.showDetailPanel ? "sidebar.right" : "sidebar.right")
            }
            .help("Toggle Detail Panel")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(NSColor.windowBackgroundColor))
    }
}
