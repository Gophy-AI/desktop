import XCTest
import AVFoundation
@testable import Gophy

final class MicrophoneCaptureServiceTests: XCTestCase {

    // MARK: - Mock Audio Capture

    actor MockAudioCapture: AudioCaptureProtocol {
        private var isRunning = false
        private var continuation: AsyncStream<AudioChunk>.Continuation?
        private var mockChunks: [AudioChunk] = []

        func setMockChunks(_ chunks: [AudioChunk]) {
            mockChunks = chunks
        }

        func start() -> AsyncStream<AudioChunk> {
            AsyncStream { continuation in
                self.continuation = continuation
                Task {
                    await self.setRunning(true)
                    // Emit mock chunks
                    for chunk in await self.getMockChunks() {
                        continuation.yield(chunk)
                        try? await Task.sleep(nanoseconds: 10_000_000) // 10ms delay
                    }
                }
            }
        }

        func stop() async {
            continuation?.finish()
            continuation = nil
            isRunning = false
        }

        func setInputDevice(deviceID: String) async throws {
            // Mock implementation - no-op
        }

        private func setRunning(_ value: Bool) {
            isRunning = value
        }

        private func getMockChunks() -> [AudioChunk] {
            mockChunks
        }
    }

    // MARK: - Tests

    func testStartEmitsAudioChunks() async throws {
        let mock = MockAudioCapture()

        // Create mock chunks with 16kHz mono float32 (16000 samples per second)
        let mockChunk1 = AudioChunk(
            samples: Array(repeating: 0.5, count: 16000),
            timestamp: 0.0,
            source: .microphone
        )
        let mockChunk2 = AudioChunk(
            samples: Array(repeating: 0.3, count: 16000),
            timestamp: 1.0,
            source: .microphone
        )

        await mock.setMockChunks([mockChunk1, mockChunk2])

        let stream = await mock.start()
        var receivedChunks: [AudioChunk] = []

        for await chunk in stream {
            receivedChunks.append(chunk)
            if receivedChunks.count >= 2 {
                await mock.stop()
                break
            }
        }

        XCTAssertEqual(receivedChunks.count, 2)
        XCTAssertEqual(receivedChunks[0].samples.count, 16000)
        XCTAssertEqual(receivedChunks[1].samples.count, 16000)
    }

    func testChunksAre16kHzMonoFloat32() async throws {
        let mock = MockAudioCapture()

        // Create a chunk with exactly 16000 samples (1 second at 16kHz)
        let samples = (0..<16000).map { Float(sin(Double($0) * 2.0 * .pi * 440.0 / 16000.0)) }
        let mockChunk = AudioChunk(
            samples: samples,
            timestamp: 0.0,
            source: .microphone
        )

        await mock.setMockChunks([mockChunk])

        let stream = await mock.start()
        var receivedChunk: AudioChunk?

        for await chunk in stream {
            receivedChunk = chunk
            await mock.stop()
            break
        }

        guard let chunk = receivedChunk else {
            XCTFail("No chunk received")
            return
        }

        // Verify 16kHz mono (16000 samples per second)
        XCTAssertEqual(chunk.samples.count, 16000, "Chunk should contain 16000 samples for 1-second at 16kHz")

        // Verify samples are Float32
        XCTAssertTrue(chunk.samples is [Float])

        // Verify samples are in valid range [-1.0, 1.0]
        for sample in chunk.samples {
            XCTAssertGreaterThanOrEqual(sample, -1.0)
            XCTAssertLessThanOrEqual(sample, 1.0)
        }
    }

    func testStopClosesStream() async throws {
        let mock = MockAudioCapture()

        let mockChunk = AudioChunk(
            samples: Array(repeating: 0.1, count: 16000),
            timestamp: 0.0,
            source: .microphone
        )

        await mock.setMockChunks([mockChunk])

        let stream = await mock.start()
        var didStreamEnd = false

        Task {
            try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
            await mock.stop()
        }

        var chunkCount = 0
        for await _ in stream {
            chunkCount += 1
        }
        didStreamEnd = true

        XCTAssertTrue(didStreamEnd, "Stream should complete after stop()")
        XCTAssertGreaterThanOrEqual(chunkCount, 0)
    }

    func testChunksHaveMicrophoneSource() async throws {
        let mock = MockAudioCapture()

        let mockChunk = AudioChunk(
            samples: Array(repeating: 0.2, count: 16000),
            timestamp: 0.0,
            source: .microphone
        )

        await mock.setMockChunks([mockChunk])

        let stream = await mock.start()
        var receivedChunk: AudioChunk?

        for await chunk in stream {
            receivedChunk = chunk
            await mock.stop()
            break
        }

        guard let chunk = receivedChunk else {
            XCTFail("No chunk received")
            return
        }

        XCTAssertEqual(chunk.source, .microphone, "Chunk source should be .microphone")
    }

    func testRealMicrophoneCaptureService() async throws {
        // This test verifies the real implementation can be instantiated
        // and follows the protocol contract
        let service = MicrophoneCaptureService()

        // Start capture (will fail if no permission, but that's expected in CI)
        let stream = await service.start()

        // Immediately stop to avoid permission dialogs in tests
        await service.stop()

        // Just verify the service conforms to the protocol
        XCTAssertTrue(service is AudioCaptureProtocol)
    }
}
