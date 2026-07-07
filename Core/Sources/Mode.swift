/// The two document views: Mark Up (rendered) and Mark Down (raw source).
public enum Mode: Sendable {
    case up
    case down

    public func toggled() -> Mode {
        switch self {
        case .up: return .down
        case .down: return .up
        }
    }
}
