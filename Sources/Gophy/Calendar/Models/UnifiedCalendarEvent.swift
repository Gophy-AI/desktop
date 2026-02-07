import Foundation

enum CalendarEventSource: String, Sendable, Equatable {
    case google
    case eventKit
}

struct UnifiedCalendarEvent: Sendable, Equatable, Identifiable {
    let id: String
    let title: String
    let startDate: Date
    let endDate: Date
    let location: String?
    let isAllDay: Bool
    let meetingLink: String?
    let attendees: [MeetingAttendee]
    let source: CalendarEventSource
    let googleEventId: String?
    let calendarId: String?

    static func == (lhs: UnifiedCalendarEvent, rhs: UnifiedCalendarEvent) -> Bool {
        lhs.id == rhs.id
    }
}
