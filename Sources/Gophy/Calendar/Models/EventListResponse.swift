import Foundation

struct EventListResponse: Codable, Sendable {
    let items: [CalendarEvent]?
    let nextSyncToken: String?
    let nextPageToken: String?

    var events: [CalendarEvent] {
        items ?? []
    }
}
