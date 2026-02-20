import SwiftUI

enum Lighting: String, CaseIterable {
    case auto
    case bright
    case dark

    /// Toggle: auto ↔ opposite of system
    func toggled() -> Lighting {
        switch self {
        case .auto:
            return Self.systemIsDark ? .bright : .dark
        case .bright, .dark:
            return .auto
        }
    }

    /// Whether this mode results in dark appearance
    func isDark() -> Bool {
        switch self {
        case .auto: return Self.systemIsDark
        case .bright: return false
        case .dark: return true
        }
    }

    /// The NSAppearance for this mode (nil = follow system)
    var appearance: NSAppearance? {
        switch self {
        case .auto: return nil
        case .bright: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }

    /// The SwiftUI ColorScheme for this mode
    func colorScheme(environment: ColorScheme) -> ColorScheme {
        switch self {
        case .auto: return environment
        case .bright: return .light
        case .dark: return .dark
        }
    }

    /// Whether the system is currently in dark mode
    static var systemIsDark: Bool {
        NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
}
