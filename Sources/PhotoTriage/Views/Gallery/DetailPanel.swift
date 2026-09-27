import SwiftUI

/// Sidebar detail panel for selected image
struct DetailPanel: View {
    @ObservedObject var asset: ImageAsset
    @EnvironmentObject var appState: AppState

    @State private var hasOriginalBackup: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                thumbnailSection
                decisionSection
                Divider()
                fileInfoSection
                Divider()
                exifSection
                Divider()
                actionsSection
            }
            .padding()
        }
        .background(Color(NSColor.windowBackgroundColor))
        .task(id: asset.displayURL) { await checkBackup() }
        .onChange(of: appState.cropVersion) { _, _ in Task { await checkBackup() } }
    }

    private func checkBackup() async {
        hasOriginalBackup = await CropService().hasBackup(for: asset.displayURL)
    }

    // MARK: - Sections

    private var thumbnailSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            AsyncThumbnail(url: asset.displayURL, size: 240, reloadToken: asset.thumbnailVersion)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .frame(maxWidth: .infinity)
                .onTapGesture(count: 2) { appState.showPreview(for: asset) }
                .help("Double-click to open in Preview")

            HStack(alignment: .firstTextBaseline) {
                Text(asset.displayName)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)

                Spacer()

                FavoriteButton(asset: asset, size: .small) {
                    appState.toggleFavorite(on: asset)
                }
            }
        }
    }

    /// Keep / Trash / Clear as a single segmented control that also shows the current state
    private var decisionSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                DecisionBadge(asset: asset, style: .pill, showUnreviewed: true)
                Spacer()
                Text(asset.typeIndicator)
                    .font(.caption.weight(.medium))
                    .foregroundColor(.secondary)
            }

            Picker("Decision", selection: Binding(
                get: { asset.triageState.isDecided ? asset.triageState : .unreviewed },
                set: { newValue in
                    let label = newValue == .kept ? "Keep" : newValue == .trashed ? "Trash" : "Clear Decision"
                    appState.setState(newValue, on: asset, label: label)
                }
            )) {
                Label("Keep", systemImage: "checkmark").tag(TriageState.kept)
                Label("Undecided", systemImage: "minus").tag(TriageState.unreviewed)
                Label("Trash", systemImage: "trash").tag(TriageState.trashed)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .help("Keep (K) · Clear (U) · Trash (⌫)")
        }
    }

    private var fileInfoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("File Info")
                .font(.subheadline.bold())

            InfoRow(label: "Type", value: asset.typeIndicator)

            if let metadata = asset.exifMetadata {
                if let width = metadata.imageWidth, let height = metadata.imageHeight {
                    InfoRow(label: "Dimensions", value: "\(width) × \(height)")
                }
            }

            // File size
            if let attrs = try? FileManager.default.attributesOfItem(atPath: asset.displayURL.path),
               let size = attrs[.size] as? Int64 {
                InfoRow(label: "Size", value: formatFileSize(size))
            }

            if hasOriginalBackup {
                InfoRow(label: "Edited", value: "Original backed up")
            }
        }
    }

    private var exifSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Camera")
                .font(.subheadline.bold())

            if let metadata = asset.exifMetadata {
                if metadata.hasAnyData {
                    if let camera = metadata.cameraString {
                        InfoRow(label: "Camera", value: camera)
                    }
                    if let lens = metadata.lensString {
                        InfoRow(label: "Lens", value: lens)
                    }
                    if !metadata.summaryString.isEmpty {
                        InfoRow(label: "Exposure", value: metadata.summaryString)
                    }
                    if let ev = metadata.exposureCompensationString {
                        InfoRow(label: "Comp.", value: ev)
                    }
                    if let date = metadata.captureDate {
                        InfoRow(label: "Taken", value: formatDate(date))
                    }
                } else {
                    Text("No EXIF metadata")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else {
                Text("Loading…")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .task {
                        let url = asset.displayURL
                        asset.exifMetadata = await Task.detached { EXIFReader.read(from: url) }.value
                    }
            }
        }
    }

    private var actionsSection: some View {
        VStack(spacing: 8) {
            Button(action: {
                appState.showPreview(for: asset)
            }) {
                Label("Open in Preview", systemImage: "eye")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)

            Button(action: {
                appState.showTriage(from: asset)
            }) {
                Label("Start Triage Here", systemImage: "square.split.2x1")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)

            if hasOriginalBackup {
                Button(action: { Task { await appState.restoreOriginal(asset) } }) {
                    Label("Restore Original", systemImage: "arrow.counterclockwise")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .help("Replace the edited file with the unedited original (undoable)")
            }

            Button(action: {
                NSWorkspace.shared.activateFileViewerSelecting([asset.displayURL])
            }) {
                Label("Show in Finder", systemImage: "folder")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderless)
            .padding(.top, 4)
        }
    }

    // MARK: - Helpers

    private func formatFileSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium  // includes seconds
        return formatter.string(from: date)
    }
}

/// Simple info row for detail panel
struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 72, alignment: .leading)

            Text(value)
                .font(.caption)
                .lineLimit(2)
                .textSelection(.enabled)

            Spacer(minLength: 0)
        }
    }
}
