import SwiftUI

/// Main gallery view with resizable thumbnail grid
struct GalleryView: View {
    @EnvironmentObject var appState: AppState
    @State private var showingOpenPanel = false

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 6), count: appState.galleryColumns)
    }

    var body: some View {
        HSplitView {
            // Main grid
            VStack(spacing: 0) {
                GalleryToolbar(showingOpenPanel: $showingOpenPanel)
                Divider()

                // Grid or empty state
                if let folder = appState.folder {
                    if folder.images.isEmpty {
                        emptyFolderState
                    } else if folder.filteredImages.isEmpty {
                        emptyState(for: folder)
                    } else {
                        gridView(for: folder)
                    }
                    Divider()
                    GalleryStatusBar()
                } else {
                    noFolderState
                }
            }
            .frame(minWidth: 420)

            // Detail panel
            if appState.showDetailPanel, let selected = appState.selectedAsset, appState.folder != nil {
                DetailPanel(asset: selected)
                    .frame(minWidth: 260, idealWidth: 300, maxWidth: 400)
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
                LazyVGrid(columns: columns, spacing: 6) {
                    ForEach(folder.filteredImages) { asset in
                        GalleryThumbnail(
                            asset: asset,
                            isSelected: appState.selectedAsset?.id == asset.id
                        )
                        .id(asset.id)
                        // Single click selects immediately; the double-click recognizer runs
                        // simultaneously so selection never waits for the double-click timeout.
                        .onTapGesture {
                            appState.selectedAsset = asset
                        }
                        .simultaneousGesture(TapGesture(count: 2).onEnded {
                            appState.showPreview(for: asset)
                        })
                        .contextMenu { AssetContextMenu(asset: asset) }
                    }
                }
                .padding(10)
            }
            .background(Color(NSColor.underPageBackgroundColor))
            .onAppear {
                scrollToSelected(proxy: proxy, anchor: .center)
            }
            .onChange(of: appState.currentView) { _, view in
                if view == .gallery { scrollToSelected(proxy: proxy, anchor: .center) }
            }
            .onChange(of: appState.selectedAsset?.id) { _, _ in
                // Keyboard navigation: keep the selection visible with minimal scrolling
                scrollToSelected(proxy: proxy, anchor: nil)
            }
        }
    }

    private func scrollToSelected(proxy: ScrollViewProxy, anchor: UnitPoint?) {
        guard let id = appState.selectedAsset?.id else { return }
        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.2)) {
                proxy.scrollTo(id, anchor: anchor)
            }
        }
    }

    @ViewBuilder
    private func emptyState(for folder: ImageFolder) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 44, weight: .light))
                .foregroundColor(.secondary)

            Text("No “\(folder.filter.rawValue)” photos")
                .font(.headline)

            Text(emptyFilterHint(folder.filter))
                .font(.callout)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button("Show All Photos") {
                folder.filter = .all
            }
            .controlSize(.large)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.underPageBackgroundColor))
    }

    private func emptyFilterHint(_ filter: ImageFilter) -> String {
        switch filter {
        case .all: return ""
        case .unreviewed: return "Every photo in this folder has been reviewed."
        case .kept: return "Press K on a photo, or use the arrow keys in Preview, to keep it."
        case .trashed: return "Nothing is marked for trash."
        case .favorites: return "Press F on a photo to mark it as a favorite."
        }
    }

    private var emptyFolderState: some View {
        VStack(spacing: 14) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 44, weight: .light))
                .foregroundColor(.secondary)
            Text("This folder has no photos")
                .font(.headline)
            Text("Photo Triage reads JPEG and RAW files (CR2, CR3, NEF, ARW, DNG, RAF, ORF, RW2).")
                .font(.callout)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Button("Open Another Folder…") { showingOpenPanel = true }
                .controlSize(.large)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.underPageBackgroundColor))
    }

    private var noFolderState: some View {
        VStack(spacing: 16) {
            Image(systemName: "photo.stack")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(.secondary)

            Text("Photo Triage")
                .font(.largeTitle.bold())

            Text("Open a folder of photos to browse, compare and cull them.\nNothing is deleted until you empty the trash.")
                .font(.callout)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button {
                showingOpenPanel = true
            } label: {
                Label("Open Folder…", systemImage: "folder")
                    .padding(.horizontal, 8)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut("o", modifiers: .command)

            if let last = UserDefaults.standard.string(forKey: "lastFolderPath"),
               FileManager.default.fileExists(atPath: last) {
                Button("Reopen “\(URL(fileURLWithPath: last).lastPathComponent)”") {
                    Task { await appState.openFolder(URL(fileURLWithPath: last)) }
                }
                .buttonStyle(.link)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.underPageBackgroundColor))
    }

    private func handleKeyAction(_ action: KeyAction) -> Bool {
        switch action {
        case .navigateLeft:
            moveSelection(by: -1)
            return true
        case .navigateRight:
            moveSelection(by: 1)
            return true
        case .candidateUp:
            moveSelection(by: -appState.galleryColumns)
            return true
        case .candidateDown:
            moveSelection(by: appState.galleryColumns)
            return true
        case .applyCrop, .toggleZoom:
            if let asset = appState.selectedAsset { appState.showPreview(for: asset) }
            return appState.selectedAsset != nil
        case .keepCurrentImage:
            appState.decideSelected(.kept)
            return true
        case .trashCurrentImage:
            appState.decideSelected(.trashed)
            return true
        case .clearDecision:
            appState.decideSelected(.unreviewed)
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
            appState.showTriage(from: appState.selectedAsset)
            return true
        case .toggleEXIF:
            appState.showDetailPanel.toggle()
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
            appState.requestEmptyTrash()
            return true
        default:
            return false
        }
    }

    /// Move the selection by `delta` positions (±1 for left/right, ±columns for up/down).
    private func moveSelection(by delta: Int) {
        guard let folder = appState.folder else { return }
        let images = folder.filteredImages
        guard !images.isEmpty else { return }
        guard let current = appState.selectedAsset, let index = images.firstIndex(of: current) else {
            appState.selectedAsset = images.first
            return
        }
        let target = index + delta
        if images.indices.contains(target) {
            appState.selectedAsset = images[target]
        } else if abs(delta) > 1 {
            // Up/down past the edge: clamp to first/last
            appState.selectedAsset = delta > 0 ? images.last : images.first
        }
    }
}

