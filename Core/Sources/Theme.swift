public enum Theme: String, CaseIterable, Sendable {
    case austere
    case blues
    case earthy
    case riot
    /// Internal theme for system messages (error pages, etc.). Not user-selectable.
    case system

    public static let allCases: [Theme] = [.austere, .blues, .earthy, .riot]
}
