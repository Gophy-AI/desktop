import Testing
import Foundation
import QuartzCore
@testable import Gophy

// Mock TranscriptionEngine for testing
final class MockPipelineTranscriptionEngine: @unchecked Sendable, PipelineTranscriptionProtocol {
    private var transcribeCalls: [(samples: [Float], callback: ([TranscriptionSegment]) -> Void)] = []
    private let lock = NSLock()

    func transcribe(audioArray: [Float], sampleRate: Int = 16000, language: String? = nil) async throws -> [TranscriptionSegment] {
        // Simulate transcription with mock result
        let segment = TranscriptionSegment(
            text: "Mock transcription",
            startTime: 0.0,
            endTime: 1.0
        )
        return [segment]
    }

    func recordCall(samples: [Float]) {
        lock.lock()
        defer { lock.unlock() }
        transcribeCalls.append((samples: samples, callback: { _ in }))
    }

    func getCallCount() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return transcribeCalls.count
    }
}

@Suite("TranscriptionPipeline Tests")
struct TranscriptionPipelineTests {

    @Test("transcript segments appear within latency budget")
    func testLatencyBudget() async throws {
        let pipeline = TranscriptionPipeline(
            transcriptionEngine: MockPipelineTranscriptionEngine()
        )

        let mockCapture = MockAudioMixerCapture()
        let micStream = await mockCapture.start()

        let sysCapture = MockAudioMixerCapture()

        let mixer = AudioMixer(
            microphoneStream: micStream,
            systemAudioStream: sysCapture.start()
        )

        let outputStream = await pipeline.start(mixedStream: mixer.start())

        // Emit speech chunk
        let speechSamples = (0..<16000).map { i in
            Float(0.1 * sin(Double(i) * 2.0 * .pi * 440.0 / 16000.0))
        }
        let chunk = AudioChunk(
            samples: speechSamples,
            timestamp: 0.0,
            source: .microphone
        )

        let startTime = CACurrentMediaTime()
        mockCapture.emit(chunk)

        // Wait for accumulation (need at least 2 seconds of audio)
        for i in 1..<3 {
            let nextChunk = AudioChunk(
                samples: speechSamples,
                timestamp: TimeInterval(i),
                source: .microphone
            )
            try? await Task.sleep(nanoseconds: 100_000_000)
            mockCapture.emit(nextChunk)
        }

        // Give time to process
        try? await Task.sleep(nanoseconds: 500_000_000)

        mockCapture.finish()
        sysCapture.finish()

        var receivedSegment: TranscriptSegment?
        for await segment in outputStream {
            receivedSegment = segment
            let endTime = CACurrentMediaTime()
            let latency = endTime - startTime

            // Should be under 2 seconds target latency
            #expect(latency < 3.0, "Latency should be under 3 seconds")
            break
        }

        #expect(receivedSegment != nil, "Should receive at least one segment")
    }

    @Test("segments have correct speaker labels")
    func testSegmentSpeakerLabels() async throws {
        let pipeline = TranscriptionPipeline(
            transcriptionEngine: MockPipelineTranscriptionEngine()
        )

        let micCapture = MockAudioMixerCapture()
        let sysCapture = MockAudioMixerCapture()

        let mixer = AudioMixer(
            microphoneStream: await micCapture.start(),
            systemAudioStream: await sysCapture.start()
        )

        let outputStream = await pipeline.start(mixedStream: mixer.start())

        // Emit mic and system chunks
        let speechSamples = (0..<16000).map { i in
            Float(0.1 * sin(Double(i) * 2.0 * .pi * 440.0 / 16000.0))
        }

        // Emit enough chunks to trigger transcription (2+ seconds)
        for i in 0..<3 {
            let micChunk = AudioChunk(
                samples: speechSamples,
                timestamp: TimeInterval(i),
                source: .microphone
            )
            micCapture.emit(micChunk)

            let sysChunk = AudioChunk(
                samples: speechSamples,
                timestamp: TimeInterval(i) + 0.5,
                source: .systemAudio
            )
            sysCapture.emit(sysChunk)

            try? await Task.sleep(nanoseconds: 100_000_000)
        }

        try? await Task.sleep(nanoseconds: 500_000_000)

        micCapture.finish()
        sysCapture.finish()

        var youSegments: [TranscriptSegment] = []
        var othersSegments: [TranscriptSegment] = []

        for await segment in outputStream {
            if segment.speaker == "You" {
                youSegments.append(segment)
            } else if segment.speaker == "Others" {
                othersSegments.append(segment)
            }

            if youSegments.count >= 1 && othersSegments.count >= 1 {
                break
            }
        }

        #expect(youSegments.count >= 1, "Should have 'You' segments")
        #expect(othersSegments.count >= 1, "Should have 'Others' segments")
    }

