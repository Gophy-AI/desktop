import Foundation

public struct LocalCalendarEvent: Sendable, Equatable, Identifiable {
    public let identifier: String
    public let title: String
    public let startDate: Date
    public let endDate: Date
    public let location: String?
    public let notes: String?
    public let calendarTitle: String
    public let isAllDay: Bool
    public let url: URL?
    public let organizer: String?

    public var id: String { identifier }

    public init(
        identifier: String,
        title: String,
        startDate: Date,
        endDate: Date,
        location: String?,
        notes: String?,
        calendarTitle: String,
        isAllDay: Bool,
        url: URL?,
        organizer: String?
    ) {
        self.identifier = identifier
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.location = location
        self.notes = notes
        self.calendarTitle = calendarTitle
        self.isAllDay = isAllDay
        self.url = url
        self.organizer = organizer
    }
}
