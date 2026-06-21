import Foundation

/// A persisted boolean toggle that maps to a CSS class on the webview root.
public enum ViewToggle: String, CaseIterable, Sendable {
    case readableColumn
    case lineNumbers
    case wordWrap
    case codeHeader
    case autoExpandChanges

    public var className: String {
        switch self {
        case .readableColumn: return "is-readable-column"
        case .lineNumbers: return "has-line-numbers"
        case .wordWrap: return "has-word-wrap"
        case .codeHeader: return "is-code-header"
        case .autoExpandChanges: return "is-auto-expand-changes"
        }
    }

    /// The persistence key that backs this toggle.
    var key: MudPreferences.Keys {
        switch self {
        case .readableColumn:    return .uiShowReadableColumn
        case .lineNumbers:       return .downModeShowLineNumbers
        case .wordWrap:          return .downModeWrapLines
        case .codeHeader:        return .upModeShowCodeHeader
        case .autoExpandChanges: return .changesAutoExpandGroups
        }
    }

    /// The hard-coded default if the key has never been written.
    var defaultValue: Bool {
        switch self {
        case .readableColumn:    return false
        case .lineNumbers:       return true
        case .wordWrap:          return true
        case .codeHeader:        return true
        case .autoExpandChanges: return false
        }
    }

    public var isEnabled: Bool {
        MudPreferences.shared.readViewToggle(self)
    }

    public func save(_ enabled: Bool) {
        MudPreferences.shared.writeViewToggle(self, enabled: enabled)
    }
}
