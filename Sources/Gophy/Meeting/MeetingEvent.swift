import Foundation

public enum MeetingStatus: String, Sendable, Codable {
    case idle
    case starting
    case active
    case paused
    case stopping
    case completed
}

public enum MeetingEvent: Sendable {
    case transcriptSegment(TranscriptSegment)
    case suggestion(String)
    case statusChange(MeetingStatus)
    case playbackProgress(currentTime: TimeInterval, duration: TimeInterval)
    case error(Error)
}

extension MeetingEvent {
    public struct ErrorWrapper: Error, Sendable {
        public let underlyingError: String

        public init(_ error: Error) {
            self.underlyingError = "\(error)"
        }
    }
}
