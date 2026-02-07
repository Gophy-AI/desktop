import Foundation

public enum LocalCalendarType: String, Sendable, Equatable {
    case local
    case calDAV
    case exchange
    case birthday
}

public struct LocalCalendar: Sendable, Equatable, Identifiable {
    public let identifier: String
    public let title: String
    public let type: LocalCalendarType
    public let source: String
    public let color: String

    public var id: String { identifier }

    public init(identifier: String, title: String, type: LocalCalendarType, source: String, color: String) {
        self.identifier = identifier
        self.title = title
        self.type = type
        self.source = source
        self.color = color
    }
}
