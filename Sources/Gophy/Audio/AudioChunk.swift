import Foundation

/// Audio source type for speaker identification
public enum AudioSource: Sendable, Equatable {
    case microphone
    case systemAudio
}

/// Chunk of audio samples with metadata for transcription
public struct AudioChunk: Sendable {
    /// Raw audio samples (16kHz mono float32)
    public let samples: [Float]

    /// Timestamp in seconds since audio capture start
    public let timestamp: TimeInterval

    /// Source of the audio (mic = "You", system = "Others")
    public let source: AudioSource

    public init(samples: [Float], timestamp: TimeInterval, source: AudioSource) {
        self.samples = samples
        self.timestamp = timestamp
        self.source = source
    }
}
