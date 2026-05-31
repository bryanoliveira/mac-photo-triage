import SwiftUI

/// Sidebar detail panel for selected image
struct DetailPanel: View {
    @ObservedObject var asset: ImageAsset
    @EnvironmentObject var appState: AppState

    @State private var hasOriginalBackup: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Preview thumbnail
                thumbnailSection

                Divider()

                // File info
                fileInfoSection

                Divider()

                // EXIF metadata
                exifSection

                Divider()

                // Actions
                actionsSection

                Spacer()
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
        VStack {
            AsyncThumbnail(url: asset.displayURL, size: 200, reloadToken: asset.thumbnailVersion)
                .cornerRadius(8)

            HStack {
                Text(asset.displayName)
                    .font(.headline)
                    .lineLimit(1)

                Spacer()

                FavoriteButton(asset: asset) {
                    appState.toggleFavorite(on: asset)
                }
            }

            // State indicator
            HStack {
                Text(asset.sentinelState.stateDescription)
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                Text(asset.typeIndicator)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var fileInfoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("File Info")
                .font(.subheadline.bold())

            InfoRow(label: "Name", value: asset.displayName)
            InfoRow(label: "Type", value: asset.typeIndicator)

            if let metadata = asset.exifMetadata {
                if let width = metadata.imageWidth, let height = metadata.imageHeight {
                    InfoRow(label: "Dimensions", value: "\(width) x \(height)")
                }
            }

            // File size
            if let attrs = try? FileManager.default.attributesOfItem(atPath: asset.displayURL.path),
               let size = attrs[.size] as? Int64 {
                InfoRow(label: "Size", value: formatFileSize(size))
            }
        }
    }

    private var exifSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("EXIF Data")
                .font(.subheadline.bold())

            if let metadata = asset.exifMetadata {
                if let camera = metadata.cameraString {
                    InfoRow(label: "Camera", value: camera)
                }

                if let lens = metadata.lensString {
                    InfoRow(label: "Lens", value: lens)
                }

                if let focal = metadata.focalLengthString {
                    InfoRow(label: "Focal Length", value: focal)
                }

                if let aperture = metadata.apertureString {
                    InfoRow(label: "Aperture", value: aperture)
                }

                if let shutter = metadata.shutterSpeed {
                    InfoRow(label: "Shutter", value: shutter)
                }

                if let iso = metadata.isoString {
                    InfoRow(label: "ISO", value: iso)
                }

                if let date = metadata.captureDate {
                    InfoRow(label: "Date", value: formatDate(date))
                }
            } else {
                Text("Loading...")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .task {
                        asset.exifMetadata = EXIFReader.read(from: asset.displayURL)
                    }
            }
        }
    }

    private var actionsSection: some View {
        VStack(spacing: 12) {
            Text("Actions")
                .font(.subheadline.bold())
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: {
                appState.showPreview(for: asset)
            }) {
                Label("Open in Preview", systemImage: "eye")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Button(action: {
                appState.showTriage(from: asset)
            }) {
                Label("Start Triage Here", systemImage: "square.split.2x1")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Divider()

            HStack(spacing: 12) {
                Button(action: {
                    try? asset.markKept()
                }) {
                    Label("Keep", systemImage: "checkmark.circle")
                }
                .buttonStyle(.bordered)
                .tint(.green)
                .disabled(asset.isKept)

                Button(action: {
                    try? asset.markTrashed()
                }) {
                    Label("Trash", systemImage: "trash")
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .disabled(asset.isTrashed)
            }

            if asset.isReviewed {
                Button(action: {
                    try? asset.clearTriageState()
                }) {
                    Label("Clear State", systemImage: "arrow.uturn.backward")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }

            if hasOriginalBackup {
                Divider()

                Button(action: restoreOriginal) {
                    Label("Restore Original", systemImage: "arrow.counterclockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .help("Replace the current file with the unedited original")
            }
        }
    }

    private func restoreOriginal() {
        Task {
            let service = CropService()
            do {
                try await service.restoreOriginal(for: asset.displayURL)
                appState.cropVersion += 1
                asset.thumbnailVersion += 1
                hasOriginalBackup = false
            } catch {
                appState.errorMessage = error.localizedDescription
            }
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
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 80, alignment: .leading)

            Text(value)
                .font(.caption)
                .lineLimit(1)

            Spacer()
        }
    }
}
