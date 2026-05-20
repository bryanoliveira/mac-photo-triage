import XCTest
@testable import PhotoTriage

final class KeyBindingsTests: XCTestCase {

    var keyBindings: KeyBindings!

    override func setUp() {
        super.setUp()
        keyBindings = KeyBindings()
        keyBindings.resetToDefaults()
    }

    func testDefaultBindings() {
        let keepLeft = keyBindings.binding(for: .keepLeft)
        XCTAssertEqual(keepLeft.key, "l")
        XCTAssertTrue(keepLeft.modifiers.isEmpty)

        let keepRight = keyBindings.binding(for: .keepRight)
        XCTAssertEqual(keepRight.key, "r")

        let rotateCW = keyBindings.binding(for: .rotateCW)
        XCTAssertEqual(rotateCW.key, "right")
        XCTAssertTrue(rotateCW.modifiers.contains("command"))
    }

    func testUpdateBinding() {
        let newBinding = KeyBinding(
            action: .keepLeft,
            key: "k",
            modifiers: ["shift"]
        )

        keyBindings.update(newBinding)

        let updated = keyBindings.binding(for: .keepLeft)
        XCTAssertEqual(updated.key, "k")
        XCTAssertTrue(updated.modifiers.contains("shift"))
    }

    func testResetToDefaults() {
        // Modify a binding
        let newBinding = KeyBinding(
            action: .keepLeft,
            key: "x",
            modifiers: []
        )
        keyBindings.update(newBinding)

        // Reset
        keyBindings.resetToDefaults()

        // Should be back to default
        let binding = keyBindings.binding(for: .keepLeft)
        XCTAssertEqual(binding.key, "l")
    }

    func testDisplayString() {
        let binding1 = KeyBinding(action: .undo, key: "z", modifiers: ["command"])
        XCTAssertEqual(binding1.displayString, "⌘Z")

        let binding2 = KeyBinding(action: .redo, key: "z", modifiers: ["command", "shift"])
        XCTAssertTrue(binding2.displayString.contains("⌘"))
        XCTAssertTrue(binding2.displayString.contains("⇧"))
        XCTAssertTrue(binding2.displayString.contains("Z"))

        let binding3 = KeyBinding(action: .navigateLeft, key: "left", modifiers: [])
        XCTAssertEqual(binding3.displayString, "←")

        let binding4 = KeyBinding(action: .applyCrop, key: "return", modifiers: [])
        XCTAssertEqual(binding4.displayString, "↩")
    }

    func testKeyActionCategories() {
        XCTAssertEqual(KeyAction.keepLeft.category, "Triage Actions")
        XCTAssertEqual(KeyAction.navigateLeft.category, "Navigation")
        XCTAssertEqual(KeyAction.rotateCW.category, "Preview")
        XCTAssertEqual(KeyAction.trashCurrentImage.category, "Preview")
        XCTAssertEqual(KeyAction.toggleClipping.category, "View")
        XCTAssertEqual(KeyAction.undo.category, "System")
    }

    func testKeyActionDisplayNames() {
        XCTAssertEqual(KeyAction.keepLeft.displayName, "Keep Left")
        XCTAssertEqual(KeyAction.keepRight.displayName, "Keep Right")
        XCTAssertEqual(KeyAction.toggleFavorite.displayName, "Toggle Favorite")
        XCTAssertEqual(KeyAction.emptyTrash.displayName, "Empty Trash")
        XCTAssertEqual(KeyAction.trashCurrentImage.displayName, "Trash Current Image")
        XCTAssertEqual(KeyAction.toggleClipping.displayName, "Toggle Clipping Warnings")
    }

    func testTrashCurrentImageDefault() {
        let binding = keyBindings.binding(for: .trashCurrentImage)
        XCTAssertEqual(binding.key, "delete")
        XCTAssertTrue(binding.modifiers.isEmpty)
    }

    func testToggleClippingDefault() {
        let binding = keyBindings.binding(for: .toggleClipping)
        XCTAssertEqual(binding.key, "w")
        XCTAssertTrue(binding.modifiers.isEmpty)
    }

    func testAllActionsHaveDefaults() {
        for action in KeyAction.allCases {
            let binding = keyBindings.binding(for: action)
            XCTAssertFalse(binding.key.isEmpty, "Action \(action) should have a default key")
        }
    }

    func testKeyEquivalentArrowKeys() {
        let left = KeyBinding(action: .navigateLeft, key: "left", modifiers: [])
        let right = KeyBinding(action: .navigateRight, key: "right", modifiers: [])
        let up = KeyBinding(action: .candidateUp, key: "up", modifiers: [])
        let down = KeyBinding(action: .candidateDown, key: "down", modifiers: [])

        XCTAssertNotNil(left.keyEquivalent)
        XCTAssertNotNil(right.keyEquivalent)
        XCTAssertNotNil(up.keyEquivalent)
        XCTAssertNotNil(down.keyEquivalent)
    }

    func testEventModifiers() {
        let commandOnly = KeyBinding(action: .undo, key: "z", modifiers: ["command"])
        XCTAssertTrue(commandOnly.eventModifiers.contains(.command))
        XCTAssertFalse(commandOnly.eventModifiers.contains(.shift))

        let commandShift = KeyBinding(action: .redo, key: "z", modifiers: ["command", "shift"])
        XCTAssertTrue(commandShift.eventModifiers.contains(.command))
        XCTAssertTrue(commandShift.eventModifiers.contains(.shift))

        let noModifiers = KeyBinding(action: .keepLeft, key: "l", modifiers: [])
        XCTAssertTrue(noModifiers.eventModifiers.isEmpty)
    }
}
