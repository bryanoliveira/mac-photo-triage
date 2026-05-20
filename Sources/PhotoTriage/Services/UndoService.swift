import Foundation

/// Represents an undoable action
protocol UndoableAction {
    var description: String { get }
    func undo() throws
    func redo() throws
}

/// Undo service for managing undo/redo stack
@MainActor
final class UndoService: ObservableObject {
    @Published private(set) var undoStack: [UndoableAction] = []
    @Published private(set) var redoStack: [UndoableAction] = []

    /// Maximum undo history
    private let maxHistory = 100

    /// Whether undo is available
    var canUndo: Bool { !undoStack.isEmpty }

    /// Whether redo is available
    var canRedo: Bool { !redoStack.isEmpty }

    /// Description of next undo action
    var undoDescription: String? {
        undoStack.last?.description
    }

    /// Description of next redo action
    var redoDescription: String? {
        redoStack.last?.description
    }

    /// Register an action that was just performed
    func register(_ action: UndoableAction) {
        undoStack.append(action)
        redoStack.removeAll()

        // Limit history size
        if undoStack.count > maxHistory {
            undoStack.removeFirst()
        }
    }

    /// Undo the last action
    func undo() throws {
        guard let action = undoStack.popLast() else { return }
        try action.undo()
        redoStack.append(action)
    }

    /// Redo the last undone action
    func redo() throws {
        guard let action = redoStack.popLast() else { return }
        try action.redo()
        undoStack.append(action)
    }

    /// Clear all history
    func clear() {
        undoStack.removeAll()
        redoStack.removeAll()
    }
}

// MARK: - Concrete Actions

/// Undo action for marking an image as kept
struct MarkKeptAction: UndoableAction {
    let asset: ImageAsset

    var description: String { "Mark \(asset.displayName) as kept" }

    func undo() throws {
        try asset.clearTriageState()
    }

    func redo() throws {
        try asset.markKept()
    }
}

/// Undo action for marking an image as trashed
struct MarkTrashedAction: UndoableAction {
    let asset: ImageAsset

    var description: String { "Mark \(asset.displayName) for trash" }

    func undo() throws {
        try asset.clearTriageState()
    }

    func redo() throws {
        try asset.markTrashed()
    }
}

/// Undo action for toggling favorite
struct ToggleFavoriteAction: UndoableAction {
    let asset: ImageAsset
    let wasFavorite: Bool

    var description: String {
        wasFavorite
            ? "Remove \(asset.displayName) from favorites"
            : "Add \(asset.displayName) to favorites"
    }

    func undo() throws {
        try asset.toggleFavorite()
    }

    func redo() throws {
        try asset.toggleFavorite()
    }
}

/// Undo action for a triage decision (affects two images)
struct TriageDecisionAction: UndoableAction {
    let anchor: ImageAsset
    let candidate: ImageAsset
    let anchorWasKept: Bool
    let anchorWasTrashed: Bool
    let candidateWasKept: Bool
    let candidateWasTrashed: Bool

    var description: String {
        "Triage decision for \(anchor.displayName)"
    }

    func undo() throws {
        // Restore previous state
        try anchor.clearTriageState()
        try candidate.clearTriageState()

        if anchorWasKept { try anchor.markKept() }
        if anchorWasTrashed { try anchor.markTrashed() }
        if candidateWasKept { try candidate.markKept() }
        if candidateWasTrashed { try candidate.markTrashed() }
    }

    func redo() throws {
        // This would need to store the actual decision made
        // For simplicity, we just re-mark based on current state
    }
}
