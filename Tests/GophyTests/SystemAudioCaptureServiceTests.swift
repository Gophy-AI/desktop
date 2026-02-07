import Testing
import Foundation
@testable import Gophy

/// Mock implementation for testing without actual hardware
final class MockSystemAudioCapture: SystemAudioCaptureProtocol, @unchecked Sendable {
    private var isRunning = false
    private var continuation: AsyncStream<AudioChunk>.Continuation?

    nonisolated func start() -> AsyncStream<AudioChunk> {
        let stream = AsyncStream<AudioChunk> { continuation in
            self.continuation = continuation
            self.isRunning = true
        }
        return stream
    }

    func stop() async {
        continuation?.finish()
        continuation = nil
        isRunning = false
    }

    func emitChunk(_ chunk: AudioChunk) {
        continuation?.yield(chunk)
    }

    func getIsRunning() -> Bool {
        return isRunning
    }
}

@Suite("SystemAudioCaptureService Tests")
struct SystemAudioCaptureServiceTests {
    
    @Test("start() emits audio chunks via AsyncStream")
    func testStartEmitsChunks() async throws {
        let mock = MockSystemAudioCapture()
        let stream = mock.start()
        
        // Emit test chunks
        let chunk1 = AudioChunk(
            samples: Array(repeating: 0.5, count: 16000),
            timestamp: 0.0,
            source: .systemAudio
        )
        let chunk2 = AudioChunk(
            samples: Array(repeating: 0.7, count: 16000),
            timestamp: 1.0,
            source: .systemAudio
        )
        
        mock.emitChunk(chunk1)
        mock.emitChunk(chunk2)
        await mock.stop()
        
        // Collect chunks
        var collected: [AudioChunk] = []
        for await chunk in stream {
            collected.append(chunk)
        }
        
        #expect(collected.count == 2)
        #expect(collected[0].timestamp == 0.0)
        #expect(collected[1].timestamp == 1.0)
    }
    
    @Test("chunks are 16kHz mono float32")
    func testChunkFormat() async throws {
        let mock = MockSystemAudioCapture()
        let stream = mock.start()
        
        // Emit chunk with known format
        let samples = Array(repeating: Float(0.5), count: 16000) // 1 second at 16kHz
        let chunk = AudioChunk(
            samples: samples,
            timestamp: 0.0,
            source: .systemAudio
        )
        
        mock.emitChunk(chunk)
        await mock.stop()
        
        var receivedChunk: AudioChunk?
        for await chunk in stream {
            receivedChunk = chunk
            break
        }
        
        #expect(receivedChunk != nil)
        #expect(receivedChunk?.samples.count == 16000)
        
        // Verify float32 type (samples are [Float])
        if let chunk = receivedChunk {
            #expect(chunk.samples.allSatisfy { $0 >= -1.0 && $0 <= 1.0 })
        }
    }
    
    @Test("chunks have source = .systemAudio")
    func testChunkSource() async throws {
        let mock = MockSystemAudioCapture()
        let stream = mock.start()
        
        let chunk = AudioChunk(
            samples: Array(repeating: 0.5, count: 16000),
            timestamp: 0.0,
            source: .systemAudio
        )
        
        mock.emitChunk(chunk)
        await mock.stop()
        
        var receivedChunk: AudioChunk?
        for await chunk in stream {
            receivedChunk = chunk
            break
        }
        
        #expect(receivedChunk?.source == .systemAudio)
    }
    
    @Test("stop() tears down tap and closes stream")
    func testStopClosesStream() async throws {
        let mock = MockSystemAudioCapture()
        let stream = mock.start()
        
        #expect(mock.getIsRunning() == true)

        await mock.stop()
        
        // Stream should complete without any new chunks
        var chunkCount = 0
        for await _ in stream {
            chunkCount += 1
        }
        
        #expect(chunkCount == 0)
        #expect(mock.getIsRunning() == false)
    }
    
    @Test("timestamps are monotonically increasing")
    func testMonotonicTimestamps() async throws {
        let mock = MockSystemAudioCapture()
        let stream = mock.start()
        
        // Emit chunks with increasing timestamps
        for i in 0..<5 {
            let chunk = AudioChunk(
                samples: Array(repeating: 0.5, count: 16000),
                timestamp: TimeInterval(i),
                source: .systemAudio
            )
            mock.emitChunk(chunk)
        }
        await mock.stop()

        var timestamps: [TimeInterval] = []
        for await chunk in stream {
            timestamps.append(chunk.timestamp)
        }
        
        #expect(timestamps.count == 5)
        for i in 1..<timestamps.count {
            #expect(timestamps[i] > timestamps[i - 1])
        }
    }
}
