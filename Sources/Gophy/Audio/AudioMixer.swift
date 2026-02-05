import Foundation

/// Mixes audio from microphone and system audio into labeled streams
///
/// Does NOT mix audio into a single waveform. Instead, labels each chunk
/// with speaker identification and aligns timestamps using monotonic clock.
public final class AudioMixer: Sendable {
    private let microphoneStream: AsyncStream<AudioChunk>
    private let systemAudioStream: AsyncStream<AudioChunk>

    public init(
        microphoneStream: AsyncStream<AudioChunk>,
        systemAudioStream: AsyncStream<AudioChunk>
    ) {
        self.microphoneStream = microphoneStream
        self.systemAudioStream = systemAudioStream
    }

    /// Start mixing audio from both sources
    /// - Returns: AsyncStream of LabeledAudioChunk with speaker labels
    public func start() -> AsyncStream<LabeledAudioChunk> {
        let micStream = microphoneStream
        let sysStream = systemAudioStream

        return AsyncStream { continuation in
            Task {
                await withTaskGroup(of: Void.self) { group in
                    // Process microphone stream
                    group.addTask {
                        for await chunk in micStream {
                            let labeled = self.labelChunk(chunk, speaker: "You")
                            continuation.yield(labeled)
                        }
                    }

                    // Process system audio stream
                    group.addTask {
                        for await chunk in sysStream {
                            let labeled = self.labelChunk(chunk, speaker: "Others")
                            continuation.yield(labeled)
                        }
                    }

                    // Wait for both streams to complete
                    await group.waitForAll()
                    continuation.finish()
                }
            }
        }
    }

    private func labelChunk(_ chunk: AudioChunk, speaker: String) -> LabeledAudioChunk {
        // Use monotonic clock for timestamp alignment
        let monotonicTimestamp = ProcessInfo.processInfo.systemUptime

        return LabeledAudioChunk(
            samples: chunk.samples,
            timestamp: monotonicTimestamp,
            speaker: speaker
        )
    }
}
