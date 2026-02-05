import Foundation

public struct TranscriptionSegment: Sendable, Identifiable {
    public let id: UUID
    public let text: String
    public let startTime: TimeInterval
    public let endTime: TimeInterval

    public init(text: String, startTime: TimeInterval, endTime: TimeInterval) {
        self.id = UUID()
        self.text = text
        self.startTime = startTime
        self.endTime = endTime
    }
}
