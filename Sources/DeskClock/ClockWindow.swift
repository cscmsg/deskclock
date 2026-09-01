import AppKit

// The three fixed clock sizes offered in the menu. Square point dimensions.
enum ClockSize: String, CaseIterable {
    case small, medium, large

    var points: CGFloat {
        switch self {
        case .small:  return 140
        case .medium: return 200
        case .large:  return 280
        }
    }

    var title: String {
        switch self {
        case .small:  return "Small"
        case .medium: return "Medium"
        case .large:  return "Large"
        }
    }

    var shortLabel: String {
        switch self {
        case .small:  return "S"
        case .medium: return "M"
        case .large:  return "L"
        }
    }
}

// A borderless, transparent, always-on-top window that shows only the clock
// face. No title bar, no background rectangle, no window shadow.
final class ClockWindow: NSWindow {

    init(size: CGFloat) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: size, height: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        // Transparent chrome — only what SwiftUI draws is visible.
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false

        // Float above normal windows, follow across every Space, and (when the
        // collection behavior includes .fullScreenAuxiliary) sit over fullscreen
        // apps too.
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        // Drag the clock by grabbing anywhere on the face.
        isMovableByWindowBackground = true

        isExcludedFromWindowsMenu = true
        isReleasedWhenClosed = false
    }

    // Borderless windows refuse key/main status by default; allow it so the
    // window reliably receives the mouse for dragging.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
