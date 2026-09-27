import SwiftUI
import AppKit

// MARK: - Public extension used by views

extension View {
    /// Installs a keyboard handler that intercepts key events via a local NSEvent monitor.
    /// The monitor is active while this view is in the window; events that are handled
    /// (handler returns true) are consumed so macOS never plays the error beep.
    func focusedKeyboardHandler(_ handler: @escaping (KeyAction) -> Bool) -> some View {
        modifier(FocusedKeyboardHandler(onKeyPress: handler))
    }
}

// MARK: - ViewModifier

struct FocusedKeyboardHandler: ViewModifier {
    @EnvironmentObject var appState: AppState
    let onKeyPress: (KeyAction) -> Bool

    func body(content: Content) -> some View {
        content.background(
            KeyMonitorView { [appState] event in
                handleKeyEvent(event, keyBindings: appState.keyBindings)
            }
        )
    }

    private func handleKeyEvent(_ event: NSEvent, keyBindings: KeyBindings) -> Bool {
        guard let characters = event.charactersIgnoringModifiers?.lowercased() else { return false }

        var modifiers: EventModifiers = []
        if event.modifierFlags.contains(.command) { modifiers.insert(.command) }
        if event.modifierFlags.contains(.shift)   { modifiers.insert(.shift) }
        if event.modifierFlags.contains(.option)  { modifiers.insert(.option) }
        if event.modifierFlags.contains(.control) { modifiers.insert(.control) }

        for action in KeyAction.allCases {
            let binding = keyBindings.binding(for: action)
            if matches(binding, key: characters, event: event, modifiers: modifiers) {
                return onKeyPress(action)
            }
        }
        return false
    }

    private func matches(_ binding: KeyBinding, key: String, event: NSEvent, modifiers: EventModifiers) -> Bool {
        KeyEventMatcher.matches(binding, key: key, keyCode: event.keyCode, modifiers: modifiers)
    }
}

/// Pure key-matching logic, separated from NSEvent so it can be unit-tested.
enum KeyEventMatcher {
    static func matches(_ binding: KeyBinding, key: String, keyCode: UInt16, modifiers: EventModifiers) -> Bool {
        let k = binding.key.lowercased()

        // Symbols like "+" need Shift on most layouts ("=" key). A binding for a symbol without
        // an explicit Shift should fire whether or not Shift was held, and "+" also accepts the
        // unshifted "=" so the zoom/grid shortcut works without reaching for Shift.
        if k.count == 1, let ch = k.first, !ch.isLetter, !ch.isNumber, !binding.eventModifiers.contains(.shift) {
            let mods = modifiers.subtracting(.shift)
            guard binding.eventModifiers == mods else { return false }
            if k == "+" { return key == "+" || key == "=" }
            if k == "-" { return key == "-" || key == "_" }
            return key == k
        }

        guard binding.eventModifiers == modifiers else { return false }
        switch keyCode {
        case 123 where k == "left"   || k == "leftarrow":  return true
        case 124 where k == "right"  || k == "rightarrow": return true
        case 125 where k == "down"   || k == "downarrow":  return true
        case 126 where k == "up"     || k == "uparrow":    return true
        case 36  where k == "return" || k == "enter":      return true
        case 53  where k == "escape" || k == "esc":        return true
        case 49  where k == "space":                       return true
        case 51  where k == "delete" || k == "backspace":  return true
        default: break
        }
        return key == k
    }
}

// MARK: - NSViewRepresentable

/// Zero-size NSView that installs a local key-down monitor for the lifetime it is in a window.
/// Local monitors fire before the responder chain, so returning nil consumes the event
/// and prevents the system error beep.
struct KeyMonitorView: NSViewRepresentable {
    let handler: (NSEvent) -> Bool

    func makeNSView(context: Context) -> KeyMonitorNSView {
        let v = KeyMonitorNSView()
        v.handler = handler
        return v
    }

    func updateNSView(_ nsView: KeyMonitorNSView, context: Context) {
        nsView.handler = handler
    }

    class KeyMonitorNSView: NSView {
        var handler: ((NSEvent) -> Bool)?
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window != nil { installMonitor() } else { removeMonitor() }
        }

        private func installMonitor() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                // Only handle keys aimed at our window (not Settings), and never while the user
                // is typing into a text field.
                guard let self, let window = self.window, event.window === window,
                      !(window.firstResponder is NSText) else { return event }
                return (self.handler?(event) == true) ? nil : event
            }
        }

        private func removeMonitor() {
            if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
        }

        deinit { removeMonitor() }
    }
}
