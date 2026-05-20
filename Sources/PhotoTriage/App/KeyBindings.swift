import Foundation
import SwiftUI

/// Action identifiers for keyboard shortcuts
enum KeyAction: String, CaseIterable, Identifiable, Codable {
    // Navigation
    case navigateLeft = "navigate.left"
    case navigateRight = "navigate.right"
    case candidateUp = "triage.candidateUp"
    case candidateDown = "triage.candidateDown"

    // Triage actions
    case keepLeft = "triage.keepLeft"
    case keepRight = "triage.keepRight"
    case keepBoth = "triage.keepBoth"
    case keepNone = "triage.keepNone"

    // Preview actions
    case rotateCCW = "preview.rotateCCW"
    case rotateCW = "preview.rotateCW"
    case applyCrop = "preview.applyCrop"
    case cancelCrop = "preview.cancelCrop"
    case trashCurrentImage = "preview.trash"

    // View toggles
    case toggleZoom = "view.toggleZoom"
    case toggleEXIF = "view.toggleEXIF"
    case toggleClipping = "view.toggleClipping"
    case switchToTriage = "view.triage"
    case switchToGallery = "view.gallery"
    case toggleFavorite = "view.favorite"

    // Triage-specific
    case openLeftPreview = "triage.previewLeft"
    case openRightPreview = "triage.previewRight"

    // System
    case undo = "system.undo"
    case redo = "system.redo"
    case openFolder = "system.openFolder"
    case emptyTrash = "system.emptyTrash"

    // Gallery
    case gridIncrease = "gallery.gridIncrease"
    case gridDecrease = "gallery.gridDecrease"

    var id: String { rawValue }

    /// Human-readable name for display
    var displayName: String {
        switch self {
        case .navigateLeft: return "Navigate Left"
        case .navigateRight: return "Navigate Right"
        case .candidateUp: return "Previous Candidate"
        case .candidateDown: return "Next Candidate"
        case .keepLeft: return "Keep Left"
        case .keepRight: return "Keep Right"
        case .keepBoth: return "Keep Both"
        case .keepNone: return "Keep None (Trash Both)"
        case .rotateCCW: return "Rotate 90° CCW"
        case .rotateCW: return "Rotate 90° CW"
        case .applyCrop: return "Apply Crop"
        case .cancelCrop: return "Cancel / Back"
        case .trashCurrentImage: return "Trash Current Image"
        case .toggleZoom: return "Toggle Zoom"
        case .toggleEXIF: return "Toggle EXIF Overlay"
        case .toggleClipping: return "Toggle Clipping Warnings"
        case .switchToTriage: return "Switch to Triage"
        case .switchToGallery: return "Switch to Gallery"
        case .toggleFavorite: return "Toggle Favorite"
        case .openLeftPreview: return "Preview Left Image"
        case .openRightPreview: return "Preview Right Image"
        case .undo: return "Undo"
        case .redo: return "Redo"
        case .openFolder: return "Open Folder"
        case .emptyTrash: return "Empty Trash"
        case .gridIncrease: return "Increase Grid Size"
        case .gridDecrease: return "Decrease Grid Size"
        }
    }

    /// Category for grouping in settings
    var category: String {
        switch self {
        case .navigateLeft, .navigateRight, .candidateUp, .candidateDown:
            return "Navigation"
        case .keepLeft, .keepRight, .keepBoth, .keepNone:
            return "Triage Actions"
        case .rotateCCW, .rotateCW, .applyCrop, .cancelCrop, .trashCurrentImage:
            return "Preview"
        case .toggleZoom, .toggleEXIF, .toggleClipping, .switchToTriage, .switchToGallery, .toggleFavorite:
            return "View"
        case .openLeftPreview, .openRightPreview:
            return "Triage"
        case .undo, .redo, .openFolder, .emptyTrash:
            return "System"
        case .gridIncrease, .gridDecrease:
            return "Gallery"
        }
    }
}

/// A single key binding configuration
struct KeyBinding: Codable, Equatable, Identifiable {
    let action: KeyAction
    var key: String               // Character or special key name
    var modifiers: [String]       // Modifier names: "command", "shift", "option", "control"

    var id: String { action.rawValue }

    /// Create KeyEquivalent for SwiftUI
    var keyEquivalent: KeyEquivalent? {
        if key.count == 1 {
            return KeyEquivalent(Character(key))
        }
        switch key.lowercased() {
        case "left", "leftarrow": return .leftArrow
        case "right", "rightarrow": return .rightArrow
        case "up", "uparrow": return .upArrow
        case "down", "downarrow": return .downArrow
        case "return", "enter": return .return
        case "escape", "esc": return .escape
        case "space": return .space
        case "delete", "backspace": return .delete
        case "tab": return .tab
        default: return nil
        }
    }

    /// Create EventModifiers for SwiftUI
    var eventModifiers: EventModifiers {
        var result: EventModifiers = []
        for mod in modifiers {
            switch mod.lowercased() {
            case "command", "cmd": result.insert(.command)
            case "shift": result.insert(.shift)
            case "option", "alt": result.insert(.option)
            case "control", "ctrl": result.insert(.control)
            default: break
            }
        }
        return result
    }

