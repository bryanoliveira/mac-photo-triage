import SwiftUI

/// Side indicator for comparison pane
enum PaneSide {
    case left
    case right

    var label: String {
        switch self {
        case .left: return "Anchor"
        case .right: return "Candidate"
        }
    }

    var color: Color {
        switch self {
        case .left: return .blue
        case .right: return .orange
        }
    }
}

/// Single comparison pane in triage view
struct ComparisonPane: View {
    let asset: ImageAsset?
    let side: PaneSide
    @Binding var zoom: ZoomState
    let request: ZoomRequest
    let candidateInfo: SimilarityCandidate?

    @EnvironmentObject var appState: AppState

    var body: some View {
        ZStack {
            if let asset = asset {
                ControlledZoomableImageView(
                    url: asset.displayURL,
                    zoom: $zoom,
                    request: request,
                    showClippingWarnings: appState.showClippingWarnings
                )
                .overlay {
                    if appState.showGuidingGrid { GuidingGridOverlay() }
                }
                .overlay(alignment: .top) { topBar(for: asset) }
                .overlay(alignment: .bottom) { bottomBar(for: asset) }
                .overlay(alignment: .bottomLeading) {
                    if appState.showEXIFOverlay {
                        EXIFOverlay(metadata: asset.exifMetadata, position: .bottomLeading)
                            .padding(.bottom, 36)
                    }
                }
            } else {
                emptyState
            }
        }
        .background(Color.black)
        .task(id: asset?.id) {
            // Load EXIF off the main thread when the pane's image changes
            if let asset = asset, asset.exifMetadata == nil {
                let url = asset.displayURL
                asset.exifMetadata = await Task.detached { EXIFReader.read(from: url) }.value
            }
        }
    }

    private func topBar(for asset: ImageAsset) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(side.label)
                .font(.caption.bold())
                .foregroundColor(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(side.color.opacity(0.85), in: RoundedRectangle(cornerRadius: 5))

            DecisionBadge(asset: asset, style: .pill, showUnreviewed: true)
                .animation(.easeInOut(duration: 0.15), value: asset.triageState)

            if let info = candidateInfo {
                Text("\(Int(((1 - info.score) * 100).rounded()))% match")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 5))
                    .help(matchHelp(info))
            }

            Spacer(minLength: 4)

            FavoriteButton(asset: asset, size: .medium) {
                appState.toggleFavorite(on: asset)
            }
            .background(.ultraThinMaterial, in: Circle())

            Button(action: {
                appState.showPreview(for: asset)
            }) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 13, weight: .medium))
                    .padding(9)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .background(.ultraThinMaterial, in: Circle())
            .help(side == .left ? "Open in Preview (P)" : "Open in Preview (⇧P)")
        }
        .padding(8)
    }

    private func bottomBar(for asset: ImageAsset) -> some View {
        HStack(spacing: 8) {
            Text(asset.displayName)
                .font(.caption.bold())
                .foregroundColor(.white)
                .lineLimit(1)
                .truncationMode(.middle)

            if asset.isPair {
                PairBadge()
            }

            Spacer(minLength: 4)

            if let date = asset.captureTime {
                Text(date, format: .dateTime.hour().minute().second())
                    .font(.caption2.monospacedDigit())
                    .foregroundColor(.white.opacity(0.75))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            LinearGradient(colors: [.clear, .black.opacity(0.65)], startPoint: .top, endPoint: .bottom)
        )
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: side == .left ? "photo" : "photo.on.rectangle")
                .font(.system(size: 36, weight: .light))
                .foregroundColor(.secondary)

            if side == .left {
                Text("No photo selected")
                    .font(.callout)
                    .foregroundColor(.secondary)
            } else if appState.similarityEngine.isComputing {
                Text("Finding similar photos…")
                    .font(.callout)
                    .foregroundColor(.secondary)
            } else if appState.triageAnchor != nil {
                Text("No candidates match the “\(appState.candidateFilter.rawValue)” filter")
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                if appState.candidateFilter != .all {
                    Button("Show All Candidates") { appState.candidateFilter = .all }
                }
            }
        }
        .padding()
    }

    private func matchHelp(_ info: SimilarityCandidate) -> String {
        var parts = ["Visual difference \(Int(info.hashDistancePercent.rounded()))%"]
        if info.timeDistance.isFinite {
            parts.append("taken \(Self.formatInterval(info.timeDistance)) apart")
        }
        return parts.joined(separator: " · ")
    }

    static func formatInterval(_ seconds: TimeInterval) -> String {
        if seconds < 60 { return "\(Int(seconds))s" }
        if seconds < 3600 { return "\(Int(seconds / 60))m" }
        if seconds < 86400 { return "\(Int(seconds / 3600))h" }
        return "\(Int(seconds / 86400))d"
    }
}
