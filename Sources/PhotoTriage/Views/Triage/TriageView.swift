import SwiftUI

/// Side-by-side triage comparison view
struct TriageView: View {
    @EnvironmentObject var appState: AppState

    @State private var dividerPosition: CGFloat = 0.5
    @State private var leftZoom = ZoomState.fit
    @State private var rightZoom = ZoomState.fit
    @State private var zoomRequest = ZoomRequest()

    var body: some View {
        VStack(spacing: 0) {
            TriageToolbar()
            Divider()

            // Main comparison area
            GeometryReader { geometry in
                HStack(spacing: 0) {
                    // Left pane (anchor)
                    ComparisonPane(
                        asset: appState.triageAnchor,
                        side: .left,
                        zoom: $leftZoom,
                        request: zoomRequest,
                        candidateInfo: nil
                    )
                    .frame(width: max(0, geometry.size.width * dividerPosition - 1))

                    ResizableDivider(position: $dividerPosition, totalWidth: geometry.size.width)

                    // Right pane (candidate) — shares the left pane's zoom when synced
                    ComparisonPane(
                        asset: appState.triageCandidate,
                        side: .right,
                        zoom: appState.syncTriageZoom ? $leftZoom : $rightZoom,
                        request: zoomRequest,
                        candidateInfo: appState.currentCandidateInfo
                    )
                    .frame(width: max(0, geometry.size.width * (1 - dividerPosition) - 1))
                }
            }
            .background(Color.black)
            .overlay {
                if appState.triageFinished {
                    ZStack {
                        Color.black.opacity(0.55)
                        TriageCompleteView()
                    }
                    .transition(.opacity)
                }
            }

            Divider()
            TriageControls()
        }
        .animation(.easeInOut(duration: 0.2), value: appState.triageFinished)
        .focusedKeyboardHandler { action in
            handleKeyAction(action)
        }
        .onChange(of: appState.syncTriageZoom) { _, synced in
            if synced { rightZoom = leftZoom }
        }
    }

    private func handleKeyAction(_ action: KeyAction) -> Bool {
        switch action {
        case .keepLeft:
            appState.keepLeft()
        case .keepRight:
            appState.keepRight()
        case .keepBoth:
            appState.keepBoth()
        case .keepNone:
            appState.keepNone()
        case .navigateLeft:
            appState.previousTriageAnchor()
        case .navigateRight:
            appState.nextTriageAnchor()
        case .candidateUp:
            appState.previousCandidate()
        case .candidateDown:
            appState.nextCandidate()
        case .toggleZoom:
            zoomRequest.send(.fit)
        case .zoomActualSize:
            zoomRequest.send(leftZoom.isFit ? .actualSize : .fit)
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
        case .swapPair:
            appState.swapTriagePair()
        case .switchToGallery, .cancelCrop:
            if appState.triageFinished {
                appState.triageFinished = false
            } else {
                appState.showGallery()
            }
        case .toggleFavorite:
            if let anchor = appState.triageAnchor {
                appState.toggleFavorite(on: anchor)
            }
        case .openLeftPreview:
            if let anchor = appState.triageAnchor {
                appState.showPreview(for: anchor)
            }
        case .openRightPreview:
            if let candidate = appState.triageCandidate {
                appState.showPreview(for: candidate)
            }
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
}

/// Triage toolbar with navigation and status. Collapses to icons on narrow windows.
struct TriageToolbar: View {
    @EnvironmentObject var appState: AppState

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

            Divider().frame(height: 18)

            // Anchor navigation + position
            HStack(spacing: 4) {
                Button(action: { appState.previousTriageAnchor() }) {
                    Image(systemName: "chevron.left")
                }
                .help("Previous photo (←)")
                Text(anchorPositionText)
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.secondary)
                    .frame(minWidth: compact ? 44 : 64)
                Button(action: { appState.nextTriageAnchor() }) {
                    Image(systemName: "chevron.right")
                }
                .help("Next photo (→) — keeps the current photo if undecided")
            }
            .fixedSize()

            if !compact, let folder = appState.folder {
                ProgressView(value: folder.statistics.progress)
                    .frame(width: 70)
                    .help(folder.statistics.progressSummary)
            }

            Spacer(minLength: 8)

            // Candidate navigation
            HStack(spacing: 4) {
                Button(action: { appState.previousCandidate() }) {
                    Image(systemName: "chevron.up")
                }
                .help("Previous candidate (↑)")
                .disabled(appState.candidateIndex == 0)
                Text(candidatePositionText(compact: compact))
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.secondary)
                    .frame(minWidth: compact ? 36 : 90)
                Button(action: { appState.nextCandidate() }) {
                    Image(systemName: "chevron.down")
                }
                .help("Next candidate (↓)")
                .disabled(appState.candidateIndex >= appState.candidateCount - 1)
            }
            .fixedSize()

