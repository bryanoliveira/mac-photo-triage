import XCTest
import SwiftUI
@testable import PhotoTriage

final class KeyEventMatcherTests: XCTestCase {
    private func binding(_ key: String, _ mods: [String] = []) -> KeyBinding {
        KeyBinding(action: .gridIncrease, key: key, modifiers: mods)
    }

    func testPlusMatchesWithOrWithoutShift() {
        XCTAssertTrue(KeyEventMatcher.matches(binding("+"), key: "+", keyCode: 24, modifiers: .shift))
        XCTAssertTrue(KeyEventMatcher.matches(binding("+"), key: "=", keyCode: 24, modifiers: []))
        XCTAssertFalse(KeyEventMatcher.matches(binding("+"), key: "+", keyCode: 24, modifiers: .command))
    }

    func testMinusAcceptsUnderscore() {
        XCTAssertTrue(KeyEventMatcher.matches(binding("-"), key: "-", keyCode: 27, modifiers: []))
        XCTAssertTrue(KeyEventMatcher.matches(binding("-"), key: "_", keyCode: 27, modifiers: .shift))
    }

    func testLettersRequireExactModifiers() {
        XCTAssertTrue(KeyEventMatcher.matches(binding("k"), key: "k", keyCode: 40, modifiers: []))
        XCTAssertFalse(KeyEventMatcher.matches(binding("k"), key: "k", keyCode: 40, modifiers: .shift))
        XCTAssertTrue(KeyEventMatcher.matches(binding("p", ["shift"]), key: "p", keyCode: 35, modifiers: .shift))
    }

    func testSpecialKeysMatchByKeyCode() {
        XCTAssertTrue(KeyEventMatcher.matches(binding("right"), key: "\u{F703}", keyCode: 124, modifiers: []))
        XCTAssertTrue(KeyEventMatcher.matches(binding("right", ["command"]), key: "\u{F703}", keyCode: 124, modifiers: .command))
        XCTAssertFalse(KeyEventMatcher.matches(binding("right"), key: "\u{F703}", keyCode: 124, modifiers: .command))
        XCTAssertTrue(KeyEventMatcher.matches(binding("delete"), key: "\u{7F}", keyCode: 51, modifiers: []))
    }

    func testNewDefaultBindingsDoNotCollide() {
        let bindings = KeyBindings.defaults.values
        var seen = Set<String>()
        for b in bindings {
            let id = "\(b.key.lowercased())|\(b.modifiers.sorted().joined(separator: ","))"
            XCTAssertFalse(seen.contains(id), "duplicate default binding \(id)")
            seen.insert(id)
        }
        XCTAssertEqual(KeyBindings.defaults[.keepCurrentImage]?.key, "k")
        XCTAssertEqual(KeyBindings.defaults[.clearDecision]?.key, "u")
        XCTAssertEqual(KeyBindings.defaults[.zoomActualSize]?.key, "z")
    }
}
