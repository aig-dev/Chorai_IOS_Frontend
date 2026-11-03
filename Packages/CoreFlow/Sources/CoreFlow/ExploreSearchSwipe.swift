public enum ExploreSearchSwipe: Equatable, Sendable {
    case previous
    case next
    case cancel

    public static func resolve(horizontal: Double, vertical: Double) -> Self {
        guard abs(horizontal) > 100, abs(horizontal) > abs(vertical) else { return .cancel }
        return horizontal > 0 ? .previous : .next
    }
}
