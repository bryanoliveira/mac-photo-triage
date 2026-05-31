import SwiftUI

/// Side-by-side triage comparison view
struct TriageView: View {
    @EnvironmentObject var appState: AppState

    @State private var dividerPosition: CGFloat = 0.5
    @State private var leftScale: CGFloat = 1.0
    @State private var rightScale: CGFloat = 1.0
    @State private var leftOffset: CGSize = .zero
    @State private var rightOffset: CGSize = .zero
    @State private var leftFitToWindow = true
    @State private var rightFitToWindow = true

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            TriageToolbar()

            // Main comparison area
            GeometryReader { geometry in
                HStack(spacing: 0) {
                    // Left pane (anchor)
                    ComparisonPane(
                        asset: appState.triageAnchor,
                        side: .left,
                        scale: $leftScale,
                        offset: $leftOffset,
                        isFitToWindow: $leftFitToWindow
                    )
                    .frame(width: geometry.size.width * dividerPosition)

                    // Divider
                    ResizableDivider(position: $dividerPosition)

                    // Right pane (candidate)
                    ComparisonPane(
                        asset: appState.triageCandidate,
                        side: .right,
                        scale: $rightScale,
                        offset: $rightOffset,
                        isFitToWindow: $rightFitToWindow
                    )
                    .frame(width: geometry.size.width * (1 - dividerPosition))
                }
            }
            .background(Color.black)

            // Action bar
            TriageControls()
        }
        .focusedKeyboardHandler { action in
            handleKeyAction(action)
        }
    }

    private func handleKeyAction(_ action: KeyAction) -> Bool {
        switch action {
        case .keepLeft:
            appState.keepLeft()
            return true
        case .keepRight:
            appState.keepRight()
            return true
        case .keepBoth:
            appState.keepBoth()
            return true
        case .keepNone:
            appState.keepNone()
            return true
        case .navigateLeft:
            appState.previousTriageAnchor()
            return true
        case .navigateRight:
            appState.nextTriageAnchor()
            return true
        case .candidateUp:
            appState.previousCandidate()
            return true
        case .candidateDown:
            appState.nextCandidate()
            return true
        case .toggleZoom:
            toggleZoom()
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
        case .swapPair:
            appState.swapTriagePair()
            return true
        case .switchToGallery:
            appState.showGallery()
            return true
        case .toggleFavorite:
            if let anchor = appState.triageAnchor {
                appState.toggleFavorite(on: anchor)
            }
            return true
        case .openLeftPreview:
            if let anchor = appState.triageAnchor {
                appState.showPreview(for: anchor)
            }
            return true
        case .openRightPreview:
            if let candidate = appState.triageCandidate {
                appState.showPreview(for: candidate)
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

    private func toggleZoom() {
        leftFitToWindow.toggle()
        rightFitToWindow.toggle()
        if leftFitToWindow {
            leftScale = 1.0
            leftOffset = .zero
            rightScale = 1.0
            rightOffset = .zero
        }
    }
}

/// Triage toolbar with navigation and status
struct TriageToolbar: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        HStack {
            // Back button
            Button(action: { appState.showGallery() }) {
                Label("Gallery", systemImage: "square.grid.2x2")
            }

            Divider()
                .frame(height: 20)

            // Progress indicator
            if let folder = appState.folder {
                let stats = folder.statistics
                Text("\(stats.reviewed)/\(stats.total) reviewed")
                    .font(.caption)
                    .foregroundColor(.secondary)

                ProgressView(value: stats.progress)
                    .frame(width: 100)
            }

            Spacer()

            // Navigation
            HStack(spacing: 4) {
                Button(action: { appState.previousTriageAnchor() }) {
                    Image(systemName: "chevron.left")
                }
                .help("Previous (Left Arrow)")

                Text("Anchor")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Button(action: { appState.nextTriageAnchor() }) {
                    Image(systemName: "chevron.right")
                }
                .help("Next (Right Arrow)")
            }

            Divider()
                .frame(height: 20)

            HStack(spacing: 4) {
                Button(action: { appState.previousCandidate() }) {
                    Image(systemName: "chevron.up")
                }
                .help("Previous Candidate (Up Arrow)")

                Text("Candidate")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Button(action: { appState.nextCandidate() }) {
                    Image(systemName: "chevron.down")
                }
                .help("Next Candidate (Down Arrow)")
            }

            Divider()
                .frame(height: 20)

            // Swap anchor ↔ candidate
            Button(action: { appState.swapTriagePair() }) {
                Image(systemName: "arrow.left.arrow.right")
            }
            .help("Swap anchor and candidate (S)")
            .disabled(appState.triageAnchor == nil || appState.triageCandidate == nil)

            Divider()
                .frame(height: 20)

            // Candidate filter
            Picker("", selection: Binding(
                get: { appState.candidateFilter },
                set: { appState.candidateFilter = $0 }
            )) {
                ForEach(CandidateFilter.allCases) { filter in
                    Text(filter.rawValue).tag(filter)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 100)
            .help("Candidate filter: All shows every image; Strict shows near-duplicates only")

            Divider()
                .frame(height: 20)

            // EXIF toggle
            Button(action: { appState.showEXIFOverlay.toggle() }) {
                Image(systemName: appState.showEXIFOverlay ? "info.circle.fill" : "info.circle")
            }
            .help("Toggle EXIF (I)")

            // Guiding grid toggle
            Button(action: { appState.showGuidingGrid.toggle() }) {
                Image(systemName: appState.showGuidingGrid ? "grid" : "grid")
                    .foregroundStyle(appState.showGuidingGrid ? .blue : .primary)
            }
            .help("Toggle guiding grid — rule of thirds + center crosshair (H)")

            // Clipping warnings toggle
            Button(action: { appState.showClippingWarnings.toggle() }) {
                Image(systemName: appState.showClippingWarnings
                    ? "exclamationmark.triangle.fill"
                    : "exclamationmark.triangle")
                .foregroundStyle(appState.showClippingWarnings ? .yellow : .primary)
            }
            .help("Toggle Clipping Warnings — red: blown highlights, blue: crushed shadows (W)")

            // Undo/Redo
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
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

/// Resizable divider between panes
struct ResizableDivider: View {
    @Binding var position: CGFloat

    @State private var isDragging = false

    var body: some View {
        Rectangle()
            .fill(Color.gray.opacity(0.3))
            .frame(width: isDragging ? 4 : 2)
            .contentShape(Rectangle().inset(by: -4))
            .gesture(
                DragGesture()
                    .onChanged { value in
                        isDragging = true
                        let newPosition = position + value.translation.width / 1000
                        position = max(0.2, min(0.8, newPosition))
                    }
                    .onEnded { _ in
                        isDragging = false
                    }
            )
            .onHover { hovering in
                if hovering {
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.pop()
                }
            }
    }
}
