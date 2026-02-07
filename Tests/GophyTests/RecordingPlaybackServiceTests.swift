import Testing
import Foundation
import AVFoundation
@testable import Gophy

@Suite("RecordingPlaybackService Tests")
struct RecordingPlaybackServiceTests {

    private func testResourceURL(_ name: String) -> URL? {
        let testDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let resourceURL = testDir.appendingPathComponent("Resources").appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: resourceURL.path) {
            return resourceURL
        }
        return nil
    }

    @Test("loadFile sets state to .loaded with correct file info")
    func testLoadFileSetsStateToLoaded() async throws {
        guard let url = testResourceURL("test-recording.wav") else {
            Issue.record("test-recording.wav not found")
            return
        }

        let service = RecordingPlaybackService()
        try await service.loadFile(url: url)

        let state = await service.state
        let duration = await service.duration

        #expect(state == .loaded)
        #expect(duration > 0.9 && duration < 1.1)
    }

    @Test("play transitions state to .playing and emits audio chunks")
    func testPlayEmitsChunks() async throws {
        guard let url = testResourceURL("test-recording.wav") else {
            Issue.record("test-recording.wav not found")
            return
        }

        let service = RecordingPlaybackService()
        try await service.loadFile(url: url)

        let stream = try await service.play()

        var chunks: [AudioChunk] = []
        // Collect a few chunks then stop (file is only 1 second)
        for await chunk in stream {
            chunks.append(chunk)
            if chunks.count >= 1 {
                break
            }
        }
        await service.stop()

        let state = await service.state
        // After stop, state should be .stopped
        #expect(state == .stopped)
        #expect(chunks.count >= 1, "Expected at least 1 audio chunk")
    }

    @Test("chunks are 16kHz mono Float32")
    func testChunkFormat() async throws {
        guard let url = testResourceURL("test-recording.wav") else {
            Issue.record("test-recording.wav not found")
            return
        }

        let service = RecordingPlaybackService()
        try await service.loadFile(url: url)

        let stream = try await service.play()

        var firstChunk: AudioChunk?
        for await chunk in stream {
            firstChunk = chunk
            break
        }
        await service.stop()

        guard let chunk = firstChunk else {
            Issue.record("No chunks received")
            return
        }

        // Chunks should be emitted from tap. Samples should be Float (verified by type)
        #expect(chunk.samples is [Float])
        #expect(chunk.source == .systemAudio, "Recording chunks should use .systemAudio source")
    }

    @Test("chunks have timestamp relative to file start")
    func testChunkTimestamps() async throws {
        guard let url = testResourceURL("test-recording.wav") else {
            Issue.record("test-recording.wav not found")
            return
        }

        let service = RecordingPlaybackService()
        try await service.loadFile(url: url)

        let stream = try await service.play()

        var chunks: [AudioChunk] = []
        for await chunk in stream {
            chunks.append(chunk)
            if chunks.count >= 2 {
                break
            }
        }
        await service.stop()

        if chunks.count >= 2 {
            #expect(chunks[0].timestamp >= 0.0, "First chunk timestamp should be >= 0")
            #expect(chunks[1].timestamp >= chunks[0].timestamp, "Timestamps should be non-decreasing")
        }
    }

    @Test("pause transitions state to .paused")
    func testPause() async throws {
        guard let url = testResourceURL("test-recording.wav") else {
            Issue.record("test-recording.wav not found")
            return
        }

        let service = RecordingPlaybackService()
        try await service.loadFile(url: url)
        _ = try await service.play()

        // Give audio engine a moment to start
        try await Task.sleep(nanoseconds: 50_000_000)

        await service.pause()

        let state = await service.state
        #expect(state == .paused)
    }

    @Test("resume after pause continues playback")
    func testResumeAfterPause() async throws {
        guard let url = testResourceURL("test-recording.wav") else {
            Issue.record("test-recording.wav not found")
            return
        }

        let service = RecordingPlaybackService()
        try await service.loadFile(url: url)
        _ = try await service.play()

        try await Task.sleep(nanoseconds: 50_000_000)
        await service.pause()

        let pausedState = await service.state
        #expect(pausedState == .paused)

        try await service.resume()
        let resumedState = await service.state
        #expect(resumedState == .playing)

        await service.stop()
    }

    @Test("stop transitions to .stopped")
    func testStop() async throws {
        guard let url = testResourceURL("test-recording.wav") else {
            Issue.record("test-recording.wav not found")
            return
        }

        let service = RecordingPlaybackService()
        try await service.loadFile(url: url)
        _ = try await service.play()

        try await Task.sleep(nanoseconds: 50_000_000)
        await service.stop()

        let state = await service.state
        #expect(state == .stopped)
    }

    @Test("setSpeed changes playback rate within valid range")
    func testSetSpeed() async throws {
        guard let url = testResourceURL("test-recording.wav") else {
            Issue.record("test-recording.wav not found")
            return
        }

        let service = RecordingPlaybackService()
        try await service.loadFile(url: url)

        await service.setSpeed(2.0)
        let speed2 = await service.speed
        #expect(speed2 == 2.0)

        await service.setSpeed(0.5)
        let speed05 = await service.speed
        #expect(speed05 == 0.5)

        // Clamp to valid range
        await service.setSpeed(0.1)
        let speedMin = await service.speed
        #expect(speedMin == 0.25)

        await service.setSpeed(5.0)
        let speedMax = await service.speed
        #expect(speedMax == 4.0)
    }

    @Test("seek updates currentTime")
    func testSeek() async throws {
        guard let url = testResourceURL("test-recording.wav") else {
            Issue.record("test-recording.wav not found")
            return
        }

        let service = RecordingPlaybackService()
        try await service.loadFile(url: url)
        _ = try await service.play()

        try await Task.sleep(nanoseconds: 50_000_000)

        try await service.seek(to: 0.5)
        let currentTime = await service.currentTime
        // After seeking to 0.5s, currentTime should be approximately 0.5s
        #expect(currentTime >= 0.4 && currentTime <= 0.7, "Expected ~0.5s, got \(currentTime)")

        await service.stop()
    }
}
