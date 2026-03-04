enum Theme: String, CaseIterable {
    case austere
    case blues
    case earthy
    case riot
    /// Internal theme for system messages (error pages, etc.). Not user-selectable.
    case system

    static let allCases: [Theme] = [.austere, .blues, .earthy, .riot]
}