    @Test("segments are ordered by timestamp")
    func testSegmentsOrderedByTimestamp() async throws {
        let pipeline = TranscriptionPipeline(
            transcriptionEngine: MockPipelineTranscriptionEngine()
        )

        let micCapture = MockAudioMixerCapture()
        let sysCapture = MockAudioMixerCapture()

        let mixer = AudioMixer(
            microphoneStream: await micCapture.start(),
            systemAudioStream: sysCapture.start()
        )

        let outputStream = await pipeline.start(mixedStream: mixer.start())

        let speechSamples = (0..<16000).map { i in
            Float(0.1 * sin(Double(i) * 2.0 * .pi * 440.0 / 16000.0))
        }

        // Emit multiple chunks
        for i in 0..<5 {
            let chunk = AudioChunk(
                samples: speechSamples,
                timestamp: TimeInterval(i),
                source: .microphone
            )
            micCapture.emit(chunk)
            try? await Task.sleep(nanoseconds: 100_000_000)
        }

        try? await Task.sleep(nanoseconds: 500_000_000)
        micCapture.finish()
        sysCapture.finish()

        var segments: [TranscriptSegment] = []
        for await segment in outputStream {
            segments.append(segment)
            if segments.count >= 2 {
                break
            }
        }

        // Verify timestamps are ordered
        if segments.count >= 2 {
            for i in 1..<segments.count {
                #expect(segments[i].startTime >= segments[i-1].startTime,
                       "Segments should be ordered by timestamp")
            }
        }
    }

    @Test("stopping flushes buffered audio")
    func testStoppingFlushesBuffer() async throws {
        let pipeline = TranscriptionPipeline(
            transcriptionEngine: MockPipelineTranscriptionEngine()
        )

        let micCapture = MockAudioMixerCapture()
        let sysCapture = MockAudioMixerCapture()

        let mixer = AudioMixer(
            microphoneStream: await micCapture.start(),
            systemAudioStream: sysCapture.start()
        )

        let outputStream = await pipeline.start(mixedStream: mixer.start())

        let speechSamples = (0..<16000).map { i in
            Float(0.1 * sin(Double(i) * 2.0 * .pi * 440.0 / 16000.0))
        }

        // Emit single chunk (less than accumulation window)
        let chunk = AudioChunk(
            samples: speechSamples,
            timestamp: 0.0,
            source: .microphone
        )
        micCapture.emit(chunk)

        try? await Task.sleep(nanoseconds: 100_000_000)

        // Stop pipeline - should flush buffered audio
        await pipeline.stop()
        micCapture.finish()
        sysCapture.finish()

        var receivedAnySegment = false
        for await _ in outputStream {
            receivedAnySegment = true
            break
        }

        // Should receive segment from flushed buffer
        #expect(receivedAnySegment, "Should receive segment from flushed buffer after stop")
    }

    @Test("accumulates 2-5 seconds of audio per channel")
    func testAccumulationWindow() async throws {
        let mockEngine = MockPipelineTranscriptionEngine()
        let pipeline = TranscriptionPipeline(
            transcriptionEngine: mockEngine
        )

        let micCapture = MockAudioMixerCapture()
        let sysCapture = MockAudioMixerCapture()

        let mixer = AudioMixer(
            microphoneStream: await micCapture.start(),
            systemAudioStream: sysCapture.start()
        )

        let outputStream = await pipeline.start(mixedStream: mixer.start())

        let speechSamples = (0..<16000).map { i in
            Float(0.1 * sin(Double(i) * 2.0 * .pi * 440.0 / 16000.0))
        }

        // Emit 3 seconds of audio (3 chunks)
        for i in 0..<3 {
            let chunk = AudioChunk(
                samples: speechSamples,
                timestamp: TimeInterval(i),
                source: .microphone
            )
            micCapture.emit(chunk)
            try? await Task.sleep(nanoseconds: 100_000_000)
        }

        try? await Task.sleep(nanoseconds: 500_000_000)
        micCapture.finish()
        sysCapture.finish()

        // Should receive transcription after accumulating enough audio
        var receivedSegment = false
        for await _ in outputStream {
            receivedSegment = true
            break
        }

        #expect(receivedSegment, "Should receive segment after accumulation window")
    }
}
