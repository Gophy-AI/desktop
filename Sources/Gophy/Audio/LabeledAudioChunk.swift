import Foundation

/// Audio chunk with speaker label for multi-speaker transcription
public struct LabeledAudioChunk: Sendable {
    /// Raw audio samples (16kHz mono float32)
    public let samples: [Float]

    /// Timestamp in seconds since audio capture start (using monotonic clock)
    public let timestamp: TimeInterval

    /// Speaker label: "You" for microphone, "Others" for system audio
    public let speaker: String

    public init(samples: [Float], timestamp: TimeInterval, speaker: String) {
        self.samples = samples
        self.timestamp = timestamp
        self.speaker = speaker
    }
}
