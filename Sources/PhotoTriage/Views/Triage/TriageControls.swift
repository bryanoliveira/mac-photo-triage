import SwiftUI

/// Bottom action bar for triage decisions
struct TriageControls: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        HStack(spacing: 20) {
            // Keep Left
            TriageActionButton(
                label: "Keep Left",
                shortcut: "L",
                icon: "arrow.left.circle.fill",
                color: .blue,
                action: { appState.keepLeft() }
            )
            .disabled(appState.triageAnchor == nil || appState.triageCandidate == nil)

            // Keep Right
            TriageActionButton(
                label: "Keep Right",
                shortcut: "R",
                icon: "arrow.right.circle.fill",
                color: .orange,
                action: { appState.keepRight() }
            )
            .disabled(appState.triageAnchor == nil || appState.triageCandidate == nil)

            Divider()
                .frame(height: 40)

            // Keep Both
            TriageActionButton(
                label: "Keep Both",
                shortcut: "B",
                icon: "checkmark.circle.fill",
                color: .green,
                action: { appState.keepBoth() }
            )
            .disabled(appState.triageAnchor == nil || appState.triageCandidate == nil)

            // Keep None (Trash Both)
            TriageActionButton(
                label: "Trash Both",
                shortcut: "N",
                icon: "trash.circle.fill",
                color: .red,
                action: { appState.keepNone() }
            )
            .disabled(appState.triageAnchor == nil || appState.triageCandidate == nil)

            Spacer()

            // Quick stats
            if let folder = appState.folder {
                let stats = folder.statistics
                HStack(spacing: 16) {
                    StatBadge(label: "Kept", count: stats.kept, color: .green)
                    StatBadge(label: "Trash", count: stats.trashed, color: .red)
                    StatBadge(label: "Favorites", count: stats.favorites, color: .yellow)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

/// Single triage action button
struct TriageActionButton: View {
    let label: String
    let shortcut: String
    let icon: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 24))
                    .foregroundColor(color)

                HStack(spacing: 4) {
                    Text(label)
                        .font(.caption.bold())

                    Text("(\(shortcut))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
}

/// Small stat badge
struct StatBadge: View {
    let label: String
    let count: Int
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)

            Text("\(count)")
                .font(.caption.bold())

            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}

/// Completion message when all images triaged
struct TriageCompleteView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundColor(.green)

            Text("Triage Complete!")
                .font(.title)

            if let folder = appState.folder {
                let stats = folder.statistics

                VStack(spacing: 8) {
                    Text("\(stats.total) images reviewed")
                        .font(.headline)

                    HStack(spacing: 20) {
                        StatBadge(label: "Kept", count: stats.kept, color: .green)
                        StatBadge(label: "Trashed", count: stats.trashed, color: .red)
                        StatBadge(label: "Favorites", count: stats.favorites, color: .yellow)
                    }
                }
            }

            HStack(spacing: 16) {
                Button("Back to Gallery") {
                    appState.showGallery()
                }
                .buttonStyle(.bordered)

                if let folder = appState.folder, folder.statistics.trashed > 0 {
                    Button("Empty Trash") {
                        // Would trigger trash service
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                }
            }
        }
        .padding(40)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}
