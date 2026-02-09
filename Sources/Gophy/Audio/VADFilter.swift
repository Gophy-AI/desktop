import Foundation
import Accelerate
import os.log

private let vadLogger = Logger(subsystem: "com.gophy.app", category: "VADFilter")

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
        var chunkCount = 0
        var passedCount = 0
        var filteredCount = 0
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

        func incrementChunkCount() -> Int {
            lock.lock()
            defer { lock.unlock() }
            chunkCount += 1
            return chunkCount
        }

        func incrementPassedCount() -> Int {
            lock.lock()
            defer { lock.unlock() }
            passedCount += 1
            return passedCount
        }

        func incrementFilteredCount() -> Int {
            lock.lock()
            defer { lock.unlock() }
            filteredCount += 1
            return filteredCount
        }
    }

    private let state = State()

    /// Initialize VAD filter
    /// - Parameters:
    ///   - thresholdDB: Energy threshold in decibels (default -40 dB)
    ///   - holdOpenWindowSeconds: Duration to keep passing audio after speech (default 0.3s)
    public init(thresholdDB: Float = -50, holdOpenWindowSeconds: TimeInterval = 0.8) {
        self.thresholdDB = thresholdDB
        self.holdOpenWindowSeconds = holdOpenWindowSeconds

        // Convert dB to linear scale: linear = 10^(dB/20)
        self.thresholdLinear = pow(10.0, thresholdDB / 20.0)
    }

    /// Filter audio chunk based on voice activity
    /// - Parameter chunk: Input audio chunk with samples
    /// - Returns: The same chunk if speech is detected, nil if silence
    public func filter(chunk: LabeledAudioChunk) -> LabeledAudioChunk? {
        let chunkNum = state.incrementChunkCount()
        let rms = calculateRMS(samples: chunk.samples)
        let rmsDB = 20 * log10(max(rms, 1e-10))

        // Check if energy exceeds threshold
        let isSpeech = rms > thresholdLinear

        // Log every 10th chunk or first 5
        if chunkNum <= 5 || chunkNum % 10 == 0 {
            vadLogger.info("VAD chunk #\(chunkNum, privacy: .public) [\(chunk.speaker, privacy: .public)]: RMS=\(String(format: "%.6f", rms), privacy: .public) (\(String(format: "%.1f", rmsDB), privacy: .public) dB), threshold=\(String(format: "%.6f", self.thresholdLinear), privacy: .public) (\(self.thresholdDB, privacy: .public) dB), isSpeech=\(isSpeech, privacy: .public)")
        }

        if isSpeech {
            // Speech detected, update last speech time
            state.setLastSpeechTime(chunk.timestamp)
            let passedNum = state.incrementPassedCount()
            if passedNum <= 5 || passedNum % 10 == 0 {
                vadLogger.info("VAD PASSED chunk #\(chunkNum, privacy: .public) (total passed: \(passedNum, privacy: .public))")
            }
            return chunk
        }

        // No speech detected, check hold-open window
        if let lastSpeechTime = state.getLastSpeechTime() {
            let timeSinceLastSpeech = chunk.timestamp - lastSpeechTime

            if timeSinceLastSpeech < holdOpenWindowSeconds {
                // Within hold-open window, pass through
                let passedNum = state.incrementPassedCount()
                if passedNum <= 5 || passedNum % 10 == 0 {
                    vadLogger.info("VAD PASSED (hold-open) chunk #\(chunkNum, privacy: .public) (total passed: \(passedNum, privacy: .public))")
                }
                return chunk
            }
        }

        // Filter out silence
        let filteredNum = state.incrementFilteredCount()
        if filteredNum <= 5 || filteredNum % 10 == 0 {
            vadLogger.info("VAD FILTERED chunk #\(chunkNum, privacy: .public) (total filtered: \(filteredNum, privacy: .public))")
        }
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