            ToolbarButton(title: "Swap", systemImage: "arrow.left.arrow.right", compact: true,
                          help: "Swap anchor and candidate (S)") { appState.swapTriagePair() }
                .disabled(appState.triageAnchor == nil || appState.triageCandidate == nil)

            Picker("Candidates", selection: $appState.candidateFilter) {
                ForEach(CandidateFilter.allCases) { filter in
                    Text(filter.rawValue).tag(filter)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .fixedSize()
            .help("Which photos can appear as candidates: All shows every photo; Strict shows near-duplicates only")

            AnalysisIndicator()

            Divider().frame(height: 18)

            ToggleIconButton(isOn: appState.syncTriageZoom, systemImage: "link",
                             help: "Zoom and pan both photos together") { appState.syncTriageZoom.toggle() }
            ToggleIconButton(isOn: appState.showEXIFOverlay, systemImage: "info.circle",
                             help: "Photo info (I)") { appState.showEXIFOverlay.toggle() }
            ToggleIconButton(isOn: appState.showGuidingGrid, systemImage: "grid",
                             help: "Guiding grid (H)") { appState.showGuidingGrid.toggle() }
            ToggleIconButton(isOn: appState.showClippingWarnings, systemImage: "exclamationmark.triangle",
                             help: "Clipping warnings — red: blown highlights, blue: crushed shadows (W)") {
                appState.showClippingWarnings.toggle()
            }

            Divider().frame(height: 18)

            ToolbarButton(title: "Undo", systemImage: "arrow.uturn.backward", compact: true,
                          help: appState.undoLabel.map { "Undo \($0) (⌘Z)" } ?? "Undo (⌘Z)") { appState.undo() }
                .disabled(!appState.canUndo)
            ToolbarButton(title: "Redo", systemImage: "arrow.uturn.forward", compact: true,
                          help: appState.redoLabel.map { "Redo \($0) (⌘⇧Z)" } ?? "Redo (⌘⇧Z)") { appState.redo() }
                .disabled(!appState.canRedo)
        }
    }

    private var anchorPositionText: String {
        guard let pos = appState.triagePosition else { return "—" }
        return "\(pos.index + 1) / \(pos.count)"
    }

    private func candidatePositionText(compact: Bool) -> String {
        let count = appState.candidateCount
        guard count > 0, appState.triageCandidate != nil else { return compact ? "—" : "No candidates" }
        let pos = "\(appState.candidateIndex + 1) / \(count)"
        return compact ? pos : "Candidate \(pos)"
    }
}

/// Resizable divider between panes
struct ResizableDivider: View {
    @Binding var position: CGFloat
    let totalWidth: CGFloat

    @State private var isDragging = false
    @State private var startPosition: CGFloat?

    var body: some View {
        Rectangle()
            .fill(isDragging ? Color.accentColor : Color.gray.opacity(0.35))
            .frame(width: 2)
            .contentShape(Rectangle().inset(by: -5))
            .gesture(
                DragGesture(coordinateSpace: .global)
                    .onChanged { value in
                        isDragging = true
                        if startPosition == nil { startPosition = position }
                        guard totalWidth > 0, let start = startPosition else { return }
                        position = max(0.2, min(0.8, start + value.translation.width / totalWidth))
                    }
                    .onEnded { _ in
                        isDragging = false
                        startPosition = nil
                    }
            )
            .onTapGesture(count: 2) { position = 0.5 }
            .onHover { hovering in
                if hovering {
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.pop()
                }
            }
            .help("Drag to resize · double-click to reset")
    }
}
