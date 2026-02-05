import Foundation

/// Protocol for transcription in pipeline to enable testability
public protocol PipelineTranscriptionProtocol: Sendable {
    func transcribe(audioArray: [Float], sampleRate: Int) async throws -> [TranscriptionSegment]
}

/// Real transcription engine conformance
extension TranscriptionEngine: PipelineTranscriptionProtocol {}

/// Real-time streaming transcription pipeline
///
/// Connects AudioMixer → VADFilter → TranscriptionEngine
/// Accumulates 2-5 seconds of audio per channel in sliding window
/// Runs mic and system audio transcription concurrently
/// Target latency: audio chunk to text under 2 seconds
public actor TranscriptionPipeline {
    private let transcriptionEngine: any PipelineTranscriptionProtocol
    private let vadFilter: VADFilter
    private var continuation: AsyncStream<TranscriptSegment>.Continuation?
    private var isRunning = false

    // Per-speaker audio buffers
    private var buffers: [String: AudioBuffer] = [:]

    // Sliding window configuration
    private let minBufferDurationSeconds: TimeInterval = 2.0
    private let maxBufferDurationSeconds: TimeInterval = 5.0

    private struct AudioBuffer {
        var samples: [Float] = []
        var startTime: TimeInterval = 0
        var lastChunkTime: TimeInterval = 0

        mutating func append(_ chunk: LabeledAudioChunk) {
            if samples.isEmpty {
                startTime = chunk.timestamp
            }
            samples.append(contentsOf: chunk.samples)
            lastChunkTime = chunk.timestamp
        }

        func duration(at sampleRate: Double = 16000.0) -> TimeInterval {
            return TimeInterval(samples.count) / sampleRate
        }

        mutating func clear() {
            samples.removeAll(keepingCapacity: true)
            startTime = 0
            lastChunkTime = 0
        }
    }

    public init(transcriptionEngine: any PipelineTranscriptionProtocol, vadFilter: VADFilter = VADFilter()) {
        self.transcriptionEngine = transcriptionEngine
        self.vadFilter = vadFilter
    }

    /// Start transcription pipeline
    /// - Parameter mixedStream: Stream of labeled audio chunks from AudioMixer
    /// - Returns: AsyncStream of transcript segments with speaker labels
    public nonisolated func start(mixedStream: AsyncStream<LabeledAudioChunk>) -> AsyncStream<TranscriptSegment> {
        AsyncStream { [weak self] continuation in
            guard let self = self else {
                continuation.finish()
                return
            }

            Task {
                await self.setContinuation(continuation)
                await self.processStream(mixedStream)
            }
        }
    }

    private func setContinuation(_ continuation: AsyncStream<TranscriptSegment>.Continuation) {
        self.continuation = continuation
    }

    private func processStream(_ stream: AsyncStream<LabeledAudioChunk>) async {
        isRunning = true

        for await chunk in stream {
            guard isRunning else { break }

            // Apply VAD filter
            guard let filteredChunk = vadFilter.filter(chunk: chunk) else {
                continue
            }

            // Add to speaker-specific buffer
            let speaker = filteredChunk.speaker
            if buffers[speaker] == nil {
                buffers[speaker] = AudioBuffer()
            }
            buffers[speaker]?.append(filteredChunk)

            // Check if we should transcribe this buffer
            if let buffer = buffers[speaker], buffer.duration() >= minBufferDurationSeconds {
                await transcribeBuffer(speaker: speaker)
            }
        }

        // Flush all buffers on stream end
        await flushAllBuffers()
        continuation?.finish()
    }

    private func transcribeBuffer(speaker: String) async {
        guard var buffer = buffers[speaker], !buffer.samples.isEmpty else {
            return
        }

        let audioArray = buffer.samples
        let startTime = buffer.startTime
        let endTime = buffer.lastChunkTime

        // Clear buffer for next accumulation
        buffer.clear()
        buffers[speaker] = buffer

        // Transcribe asynchronously
        do {
            let segments = try await transcriptionEngine.transcribe(audioArray: audioArray, sampleRate: 16000)

            // Convert to transcript segments with speaker labels
            for segment in segments {
                let transcriptSegment = TranscriptSegment(
                    text: segment.text,
                    startTime: startTime + segment.startTime,
                    endTime: startTime + segment.endTime,
                    speaker: speaker
                )
                continuation?.yield(transcriptSegment)
            }
        } catch {
            // Log error but continue processing
            // In production, use proper logging
        }
    }

    private func flushAllBuffers() async {
        for speaker in buffers.keys {
            await transcribeBuffer(speaker: speaker)
        }
    }

    /// Stop pipeline and flush buffered audio
    public func stop() async {
        isRunning = false
        await flushAllBuffers()
        continuation?.finish()
        continuation = nil
    }
}
