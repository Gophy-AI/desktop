import Foundation
import os.log

private let mixerLogger = Logger(subsystem: "com.gophy.app", category: "AudioMixer")

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

        mixerLogger.info("AudioMixer starting...")

        return AsyncStream { continuation in
            Task {
                mixerLogger.info("AudioMixer task started, waiting for audio streams")

                await withTaskGroup(of: Void.self) { group in
                    // Process microphone stream
                    group.addTask {
                        mixerLogger.info("Microphone stream task started")
                        var micChunkCount = 0
                        for await chunk in micStream {
                            micChunkCount += 1
                            let labeled = self.labelChunk(chunk, speaker: "You")
                            if micChunkCount <= 5 || micChunkCount % 10 == 0 {
                                mixerLogger.info("Mic chunk #\(micChunkCount, privacy: .public): \(chunk.samples.count, privacy: .public) samples")
                            }
                            continuation.yield(labeled)
                        }
                        mixerLogger.info("Microphone stream ended after \(micChunkCount, privacy: .public) chunks")
                    }

                    // Process system audio stream
                    group.addTask {
                        mixerLogger.info("System audio stream task started")
                        var sysChunkCount = 0
                        for await chunk in sysStream {
                            sysChunkCount += 1
                            let labeled = self.labelChunk(chunk, speaker: "Others")
                            if sysChunkCount <= 5 || sysChunkCount % 10 == 0 {
                                mixerLogger.info("System chunk #\(sysChunkCount, privacy: .public): \(chunk.samples.count, privacy: .public) samples")
                            }
                            continuation.yield(labeled)
                        }
                        mixerLogger.info("System audio stream ended after \(sysChunkCount, privacy: .public) chunks")
                    }

                    // Wait for both streams to complete
                    await group.waitForAll()
                    mixerLogger.info("Both audio streams completed, finishing mixer")
                    continuation.finish()
                }
            }
        }
    }

    private func labelChunk(_ chunk: AudioChunk, speaker: String) -> LabeledAudioChunk {
        return LabeledAudioChunk(
            samples: chunk.samples,
            timestamp: chunk.timestamp,
            speaker: speaker
        )
    }
}