    /// Display string for the key combo
    var displayString: String {
        var parts: [String] = []
        for mod in modifiers.sorted() {
            switch mod.lowercased() {
            case "command", "cmd": parts.append("⌘")
            case "shift": parts.append("⇧")
            case "option", "alt": parts.append("⌥")
            case "control", "ctrl": parts.append("⌃")
            default: break
            }
        }

        switch key.lowercased() {
        case "left", "leftarrow": parts.append("←")
        case "right", "rightarrow": parts.append("→")
        case "up", "uparrow": parts.append("↑")
        case "down", "downarrow": parts.append("↓")
        case "return", "enter": parts.append("↩")
        case "escape", "esc": parts.append("⎋")
        case "space": parts.append("Space")
        case "delete", "backspace": parts.append("⌫")
        case "tab": parts.append("⇥")
        default: parts.append(key.uppercased())
        }

        return parts.joined()
    }
}

/// Manages all keyboard bindings
final class KeyBindings: ObservableObject {
    @Published var bindings: [KeyAction: KeyBinding]

    private static let userDefaultsKey = "PhotoTriage.KeyBindings"

    /// Default key bindings
    static let defaults: [KeyAction: KeyBinding] = [
        // Navigation
        .navigateLeft: KeyBinding(action: .navigateLeft, key: "left", modifiers: []),
        .navigateRight: KeyBinding(action: .navigateRight, key: "right", modifiers: []),
        .candidateUp: KeyBinding(action: .candidateUp, key: "up", modifiers: []),
        .candidateDown: KeyBinding(action: .candidateDown, key: "down", modifiers: []),

        // Triage
        .keepLeft: KeyBinding(action: .keepLeft, key: "l", modifiers: []),
        .keepRight: KeyBinding(action: .keepRight, key: "r", modifiers: []),
        .keepBoth: KeyBinding(action: .keepBoth, key: "b", modifiers: []),
        .keepNone: KeyBinding(action: .keepNone, key: "n", modifiers: []),

        // Preview
        .rotateCCW: KeyBinding(action: .rotateCCW, key: "left", modifiers: ["command"]),
        .rotateCW: KeyBinding(action: .rotateCW, key: "right", modifiers: ["command"]),
        .applyCrop: KeyBinding(action: .applyCrop, key: "return", modifiers: []),
        .cancelCrop: KeyBinding(action: .cancelCrop, key: "escape", modifiers: []),
        .trashCurrentImage: KeyBinding(action: .trashCurrentImage, key: "delete", modifiers: []),

        // View
        .toggleZoom: KeyBinding(action: .toggleZoom, key: "space", modifiers: []),
        .toggleEXIF: KeyBinding(action: .toggleEXIF, key: "i", modifiers: []),
        .toggleClipping: KeyBinding(action: .toggleClipping, key: "w", modifiers: []),
        .switchToTriage: KeyBinding(action: .switchToTriage, key: "t", modifiers: []),
        .switchToGallery: KeyBinding(action: .switchToGallery, key: "g", modifiers: []),
        .toggleFavorite: KeyBinding(action: .toggleFavorite, key: "f", modifiers: []),

        // Triage preview
        .openLeftPreview: KeyBinding(action: .openLeftPreview, key: "p", modifiers: []),
        .openRightPreview: KeyBinding(action: .openRightPreview, key: "p", modifiers: ["shift"]),

        // System
        .undo: KeyBinding(action: .undo, key: "z", modifiers: ["command"]),
        .redo: KeyBinding(action: .redo, key: "z", modifiers: ["command", "shift"]),
        .openFolder: KeyBinding(action: .openFolder, key: "o", modifiers: ["command"]),
        .emptyTrash: KeyBinding(action: .emptyTrash, key: "delete", modifiers: ["command"]),

        // Gallery
        .gridIncrease: KeyBinding(action: .gridIncrease, key: "+", modifiers: []),
        .gridDecrease: KeyBinding(action: .gridDecrease, key: "-", modifiers: []),
    ]

    init() {
        // Load from UserDefaults or use defaults
        if let data = UserDefaults.standard.data(forKey: Self.userDefaultsKey),
           let decoded = try? JSONDecoder().decode([String: KeyBinding].self, from: data) {
            var bindings: [KeyAction: KeyBinding] = [:]
            for (key, value) in decoded {
                if let action = KeyAction(rawValue: key) {
                    bindings[action] = value
                }
            }
            // Fill in any missing defaults
            for (action, binding) in Self.defaults {
                if bindings[action] == nil {
                    bindings[action] = binding
                }
            }
            self.bindings = bindings
        } else {
            self.bindings = Self.defaults
        }
    }

    /// Get binding for an action
    func binding(for action: KeyAction) -> KeyBinding {
        bindings[action] ?? Self.defaults[action]!
    }

    /// Update a binding
    func update(_ binding: KeyBinding) {
        bindings[binding.action] = binding
        save()
    }

    /// Reset to defaults
    func resetToDefaults() {
        bindings = Self.defaults
        save()
    }

    /// Save to UserDefaults
    func save() {
        var encoded: [String: KeyBinding] = [:]
        for (action, binding) in bindings {
            encoded[action.rawValue] = binding
        }
        if let data = try? JSONEncoder().encode(encoded) {
            UserDefaults.standard.set(data, forKey: Self.userDefaultsKey)
        }
    }

    /// Check if a key event matches an action
    func matches(key: String, modifiers: EventModifiers, action: KeyAction) -> Bool {
        let binding = binding(for: action)

        guard let bindingKey = binding.keyEquivalent else { return false }
        guard let eventKey = KeyEquivalent(Character(key)).character else { return false }

        let keyMatches = bindingKey.character?.lowercased() == eventKey.lowercased()
        let modifiersMatch = binding.eventModifiers == modifiers

        return keyMatches && modifiersMatch
    }
}

extension KeyEquivalent {
    var character: Character? {
        let mirror = Mirror(reflecting: self)
        for child in mirror.children {
            if let char = child.value as? Character {
                return char
            }
        }
        return nil
    }
}
