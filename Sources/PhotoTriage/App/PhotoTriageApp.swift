import SwiftUI

/// Main application entry point
@main
struct PhotoTriageApp: App {
    @StateObject private var appState = AppState()
    @State private var showSettings = false

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .frame(minWidth: 800, minHeight: 600)
                .onAppear {
                    // Restore window position if saved
                    restoreWindowState()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            // File menu
            CommandGroup(replacing: .newItem) {
                Button("Open Folder...") {
                    openFolderDialog()
                }
                .keyboardShortcut("o", modifiers: .command)
            }

            CommandGroup(after: .newItem) {
                Divider()

                Button("Empty Trash") {
                    emptyTrash()
                }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(appState.folder?.statistics.trashed == 0)
            }

            // Edit menu
            CommandGroup(replacing: .undoRedo) {
                Button("Undo") {
                    appState.undo()
                }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(!appState.canUndo)

                Button("Redo") {
                    appState.redo()
                }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(!appState.canRedo)
            }

            // View menu
            CommandGroup(replacing: .toolbar) {
                Button("Gallery") {
                    appState.showGallery()
                }
                .keyboardShortcut("g", modifiers: [])
                .disabled(appState.folder == nil)

                Button("Preview") {
                    if let asset = appState.selectedAsset {
                        appState.showPreview(for: asset)
                    }
                }
                .keyboardShortcut("p", modifiers: [])
                .disabled(appState.selectedAsset == nil)

                Button("Triage") {
                    appState.showTriage()
                }
                .keyboardShortcut("t", modifiers: [])
                .disabled(appState.folder == nil)

                Divider()

                Button("Toggle EXIF Overlay") {
                    appState.showEXIFOverlay.toggle()
                }
                .keyboardShortcut("i", modifiers: [])

                Button("Toggle Detail Panel") {
                    appState.showDetailPanel.toggle()
                }
            }
        }

        // Settings window
        Settings {
            ShortcutSettings()
                .environmentObject(appState)
        }
    }

    private func openFolderDialog() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select a folder containing photos"

        if panel.runModal() == .OK, let url = panel.url {
            Task {
                await appState.openFolder(url)
            }
        }
    }

    private func emptyTrash() {
        guard let folder = appState.folder else { return }

        let trashService = TrashService()
        Task {
            let result = await trashService.executeTrash(for: folder)
            if !result.isSuccess {
                appState.errorMessage = "Failed to trash some files: \(result.errors.joined(separator: ", "))"
            }
        }
    }

    private func restoreWindowState() {
        // Window state restoration handled by SwiftUI
    }
}

/// Main content view that switches between modes
struct ContentView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        ZStack {
            switch appState.currentView {
            case .gallery:
                GalleryView()
            case .preview:
                PreviewView()
            case .triage:
                TriageView()
            }

            // Resume prompt overlay
            if appState.showResumePrompt, let progress = appState.savedProgress {
                ResumePromptOverlay(progress: progress)
            }

            // Error alert
            if let error = appState.errorMessage {
                VStack {
                    Spacer()
                    ErrorBanner(message: error) {
                        appState.errorMessage = nil
                    }
                }
            }

            // Loading overlay
            if appState.isLoading {
                LoadingOverlay()
            }

            // Hash computation progress
            if appState.similarityEngine.isComputing {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        HashProgressIndicator(progress: appState.similarityEngine.hashProgress)
                            .padding()
                    }
                }
            }
        }
    }
}

/// Resume prompt overlay
struct ResumePromptOverlay: View {
    let progress: ProgressRecord
    @EnvironmentObject var appState: AppState

    var body: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 48))
                    .foregroundColor(.accentColor)

                Text("Resume Previous Session?")
                    .font(.title2.bold())

                Text(progress.resumeDescription)
                    .font(.body)
                    .foregroundColor(.secondary)

                HStack(spacing: 16) {
                    Button("Start Fresh") {
                        appState.startFresh()
                    }
                    .buttonStyle(.bordered)

                    Button("Resume") {
                        appState.resumeFromProgress()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(40)
            .background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
    }
}

/// Error banner at bottom of screen
struct ErrorBanner: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.yellow)

            Text(message)
                .foregroundColor(.white)

            Spacer()

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .foregroundColor(.white)
            }
            .buttonStyle(.plain)
        }
        .padding()
        .background(Color.red.opacity(0.9))
        .cornerRadius(8)
        .padding()
    }
}

/// Loading overlay
struct LoadingOverlay: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.5)

                Text("Loading...")
                    .font(.headline)
                    .foregroundColor(.white)
            }
            .padding(40)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
    }
}

/// Hash computation progress indicator
struct HashProgressIndicator: View {
    let progress: Double

    var body: some View {
        HStack(spacing: 8) {
            ProgressView(value: progress)
                .frame(width: 100)

            Text("Computing hashes: \(Int(progress * 100))%")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}
