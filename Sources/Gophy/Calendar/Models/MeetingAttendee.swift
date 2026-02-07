import Foundation

struct MeetingAttendee: Sendable, Equatable, Identifiable {
    let email: String
    let displayName: String?
    let responseStatus: String?
    let isSelf: Bool

    var id: String { email }
}
