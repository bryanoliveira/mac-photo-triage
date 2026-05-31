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

    @Binding var scale: CGFloat
    @Binding var offset: CGSize
    @Binding var isFitToWindow: Bool

    @EnvironmentObject var appState: AppState

    var body: some View {
        ZStack {
            if let asset = asset {
                // Main image
                ControlledZoomableImageView(
                    url: asset.displayURL,
                    scale: $scale,
                    offset: $offset,
                    isFitToWindow: $isFitToWindow,
                    showClippingWarnings: appState.showClippingWarnings
                )
                .overlay {
                    if appState.showGuidingGrid { GuidingGridOverlay() }
                }

                // Overlays
                VStack {
                    // Top bar with side indicator and controls
                    HStack {
                        // Side label
                        Text(side.label)
                            .font(.caption.bold())
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(side.color.opacity(0.8))
                            .cornerRadius(4)

                        Spacer()

                        // Favorite button
                        FavoriteButton(asset: asset, size: .medium) {
                            appState.toggleFavorite(on: asset)
                        }
                        .background(.ultraThinMaterial, in: Circle())

                        // Preview button
                        Button(action: {
                            appState.showPreview(for: asset)
                        }) {
                            Image(systemName: "eye")
                                .font(.system(size: 14))
                                .foregroundColor(.white)
                        }
                        .buttonStyle(.plain)
                        .padding(8)
                        .background(.ultraThinMaterial, in: Circle())
                    }
                    .padding(8)

                    Spacer()

                    // Bottom info bar
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(asset.displayName)
                                .font(.caption.bold())
                                .foregroundColor(.white)
                                .lineLimit(1)

                            if asset.isPair {
                                Text(asset.typeIndicator)
                                    .font(.caption2)
                                    .foregroundColor(.white.opacity(0.7))
                            }
                        }

                        Spacer()

                        // State badge
                        if let badge = asset.stateBadge {
                            Text(badge)
                                .font(.caption.bold())
                                .foregroundColor(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(asset.isTrashed ? Color.red : Color.green)
                                .cornerRadius(4)
                        }
                    }
                    .padding(8)
                    .background(
                        LinearGradient(
                            gradient: Gradient(colors: [.clear, .black.opacity(0.6)]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                }

                // EXIF overlay
                if appState.showEXIFOverlay {
                    VStack {
                        Spacer()
                        HStack {
                            EXIFOverlay(metadata: asset.exifMetadata, position: .bottomLeading)
                            Spacer()
                        }
                    }
                    .padding(.bottom, 40)
                }
            } else {
                // Empty state
                VStack(spacing: 8) {
                    Image(systemName: side == .left ? "photo" : "photo.on.rectangle")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)

                    Text(side == .left ? "No anchor image" : "No candidate")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .background(Color.black)
        .onChange(of: asset?.id) { _, _ in
            // Load EXIF when asset changes
            if let asset = asset, asset.exifMetadata == nil {
                asset.exifMetadata = EXIFReader.read(from: asset.displayURL)
            }
        }
    }
}

/// Similarity info overlay between panes
struct SimilarityOverlay: View {
    let candidate: SimilarityCandidate?

    var body: some View {
        if let candidate = candidate {
            VStack(spacing: 4) {
                Text("Similarity")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                Text("\(Int((1 - candidate.score) * 100))%")
                    .font(.headline)
                    .foregroundColor(.primary)

                HStack(spacing: 8) {
                    VStack {
                        Text("Hash")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text("\(100 - Int(candidate.hashDistancePercent))%")
                            .font(.caption)
                    }

                    Divider()
                        .frame(height: 20)

                    VStack {
                        Text("Time")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(formatTimeDistance(candidate.timeDistance))
                            .font(.caption)
                    }
                }
            }
            .padding(8)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func formatTimeDistance(_ seconds: TimeInterval) -> String {
        if seconds < 60 {
            return "\(Int(seconds))s"
        } else if seconds < 3600 {
            return "\(Int(seconds / 60))m"
        } else if seconds < 86400 {
            return "\(Int(seconds / 3600))h"
        } else {
            return "\(Int(seconds / 86400))d"
        }
    }
}