/// Right-click menu for a gallery thumbnail
struct AssetContextMenu: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var asset: ImageAsset

    var body: some View {
        Button("Open in Preview") { appState.showPreview(for: asset) }
        Button("Start Triage Here") { appState.showTriage(from: asset) }
        Divider()
        Button("Keep") { appState.setState(.kept, on: asset, label: "Keep") }
            .disabled(asset.isKept)
        Button("Mark for Trash") { appState.setState(.trashed, on: asset, label: "Trash") }
            .disabled(asset.isTrashed)
        Button("Clear Decision") { appState.setState(.unreviewed, on: asset, label: "Clear Decision") }
            .disabled(asset.triageState == .unreviewed)
        Button(asset.isFavorite ? "Remove from Favorites" : "Add to Favorites") {
            appState.toggleFavorite(on: asset)
        }
        Divider()
        Button("Show in Finder") {
            NSWorkspace.shared.activateFileViewerSelecting([asset.displayURL])
        }
    }
}

/// Gallery toolbar with filter/sort controls. Uses `ViewThatFits` to fall back to a compact
/// icon layout on narrow windows instead of letting controls overlap.
struct GalleryToolbar: View {
    @EnvironmentObject var appState: AppState
    @Binding var showingOpenPanel: Bool

    private var trashedCount: Int {
        appState.folder?.images.filter { $0.isTrashed }.count ?? 0
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            toolbarRow(labels: true, segmentedFilter: true)
            toolbarRow(labels: false, segmentedFilter: true)
            toolbarRow(labels: false, segmentedFilter: false)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private func toolbarRow(labels: Bool, segmentedFilter: Bool) -> some View {
        let compact = !labels
        return HStack(spacing: 10) {
            Button(action: { showingOpenPanel = true }) {
                if compact {
                    Image(systemName: "folder")
                } else {
                    Label(appState.folder?.folderURL.lastPathComponent ?? "Open", systemImage: "folder")
                        .lineLimit(1)
                        .frame(maxWidth: 180)
                }
            }
            .help("Open a folder (⌘O)")
            .fixedSize()

            if let folder = appState.folder {
                filterPicker(folder: folder, compact: !segmentedFilter)
                    .fixedSize()

                Spacer(minLength: 8)

                sortMenu(folder: folder, compact: compact)
                    .fixedSize()

                Button(action: { appState.requestEmptyTrash() }) {
                    if compact {
                        Image(systemName: "trash")
                    } else {
                        Label(trashedCount > 0 ? "Empty Trash (\(trashedCount))" : "Empty Trash",
                              systemImage: "trash")
                    }
                }
                .foregroundStyle(trashedCount > 0 ? .red : .secondary)
                .disabled(trashedCount == 0)
                .help(trashedCount > 0
                      ? "Move \(trashedCount) photo(s) marked for trash to the macOS Trash (⌘⌫)"
                      : "No photos are marked for trash")
                .fixedSize()
            } else {
                Spacer(minLength: 8)
            }

            // Detail panel toggle
            Button(action: { appState.showDetailPanel.toggle() }) {
                Image(systemName: "sidebar.right")
                    .symbolVariant(appState.showDetailPanel ? .fill : .none)
            }
            .help(appState.showDetailPanel ? "Hide Details (I)" : "Show Details (I)")
            .disabled(appState.folder == nil)
            .fixedSize()
        }
    }

    @ViewBuilder
    private func filterPicker(folder: ImageFolder, compact: Bool) -> some View {
        let selection = Binding(
            get: { appState.folder?.filter ?? .all },
            set: { appState.folder?.filter = $0 }
        )
        if compact {
            Picker("Show", selection: selection) {
                ForEach(ImageFilter.allCases) { filter in
                    Text(filter.rawValue).tag(filter)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .help("Filter photos")
        } else {
            Picker("Show", selection: selection) {
                ForEach(ImageFilter.allCases) { filter in
                    Text(filter.rawValue).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .help("Filter photos")
        }
    }

    private func sortMenu(folder: ImageFolder, compact: Bool) -> some View {
        Menu {
            Picker("Sort", selection: Binding(
                get: { appState.folder?.sort ?? .dateAscending },
                set: { appState.folder?.sort = $0 }
            )) {
                ForEach(ImageSort.allCases) { sort in
                    Text(sort.menuTitle).tag(sort)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            if compact {
                Image(systemName: "arrow.up.arrow.down")
            } else {
                Label(folder.sort.rawValue, systemImage: "arrow.up.arrow.down")
            }
        }
        .menuStyle(.borderlessButton)
        .help("Sort order")
    }
}

extension ImageSort {
    var menuTitle: String {
        switch self {
        case .dateAscending: return "Date — Oldest First"
        case .dateDescending: return "Date — Newest First"
        case .nameAscending: return "Name — A to Z"
        case .nameDescending: return "Name — Z to A"
        }
    }
}

/// Bottom status bar: review progress, decision counts, background analysis, thumbnail size.
struct GalleryStatusBar: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        if let folder = appState.folder {
            let stats = folder.statistics
            ViewThatFits(in: .horizontal) {
                row(stats: stats, showCounts: true, showSlider: true)
                row(stats: stats, showCounts: true, showSlider: false)
                row(stats: stats, showCounts: false, showSlider: false)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(Color(NSColor.windowBackgroundColor))
        }
    }

    private func row(stats: FolderStatistics, showCounts: Bool, showSlider: Bool) -> some View {
        HStack(spacing: 12) {
            ProgressView(value: stats.progress)
                .frame(width: 80)
            Text(stats.progressSummary)
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize()

            if showCounts {
                StatBadge(label: "kept", count: stats.kept, color: .green).fixedSize()
                StatBadge(label: "trash", count: stats.trashed, color: .red).fixedSize()
                StatBadge(label: "favorites", count: stats.favorites, color: .yellow).fixedSize()
            }

            Spacer(minLength: 8)

            AnalysisIndicator()

            if showSlider {
                HStack(spacing: 6) {
                    Image(systemName: "square.grid.3x3").font(.caption2).foregroundColor(.secondary)
                    Slider(value: Binding(
                        get: { Double(14 - appState.galleryColumns) },
                        set: { appState.galleryColumns = 14 - Int($0.rounded()) }
                    ), in: 2...12)
                    .frame(width: 90)
                    .controlSize(.mini)
                    Image(systemName: "square.grid.2x2").font(.caption).foregroundColor(.secondary)
                }
                .help("Thumbnail size (+ / −)")
                .fixedSize()
            }
        }
    }
}

/// "Analyzing 42%" indicator for background hash computation (drives triage similarity)
struct AnalysisIndicator: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        AnalysisIndicatorContent(engine: appState.similarityEngine)
    }
}

private struct AnalysisIndicatorContent: View {
    @ObservedObject var engine: SimilarityEngine

    var body: some View {
        if engine.isComputing {
            HStack(spacing: 6) {
                ProgressView(value: engine.hashProgress)
                    .progressViewStyle(.circular)
                    .controlSize(.mini)
                Text("Analyzing similarity \(Int(engine.hashProgress * 100))%")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .help("Computing perceptual hashes used to find similar photos in Triage")
            .fixedSize()
        }
    }
}
