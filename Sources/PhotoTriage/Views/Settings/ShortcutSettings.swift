import SwiftUI

/// Settings panel for configuring keyboard shortcuts
struct ShortcutSettings: View {
    @EnvironmentObject var appState: AppState
    @State private var editingAction: KeyAction?
    @State private var capturedKey: String = ""
    @State private var capturedModifiers: [String] = []

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Keyboard Shortcuts")
                    .font(.headline)

                Spacer()

                Button("Reset to Defaults") {
                    appState.keyBindings.resetToDefaults()
                }
                .buttonStyle(.bordered)
            }
            .padding()

            Divider()

            // Shortcuts list grouped by category
            List {
                ForEach(categories, id: \.self) { category in
                    Section(category) {
                        ForEach(actionsInCategory(category)) { action in
                            ShortcutRow(
                                action: action,
                                binding: appState.keyBindings.binding(for: action),
                                isEditing: editingAction == action,
                                onStartEdit: { editingAction = action },
                                onSave: { key, modifiers in
                                    saveBinding(action: action, key: key, modifiers: modifiers)
                                },
                                onCancel: { editingAction = nil }
                            )
                        }
                    }
                }
            }
        }
        .frame(minWidth: 500, minHeight: 400)
    }

    private var categories: [String] {
        Array(Set(KeyAction.allCases.map { $0.category })).sorted()
    }

    private func actionsInCategory(_ category: String) -> [KeyAction] {
        KeyAction.allCases.filter { $0.category == category }
    }

    private func saveBinding(action: KeyAction, key: String, modifiers: [String]) {
        let binding = KeyBinding(action: action, key: key, modifiers: modifiers)
        appState.keyBindings.update(binding)
        editingAction = nil
    }
}

/// Single shortcut row in settings
struct ShortcutRow: View {
    let action: KeyAction
    let binding: KeyBinding
    let isEditing: Bool
    let onStartEdit: () -> Void
    let onSave: (String, [String]) -> Void
    let onCancel: () -> Void

    @State private var capturedKey: String = ""
    @State private var capturedModifiers: [String] = []

    var body: some View {
        HStack {
            Text(action.displayName)
                .frame(maxWidth: .infinity, alignment: .leading)

            if isEditing {
                editingView
            } else {
                displayView
            }
        }
        .padding(.vertical, 4)
    }

    private var displayView: some View {
        HStack {
            Text(binding.displayString)
                .font(.system(.body, design: .monospaced))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(4)

            Button("Edit") {
                capturedKey = binding.key
                capturedModifiers = binding.modifiers
                onStartEdit()
            }
            .buttonStyle(.borderless)
        }
    }

    private var editingView: some View {
        HStack {
            KeyCaptureField(
                capturedKey: $capturedKey,
                capturedModifiers: $capturedModifiers
            )
            .frame(width: 120)

            Button("Save") {
                onSave(capturedKey, capturedModifiers)
            }
            .buttonStyle(.borderedProminent)

            Button("Cancel") {
                onCancel()
            }
            .buttonStyle(.bordered)
        }
    }
}

/// Field that captures key presses
struct KeyCaptureField: NSViewRepresentable {
    @Binding var capturedKey: String
    @Binding var capturedModifiers: [String]

    func makeNSView(context: Context) -> KeyCaptureNSTextField {
        let textField = KeyCaptureNSTextField()
        textField.delegate = context.coordinator
        textField.onKeyCapture = { key, modifiers in
            capturedKey = key
            capturedModifiers = modifiers
        }
        return textField
    }

    func updateNSView(_ nsView: KeyCaptureNSTextField, context: Context) {
        nsView.stringValue = displayString
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    private var displayString: String {
        var parts: [String] = []
        for mod in capturedModifiers.sorted() {
            switch mod.lowercased() {
            case "command": parts.append("⌘")
            case "shift": parts.append("⇧")
            case "option": parts.append("⌥")
            case "control": parts.append("⌃")
            default: break
            }
        }
        parts.append(capturedKey.uppercased())
        return parts.joined()
    }

    class Coordinator: NSObject, NSTextFieldDelegate {}
}

/// Custom text field that captures key events
class KeyCaptureNSTextField: NSTextField {
    var onKeyCapture: ((String, [String]) -> Void)?

    override func keyDown(with event: NSEvent) {
        var modifiers: [String] = []

        if event.modifierFlags.contains(.command) {
            modifiers.append("command")
        }
        if event.modifierFlags.contains(.shift) {
            modifiers.append("shift")
        }
        if event.modifierFlags.contains(.option) {
            modifiers.append("option")
        }
        if event.modifierFlags.contains(.control) {
            modifiers.append("control")
        }

        var key = ""

        switch event.keyCode {
        case 123: key = "left"
        case 124: key = "right"
        case 125: key = "down"
        case 126: key = "up"
        case 36: key = "return"
        case 53: key = "escape"
        case 49: key = "space"
        case 51: key = "delete"
        case 48: key = "tab"
        default:
            if let chars = event.charactersIgnoringModifiers {
                key = chars.lowercased()
            }
        }

        if !key.isEmpty {
            onKeyCapture?(key, modifiers)
        }
    }

    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool {
        true
    }
}
