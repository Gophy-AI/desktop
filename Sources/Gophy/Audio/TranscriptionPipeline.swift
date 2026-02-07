import Foundation
import os.log

private let pipelineLogger = Logger(subsystem: "com.gophy.app", category: "TranscriptionPipeline")

/// Protocol for transcription in pipeline to enable testability
public protocol PipelineTranscriptionProtocol: Sendable {
    func transcribe(audioArray: [Float], sampleRate: Int, language: String?) async throws -> [TranscriptionSegment]
}

/// Real transcription engine conformance
extension TranscriptionEngine: PipelineTranscriptionProtocol {}

/// Real-time streaming transcription pipeline
///
/// Connects AudioMixer -> VADFilter -> TranscriptionEngine (or STTProvider)
/// Accumulates 2-5 seconds of audio per channel in sliding window
/// Runs mic and system audio transcription concurrently
/// Target latency: audio chunk to text under 2 seconds
public actor TranscriptionPipeline {
    private let transcriptionEngine: any PipelineTranscriptionProtocol
    private let sttProvider: (any STTProvider)?
    private let vadFilter: VADFilter
    private let languageDetector: LanguageDetector
    private var continuation: AsyncStream<TranscriptSegment>.Continuation?
    private var isRunning = false
    public var languageHint: String?

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

    /// Initialize with a PipelineTranscriptionProtocol (local engine)
    public init(transcriptionEngine: any PipelineTranscriptionProtocol, vadFilter: VADFilter = VADFilter(), languageDetector: LanguageDetector = LanguageDetector()) {
        self.transcriptionEngine = transcriptionEngine
        self.sttProvider = nil
        self.vadFilter = vadFilter
        self.languageDetector = languageDetector
    }

    /// Initialize with an STTProvider (cloud or local provider)
    public init(sttProvider: any STTProvider, transcriptionEngine: any PipelineTranscriptionProtocol, vadFilter: VADFilter = VADFilter(), languageDetector: LanguageDetector = LanguageDetector()) {
        self.transcriptionEngine = transcriptionEngine
        self.sttProvider = sttProvider
        self.vadFilter = vadFilter
        self.languageDetector = languageDetector
    }

    /// Start transcription pipeline
    /// - Parameter mixedStream: Stream of labeled audio chunks from AudioMixer
    /// - Returns: AsyncStream of transcript segments with speaker labels
    public nonisolated func start(mixedStream: AsyncStream<LabeledAudioChunk>) -> AsyncStream<TranscriptSegment> {
        pipelineLogger.info("TranscriptionPipeline.start() called")
        return AsyncStream { [weak self] continuation in
            guard let self = self else {
                pipelineLogger.error("TranscriptionPipeline.start(): self is nil")
                continuation.finish()
                return
            }

            pipelineLogger.info("TranscriptionPipeline: setting up continuation")
            Task {
                await self.setContinuation(continuation)
                pipelineLogger.info("TranscriptionPipeline: starting to process stream")
                await self.processStream(mixedStream)
            }
        }
    }

    private func setContinuation(_ continuation: AsyncStream<TranscriptSegment>.Continuation) {
        self.continuation = continuation
    }

    private func processStream(_ stream: AsyncStream<LabeledAudioChunk>) async {
        isRunning = true
        var chunkCount = 0
        var filteredCount = 0
        var passedCount = 0

        pipelineLogger.info("TranscriptionPipeline starting to process stream")

        for await chunk in stream {
            guard isRunning else {
                pipelineLogger.info("Pipeline stopped, breaking")
                break
            }

            chunkCount += 1
            if chunkCount <= 5 || chunkCount % 10 == 0 {
                pipelineLogger.info("Pipeline received chunk #\(chunkCount, privacy: .public) from [\(chunk.speaker, privacy: .public)]: \(chunk.samples.count, privacy: .public) samples")
            }

            // Apply VAD filter
            guard let filteredChunk = vadFilter.filter(chunk: chunk) else {
                filteredCount += 1
                if filteredCount <= 5 || filteredCount % 10 == 0 {
                    pipelineLogger.info("Pipeline: chunk filtered out (total filtered: \(filteredCount, privacy: .public))")
                }
                continue
            }

            passedCount += 1
            if passedCount <= 5 || passedCount % 10 == 0 {
                pipelineLogger.info("Pipeline: chunk passed VAD (total passed: \(passedCount, privacy: .public))")
            }

            // Add to speaker-specific buffer
            let speaker = filteredChunk.speaker
            if buffers[speaker] == nil {
                buffers[speaker] = AudioBuffer()
                pipelineLogger.info("Pipeline: created buffer for speaker [\(speaker, privacy: .public)]")
            }
            buffers[speaker]?.append(filteredChunk)

            // Check if we should transcribe this buffer
            if let buffer = buffers[speaker] {
                let duration = buffer.duration()
                if passedCount <= 5 || passedCount % 10 == 0 {
                    pipelineLogger.info("Pipeline: buffer [\(speaker, privacy: .public)] duration: \(String(format: "%.2f", duration), privacy: .public)s (min: \(self.minBufferDurationSeconds, privacy: .public)s)")
                }
                if duration >= minBufferDurationSeconds {
                    pipelineLogger.info("Pipeline: buffer ready, transcribing [\(speaker, privacy: .public)]...")
                    await transcribeBuffer(speaker: speaker)
                }
            }
        }

        pipelineLogger.info("Pipeline stream ended. Total: \(chunkCount, privacy: .public) chunks, \(passedCount, privacy: .public) passed, \(filteredCount, privacy: .public) filtered")

        // Flush all buffers on stream end
        await flushAllBuffers()
        continuation?.finish()
    }

    private func transcribeBuffer(speaker: String) async {
        guard var buffer = buffers[speaker], !buffer.samples.isEmpty else {
            pipelineLogger.warning("transcribeBuffer called but buffer is empty for [\(speaker, privacy: .public)]")
            return
        }

        let audioArray = buffer.samples
        let startTime = buffer.startTime
        let endTime = buffer.lastChunkTime
        let duration = buffer.duration()

        pipelineLogger.info("Transcribing buffer for [\(speaker, privacy: .public)]: \(audioArray.count, privacy: .public) samples (\(String(format: "%.2f", duration), privacy: .public)s)")

        // Clear buffer for next accumulation
        buffer.clear()
        buffers[speaker] = buffer

        // Transcribe asynchronously via STTProvider or local engine
        do {
            let segments: [TranscriptionSegment]
            if let provider = sttProvider {
                pipelineLogger.info("Calling STTProvider.transcribe...")
                let wavData = convertFloat32ToWAVData(samples: audioArray, sampleRate: 16000)
                segments = try await provider.transcribe(audioData: wavData, format: .wav)
            } else {
                pipelineLogger.info("Calling transcriptionEngine.transcribe...")
                segments = try await transcriptionEngine.transcribe(audioArray: audioArray, sampleRate: 16000, language: languageHint)
            }
            pipelineLogger.info("Transcription returned \(segments.count, privacy: .public) segments")

            // Convert to transcript segments with speaker labels and language detection
            for segment in segments {
                pipelineLogger.info("Segment: \"\(segment.text, privacy: .public)\" [\(String(format: "%.2f", segment.startTime), privacy: .public) - \(String(format: "%.2f", segment.endTime), privacy: .public)]")
                let detected = languageDetector.detect(text: segment.text)
                let transcriptSegment = TranscriptSegment(
                    text: segment.text,
                    startTime: startTime + segment.startTime,
                    endTime: startTime + segment.endTime,
                    speaker: speaker,
                    detectedLanguage: detected
                )
                continuation?.yield(transcriptSegment)
                pipelineLogger.info("Yielded transcript segment to continuation")
            }
        } catch {
            pipelineLogger.error("Transcription failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func flushAllBuffers() async {
        for speaker in buffers.keys {
            await transcribeBuffer(speaker: speaker)
        }
    }

    public func setLanguageHint(_ hint: String?) {
        self.languageHint = hint
    }

    /// Stop pipeline and flush buffered audio
    public func stop() async {
        isRunning = false
        await flushAllBuffers()
        continuation?.finish()
        continuation = nil
    }

    /// Convert Float32 audio samples to WAV format Data for cloud STT
    private func convertFloat32ToWAVData(samples: [Float], sampleRate: Int) -> Data {
        let numChannels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let byteRate = UInt32(sampleRate) * UInt32(numChannels) * UInt32(bitsPerSample / 8)
        let blockAlign = numChannels * (bitsPerSample / 8)
        let dataSize = UInt32(samples.count * 2)
        let fileSize = 36 + dataSize

        var data = Data()

        // RIFF header
        data.append(contentsOf: [0x52, 0x49, 0x46, 0x46]) // "RIFF"
        data.append(contentsOf: withUnsafeBytes(of: fileSize.littleEndian) { Array($0) })
        data.append(contentsOf: [0x57, 0x41, 0x56, 0x45]) // "WAVE"

        // fmt subchunk
        data.append(contentsOf: [0x66, 0x6D, 0x74, 0x20]) // "fmt "
        data.append(contentsOf: withUnsafeBytes(of: UInt32(16).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Array($0) }) // PCM
        data.append(contentsOf: withUnsafeBytes(of: numChannels.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt32(sampleRate).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: byteRate.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: blockAlign.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: bitsPerSample.littleEndian) { Array($0) })

        // data subchunk
        data.append(contentsOf: [0x64, 0x61, 0x74, 0x61]) // "data"
        data.append(contentsOf: withUnsafeBytes(of: dataSize.littleEndian) { Array($0) })

        // Convert float32 to int16
        for sample in samples {
            let clamped = max(-1.0, min(1.0, sample))
            let int16Value = Int16(clamped * Float(Int16.max))
            data.append(contentsOf: withUnsafeBytes(of: int16Value.littleEndian) { Array($0) })
        }

        return data
    }
}
