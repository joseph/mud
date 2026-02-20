enum Mode {
    case up
    case down

    func toggled() -> Mode {
        switch self {
        case .up: return .down
        case .down: return .up
        }
    }
}
