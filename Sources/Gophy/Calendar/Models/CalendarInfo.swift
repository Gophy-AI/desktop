import Foundation

struct CalendarInfo: Codable, Sendable, Equatable, Identifiable {
    let id: String
    let summary: String
    let primary: Bool?
    let backgroundColor: String?

    enum CodingKeys: String, CodingKey {
        case id
        case summary
        case primary
        case backgroundColor
    }
}

struct CalendarListResponse: Codable, Sendable {
    let items: [CalendarInfo]
}
