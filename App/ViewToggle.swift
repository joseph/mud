import Foundation

/// A persisted boolean toggle that maps to a CSS class on the webview root.
enum ViewToggle: String, CaseIterable {
    case readableColumn
    case lineNumbers
    case wordWrap
    case codeHeader

    var className: String {
        switch self {
        case .readableColumn: return "is-readable-column"
        case .lineNumbers: return "has-line-numbers"
        case .wordWrap: return "has-word-wrap"
        case .codeHeader: return "is-code-header"
        }
    }

    private var defaultsKey: String { "Mud-\(rawValue)" }

    private var defaultValue: Bool {
        switch self {
        case .codeHeader: return true
        default: return false
        }
    }

    var isEnabled: Bool {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: defaultsKey) == nil {
            return defaultValue
        }
        return defaults.bool(forKey: defaultsKey)
    }

    func save(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: defaultsKey)
    }
}
