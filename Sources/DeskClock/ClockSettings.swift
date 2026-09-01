import SwiftUI

// Color themes. The translucent disc, rim and minute ticks always stay adaptive
// (light/dark) so the face reads on any wallpaper; a theme recolors the hands,
// the second hand and the numerals.
enum ClockTheme: String, CaseIterable {
    case classic, monochrome, ocean, forest, sunset, berry

    var title: String {
        switch self {
        case .classic:    return "Classic"
        case .monochrome: return "Monochrome"
        case .ocean:      return "Ocean"
        case .forest:     return "Forest"
        case .sunset:     return "Sunset"
        case .berry:      return "Berry"
        }
    }

    // Hour and minute hands.
    func handColor(_ scheme: ColorScheme) -> Color {
        switch self {
        case .classic, .monochrome:
            return scheme == .dark ? .white : Color.black.opacity(0.88)
        case .ocean:  return Color(red: 0.23, green: 0.51, blue: 0.96)
        case .forest: return Color(red: 0.13, green: 0.77, blue: 0.37)
        case .sunset: return Color(red: 0.98, green: 0.45, blue: 0.09)
        case .berry:  return Color(red: 0.66, green: 0.33, blue: 0.97)
        }
    }

    // Second hand + center cap.
    func secondColor(_ scheme: ColorScheme) -> Color {
        switch self {
        case .classic:
            return scheme == .dark ? Color(red: 1.00, green: 0.42, blue: 0.36)
                                   : Color(red: 0.86, green: 0.18, blue: 0.18)
        case .monochrome:
            return scheme == .dark ? Color.white.opacity(0.70) : Color.black.opacity(0.55)
        case .ocean:  return Color(red: 0.02, green: 0.71, blue: 0.83)
        case .forest: return Color(red: 0.64, green: 0.90, blue: 0.21)
        case .sunset: return Color(red: 0.94, green: 0.27, blue: 0.27)
        case .berry:  return Color(red: 0.93, green: 0.28, blue: 0.60)
        }
    }
}

// Single source of truth for every persisted preference. The menu mutates it
// (and the window-side effects are applied by the AppDelegate); the SwiftUI
// face observes it and redraws.
final class ClockSettings: ObservableObject {
    @Published var size: ClockSize
    @Published var opacity: Double          // window alpha, 0.3...1.0
    @Published var theme: ClockTheme
    @Published var showNumerals: Bool
    @Published var sweepSeconds: Bool
    @Published var floatOverFullscreen: Bool
    @Published var clickThrough: Bool

    // Transient hover-preview of a theme (not persisted). The face draws this
    // over `theme` while the settings popover is previewing a selection.
    @Published var previewTheme: ClockTheme? = nil

    // Transient (not persisted). False while the clock can't actually be seen —
    // display asleep, screen saver up, or the window fully occluded. The face
    // watches this to drop its periodic redraw to a single static frame so it
    // stops burning CPU rendering frames nobody sees. Driven by the AppDelegate.
    @Published var renderActive: Bool = true

    // Window position — not @Published (it doesn't affect the drawn face).
    var originX: Double?
    var originY: Double?

    static let minOpacity = 0.3
    static let maxOpacity = 1.0

    private enum Key {
        static let size         = "clock.size"
        static let opacity      = "clock.opacity"
        static let theme        = "clock.theme"
        static let numerals     = "clock.showNumerals"
        static let sweep        = "clock.sweepSeconds"
        static let float        = "clock.floatOverFullscreen"
        static let clickThrough = "clock.clickThrough"
        static let originX      = "clock.originX"
        static let originY      = "clock.originY"
    }

    init() {
        let d = UserDefaults.standard
        size = ClockSize(rawValue: d.string(forKey: Key.size) ?? "") ?? .medium
        theme = ClockTheme(rawValue: d.string(forKey: Key.theme) ?? "") ?? .classic
        opacity = d.object(forKey: Key.opacity) != nil ? d.double(forKey: Key.opacity) : 1.0
        showNumerals = d.bool(forKey: Key.numerals)        // default false
        sweepSeconds = d.bool(forKey: Key.sweep)           // default false
        floatOverFullscreen = d.object(forKey: Key.float) != nil ? d.bool(forKey: Key.float) : true
        clickThrough = d.bool(forKey: Key.clickThrough)    // default false
        originX = d.object(forKey: Key.originX) != nil ? d.double(forKey: Key.originX) : nil
        originY = d.object(forKey: Key.originY) != nil ? d.double(forKey: Key.originY) : nil
        opacity = min(max(opacity, Self.minOpacity), Self.maxOpacity)
    }

    func save() {
        let d = UserDefaults.standard
        d.set(size.rawValue, forKey: Key.size)
        d.set(opacity, forKey: Key.opacity)
        d.set(theme.rawValue, forKey: Key.theme)
        d.set(showNumerals, forKey: Key.numerals)
        d.set(sweepSeconds, forKey: Key.sweep)
        d.set(floatOverFullscreen, forKey: Key.float)
        d.set(clickThrough, forKey: Key.clickThrough)
        if let originX { d.set(originX, forKey: Key.originX) }
        if let originY { d.set(originY, forKey: Key.originY) }
    }
}
