import Foundation
import Accelerate

/// Voice Activity Detection filter using energy-based RMS calculation
///
/// Filters out silent audio chunks based on RMS energy threshold.
/// Includes hold-open window to avoid cutting mid-word.
public final class VADFilter: Sendable {
    private let thresholdDB: Float
    private let holdOpenWindowSeconds: TimeInterval
    private let thresholdLinear: Float

    // Thread-safe state using locks
    private final class State: @unchecked Sendable {
        var lastSpeechTime: TimeInterval?
        let lock = NSLock()

        func getLastSpeechTime() -> TimeInterval? {
            lock.lock()
            defer { lock.unlock() }
            return lastSpeechTime
        }

        func setLastSpeechTime(_ time: TimeInterval?) {
            lock.lock()
            defer { lock.unlock() }
            lastSpeechTime = time
        }
    }

    private let state = State()

    /// Initialize VAD filter
    /// - Parameters:
    ///   - thresholdDB: Energy threshold in decibels (default -40 dB)
    ///   - holdOpenWindowSeconds: Duration to keep passing audio after speech (default 0.3s)
    public init(thresholdDB: Float = -40, holdOpenWindowSeconds: TimeInterval = 0.3) {
        self.thresholdDB = thresholdDB
        self.holdOpenWindowSeconds = holdOpenWindowSeconds

        // Convert dB to linear scale: linear = 10^(dB/20)
        self.thresholdLinear = pow(10.0, thresholdDB / 20.0)
    }

    /// Filter audio chunk based on voice activity
    /// - Parameter chunk: Input audio chunk with samples
    /// - Returns: The same chunk if speech is detected, nil if silence
    public func filter(chunk: LabeledAudioChunk) -> LabeledAudioChunk? {
        let rms = calculateRMS(samples: chunk.samples)

        // Check if energy exceeds threshold
        let isSpeech = rms > thresholdLinear

        if isSpeech {
            // Speech detected, update last speech time
            state.setLastSpeechTime(chunk.timestamp)
            return chunk
        }

        // No speech detected, check hold-open window
        if let lastSpeechTime = state.getLastSpeechTime() {
            let timeSinceLastSpeech = chunk.timestamp - lastSpeechTime

            if timeSinceLastSpeech < holdOpenWindowSeconds {
                // Within hold-open window, pass through
                return chunk
            }
        }

        // Filter out silence
        return nil
    }

    /// Calculate RMS (Root Mean Square) energy using Accelerate framework
    /// - Parameter samples: Audio samples
    /// - Returns: RMS value
    private func calculateRMS(samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }

        var rms: Float = 0.0

        // Use vDSP for fast RMS calculation
        samples.withUnsafeBufferPointer { buffer in
            vDSP_rmsqv(buffer.baseAddress!, 1, &rms, vDSP_Length(samples.count))
        }

        return rms
    }
}
