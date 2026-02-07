import AVFoundation
import Foundation
import os.log

private let diarizationLogger = Logger(subsystem: "com.gophy.app", category: "SpeakerDiarization")

/// Protocol for the diarization backend to enable testability
public protocol DiarizationBackend: Sendable {
    func process(samples: [Float], sampleRate: Int) async throws -> [SpeakerSegment]
    var isModelAvailable: Bool { get }
}

/// Service for offline speaker diarization of audio recordings.
/// Wraps FluidAudio's OfflineDiarizerManager for on-device speaker diarization.
public actor SpeakerDiarizationService {
    private let backend: any DiarizationBackend
    private var cachedResult: DiarizationResult?

    public var isAvailable: Bool {
        backend.isModelAvailable
    }

    public init(backend: any DiarizationBackend) {
        self.backend = backend
    }

    /// Diarize audio from a file URL
    public func diarize(audioURL: URL) async throws -> DiarizationResult {
        diarizationLogger.info("Starting diarization for file: \(audioURL.lastPathComponent, privacy: .public)")

        let audioFile = try AVAudioFileReader.readSamples(from: audioURL)
        let result = try await diarize(samples: audioFile.samples, sampleRate: audioFile.sampleRate)

        diarizationLogger.info("Diarization complete: \(result.speakerCount, privacy: .public) speakers, \(result.segments.count, privacy: .public) segments")
        return result
    }

    /// Diarize audio from raw samples
    public func diarize(samples: [Float], sampleRate: Int) async throws -> DiarizationResult {
        guard !samples.isEmpty else {
            let emptyResult = DiarizationResult(segments: [], speakerCount: 0)
            cachedResult = emptyResult
            return emptyResult
        }

        let speakerSegments = try await backend.process(samples: samples, sampleRate: sampleRate)

        let uniqueSpeakers = Set(speakerSegments.map { $0.speakerLabel })
        let result = DiarizationResult(
            segments: speakerSegments,
            speakerCount: uniqueSpeakers.count
        )

        cachedResult = result
        return result
    }

    /// Look up speaker label at a given timestamp from the cached result
    public func speakerLabelAt(time: TimeInterval) -> String? {
        cachedResult?.speakerLabelAt(time: time)
    }

    /// Rename a speaker in the cached result
    public func renameSpeaker(from oldLabel: String, to newLabel: String) {
        cachedResult?.renameSpeaker(from: oldLabel, to: newLabel)
    }
}

// MARK: - Audio File Reader Helper

enum AVAudioFileReader {
    struct AudioSamples {
        let samples: [Float]
        let sampleRate: Int
    }

    static func readSamples(from url: URL) throws -> AudioSamples {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let frameCount = AVAudioFrameCount(file.length)

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw DiarizationError.audioReadFailed("Could not create PCM buffer")
        }

        try file.read(into: buffer)

        guard let channelData = buffer.floatChannelData else {
            throw DiarizationError.audioReadFailed("No float channel data available")
        }

        let frameLength = Int(buffer.frameLength)
        let channelCount = Int(format.channelCount)

        // Convert to mono if needed
        var samples: [Float]
        if channelCount > 1 {
            samples = [Float](repeating: 0, count: frameLength)
            for frame in 0..<frameLength {
                var sum: Float = 0
                for ch in 0..<channelCount {
                    sum += channelData[ch][frame]
                }
                samples[frame] = sum / Float(channelCount)
            }
        } else {
            samples = Array(UnsafeBufferPointer(start: channelData[0], count: frameLength))
        }

        return AudioSamples(samples: samples, sampleRate: Int(format.sampleRate))
    }
}

// MARK: - Errors

public enum DiarizationError: Error, LocalizedError, Sendable {
    case audioReadFailed(String)
    case diarizationFailed(String)
    case modelNotAvailable

    public var errorDescription: String? {
        switch self {
        case .audioReadFailed(let reason):
            return "Failed to read audio file: \(reason)"
        case .diarizationFailed(let reason):
            return "Diarization failed: \(reason)"
        case .modelNotAvailable:
            return "Diarization model is not available"
        }
    }
}
