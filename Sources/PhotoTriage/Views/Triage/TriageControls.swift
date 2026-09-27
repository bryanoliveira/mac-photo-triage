import SwiftUI

/// Bottom action bar for triage decisions
struct TriageControls: View {
    @EnvironmentObject var appState: AppState

    private var hasPair: Bool {
        appState.triageAnchor != nil && appState.triageCandidate != nil
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            row(compact: false)
            row(compact: true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private func row(compact: Bool) -> some View {
        HStack(spacing: compact ? 8 : 12) {
            TriageActionButton(label: "Keep Left", shortcut: "L", icon: "arrow.left.circle.fill",
                               color: .blue, compact: compact, help: "Keep the anchor, trash the candidate") {
                appState.keepLeft()
            }
            TriageActionButton(label: "Keep Right", shortcut: "R", icon: "arrow.right.circle.fill",
                               color: .orange, compact: compact, help: "Keep the candidate, trash the anchor") {
                appState.keepRight()
            }

            Divider().frame(height: 32)

            TriageActionButton(label: "Keep Both", shortcut: "B", icon: "checkmark.circle.fill",
                               color: .green, compact: compact, help: "Keep both photos") {
                appState.keepBoth()
            }
            TriageActionButton(label: "Trash Both", shortcut: "N", icon: "trash.circle.fill",
                               color: .red, compact: compact, help: "Mark both photos for trash") {
                appState.keepNone()
            }

            Spacer(minLength: 8)

            // Quick stats
            if let folder = appState.folder {
                let stats = folder.statistics
                HStack(spacing: 12) {
                    StatBadge(label: compact ? "" : "kept", count: stats.kept, color: .green)
                    StatBadge(label: compact ? "" : "trash", count: stats.trashed, color: .red)
                    StatBadge(label: compact ? "" : "favorites", count: stats.favorites, color: .yellow)
                }
                .fixedSize()
            }
        }
        .disabled(!hasPair)
    }
}

/// Single triage action button
struct TriageActionButton: View {
    let label: String
    let shortcut: String
    let icon: String
    let color: Color
    var compact: Bool = false
    var help: String = ""
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundStyle(isEnabled ? color : .secondary)

                if !compact {
                    Text(label)
                        .font(.callout.weight(.semibold))
                }

                Text(shortcut)
                    .font(.caption.monospaced().weight(.semibold))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Color(NSColor.controlBackgroundColor).opacity(isHovering ? 1 : 0.7),
                        in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(color.opacity(isHovering && isEnabled ? 0.6 : 0.15)))
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help("\(help) (\(shortcut))")
        .fixedSize()
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
                .frame(width: 7, height: 7)

            Text("\(count)")
                .font(.caption.bold().monospacedDigit())

            if !label.isEmpty {
                Text(label)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

/// Shown when forward navigation runs past the last photo in triage
struct TriageCompleteView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 52))
                .foregroundStyle(.green)

            Text("You've reached the last photo")
                .font(.title2.bold())

            if let folder = appState.folder {
                let stats = folder.statistics

                VStack(spacing: 8) {
                    Text(stats.progressSummary)
                        .foregroundColor(.secondary)

                    HStack(spacing: 18) {
                        StatBadge(label: "kept", count: stats.kept, color: .green)
                        StatBadge(label: "marked for trash", count: stats.trashed, color: .red)
                        StatBadge(label: "favorites", count: stats.favorites, color: .yellow)
                    }
                }
            }

            HStack(spacing: 12) {
                Button("Start Over") { appState.restartTriage() }
                Button("Back to Gallery") { appState.showGallery() }
                    .keyboardShortcut(.defaultAction)

                if appState.trashedCount > 0 {
                    Button("Empty Trash…") { appState.requestEmptyTrash() }
                        .tint(.red)
                }
            }
            .controlSize(.large)

            Text("Press ← to go back to the last photo")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(36)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .shadow(radius: 20)
    }
}
