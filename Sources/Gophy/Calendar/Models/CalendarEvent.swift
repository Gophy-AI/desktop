import Foundation

struct CalendarEvent: Codable, Sendable, Equatable, Identifiable {
    let id: String
    let summary: String?
    let description: String?
    let start: EventDateTime?
    let end: EventDateTime?
    let location: String?
    let status: String?
    let attendees: [Attendee]?
    let conferenceData: ConferenceData?
    let hangoutLink: String?
    let htmlLink: String?
    let organizer: Person?
    let extendedProperties: ExtendedProperties?

    var startDate: Date? {
        start?.resolvedDate
    }

    var endDate: Date? {
        end?.resolvedDate
    }

    var meetingLink: String? {
        if let entryPoints = conferenceData?.entryPoints {
            for entryPoint in entryPoints where entryPoint.entryPointType == "video" {
                return entryPoint.uri
            }
        }
        return hangoutLink
    }
}

struct EventDateTime: Codable, Sendable, Equatable {
    let dateTime: String?
    let dateValue: String?
    let timeZone: String?

    enum CodingKeys: String, CodingKey {
        case dateTime
        case dateValue = "date"
        case timeZone
    }

    var resolvedDate: Date? {
        if let dateTimeStr = dateTime {
            return Self.parseISO8601(dateTimeStr)
        }
        if let dateStr = dateValue {
            return Self.parseDateOnly(dateStr)
        }
        return nil
    }

    var isAllDay: Bool {
        dateValue != nil && dateTime == nil
    }

    private static func parseISO8601(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }

    private static func parseDateOnly(_ string: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.date(from: string)
    }
}

struct Attendee: Codable, Sendable, Equatable {
    let email: String?
    let displayName: String?
    let responseStatus: String?
    let isSelf: Bool?

    enum CodingKeys: String, CodingKey {
        case email
        case displayName
        case responseStatus
        case isSelf = "self"
    }
}

struct ConferenceData: Codable, Sendable, Equatable {
    let entryPoints: [EntryPoint]?
}

struct EntryPoint: Codable, Sendable, Equatable {
    let uri: String?
    let label: String?
    let entryPointType: String?
}

struct Person: Codable, Sendable, Equatable {
    let email: String?
    let displayName: String?
}

struct ExtendedProperties: Codable, Sendable, Equatable {
    let `private`: [String: String]?
    let shared: [String: String]?
}
