import Foundation

/// Transcript segment with speaker label for multi-speaker transcription
public struct TranscriptSegment: Sendable, Identifiable {
    public let id: UUID
    public let text: String
    public let startTime: TimeInterval
    public let endTime: TimeInterval
    public let speaker: String
    public let detectedLanguage: AppLanguage?

    public init(text: String, startTime: TimeInterval, endTime: TimeInterval, speaker: String, detectedLanguage: AppLanguage? = nil) {
        self.id = UUID()
        self.text = text
        self.startTime = startTime
        self.endTime = endTime
        self.speaker = speaker
        self.detectedLanguage = detectedLanguage
    }
}
