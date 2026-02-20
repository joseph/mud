import Foundation

/// A persisted boolean toggle that maps to a CSS class on the webview root.
enum ViewToggle: String, CaseIterable {
    case readableColumn
    case lineNumbers
    case wordWrap

    var className: String {
        switch self {
        case .readableColumn: return "is-readable-column"
        case .lineNumbers: return "has-line-numbers"
        case .wordWrap: return "has-word-wrap"
        }
    }

    private var defaultsKey: String { "Mud-\(rawValue)" }

    var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: defaultsKey)
    }

    func save(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: defaultsKey)
    }
}
