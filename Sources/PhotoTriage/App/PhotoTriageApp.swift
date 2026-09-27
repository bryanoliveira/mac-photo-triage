import SwiftUI

/// Main application entry point
@main
struct PhotoTriageApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .frame(minWidth: 820, minHeight: 560)
                .task {
                    await appState.reopenLastFolder()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            // File menu
            CommandGroup(replacing: .newItem) {
                Button("Open Folder…") {
                    openFolderDialog()
                }
                .keyboardShortcut("o", modifiers: .command)
            }

            CommandGroup(after: .newItem) {
                Divider()

                Button("Empty Trash…") {
                    appState.requestEmptyTrash()
                }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(appState.folder == nil)
            }

            // Edit menu
            CommandGroup(replacing: .undoRedo) {
                Button(appState.undoLabel.map { "Undo \($0)" } ?? "Undo") {
                    appState.undo()
                }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(!appState.canUndo)

                Button(appState.redoLabel.map { "Redo \($0)" } ?? "Redo") {
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

                Toggle("Photo Info Overlay", isOn: $appState.showEXIFOverlay)
                Toggle("Clipping Warnings", isOn: $appState.showClippingWarnings)
                Toggle("Guiding Grid", isOn: $appState.showGuidingGrid)
                Toggle("Detail Panel", isOn: $appState.showDetailPanel)
                Toggle("Sync Zoom in Triage", isOn: $appState.syncTriageZoom)
                Divider()
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

            // Error banner
            if let error = appState.errorMessage {
                VStack {
                    Spacer()
                    ErrorBanner(message: error) {
                        appState.errorMessage = nil
                    }
                    .frame(maxWidth: 560)
                    .padding(.bottom, 48)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .task(id: error) {
                    try? await Task.sleep(nanoseconds: 8_000_000_000)
                    if appState.errorMessage == error { appState.errorMessage = nil }
                }
            }

            // Toast
            if let toast = appState.toast {
                VStack {
                    Spacer()
                    ToastView(message: toast)
                        .padding(.bottom, 64)
                }
                .allowsHitTesting(false)
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
                .id(toast)
            }

            // Loading overlay
            if appState.isLoading {
                LoadingOverlay()
            }
        }
        .animation(.easeOut(duration: 0.18), value: appState.toast)
        .animation(.easeOut(duration: 0.2), value: appState.errorMessage)
        .alert("Empty Trash?", isPresented: $appState.showEmptyTrashConfirmation) {
            Button("Move \(appState.trashedCount) to Trash", role: .destructive) {
                appState.emptyTrash()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(appState.trashedCount) photo(s) marked for trash — and their RAW/JPEG partners — will be moved to the macOS Trash. You can still recover them from the Trash until you empty it.")
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
                .lineLimit(3)
                .textSelection(.enabled)

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

                Text("Opening folder…")
                    .font(.headline)
                    .foregroundColor(.white)
            }
            .padding(40)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
    }
}
