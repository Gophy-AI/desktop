import Foundation

public enum ModeState: Sendable, Equatable {
    case idle
    case loading
    case ready
    case switching
    case error(String)

    public static func == (lhs: ModeState, rhs: ModeState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.loading, .loading), (.ready, .ready), (.switching, .switching):
            return true
        case (.error(let lhsMsg), .error(let rhsMsg)):
            return lhsMsg == rhsMsg
        default:
            return false
        }
    }
}
