import Foundation

/// A segment of audio attributed to a specific speaker
public struct SpeakerSegment: Sendable, Equatable {
    public let speakerLabel: String
    public let startTime: TimeInterval
    public let endTime: TimeInterval

    public init(speakerLabel: String, startTime: TimeInterval, endTime: TimeInterval) {
        self.speakerLabel = speakerLabel
        self.startTime = startTime
        self.endTime = endTime
    }
}

/// Result of speaker diarization containing all speaker segments
public struct DiarizationResult: Sendable {
    public var segments: [SpeakerSegment]
    public let speakerCount: Int

    public init(segments: [SpeakerSegment], speakerCount: Int) {
        self.segments = segments
        self.speakerCount = speakerCount
    }

    /// Returns the speaker label for a given timestamp, or nil if no segment covers that time
    public func speakerLabelAt(time: TimeInterval) -> String? {
        for segment in segments {
            if time >= segment.startTime && time < segment.endTime {
                return segment.speakerLabel
            }
        }
        return nil
    }

    /// Rename all segments with the given speaker label
    public mutating func renameSpeaker(from oldLabel: String, to newLabel: String) {
        segments = segments.map { segment in
            if segment.speakerLabel == oldLabel {
                return SpeakerSegment(
                    speakerLabel: newLabel,
                    startTime: segment.startTime,
                    endTime: segment.endTime
                )
            }
            return segment
        }
    }
}
