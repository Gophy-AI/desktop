import Testing
import Foundation
@testable import Gophy

final class MockAudioMixerCapture: @unchecked Sendable {
    private let continuation: AsyncStream<AudioChunk>.Continuation
    private let stream: AsyncStream<AudioChunk>

    init() {
        var cont: AsyncStream<AudioChunk>.Continuation!
        self.stream = AsyncStream { continuation in
            cont = continuation
        }
        self.continuation = cont
    }

    func start() -> AsyncStream<AudioChunk> {
        return stream
    }

    func emit(_ chunk: AudioChunk) {
        continuation.yield(chunk)
    }

    func finish() {
        continuation.finish()
    }
}

@Suite("AudioMixer Tests")
struct AudioMixerTests {

    @Test("mic chunks labeled speaker = 'You'")
    func testMicChunksLabeledAsYou() async throws {
        let micCapture = MockAudioMixerCapture()
        let systemCapture = MockAudioMixerCapture()

        let mixer = AudioMixer(
            microphoneStream: await micCapture.start(),
            systemAudioStream: await systemCapture.start()
        )

        let outputStream = mixer.start()

        // Emit mic chunk
        let micChunk = AudioChunk(
            samples: Array(repeating: 0.5, count: 16000),
            timestamp: 0.0,
            source: .microphone
        )
        micCapture.emit(micChunk)

        // Give time to process
        try? await Task.sleep(nanoseconds: 50_000_000)

        micCapture.finish()
        systemCapture.finish()

        // Collect output
        var collected: [LabeledAudioChunk] = []
        for await chunk in outputStream {
            collected.append(chunk)
            if collected.count >= 1 {
                break
            }
        }

        #expect(collected.count == 1)
        #expect(collected[0].speaker == "You")
    }

    @Test("system chunks labeled speaker = 'Others'")
    func testSystemChunksLabeledAsOthers() async throws {
        let micCapture = MockAudioMixerCapture()
        let systemCapture = MockAudioMixerCapture()

        let mixer = AudioMixer(
            microphoneStream: await micCapture.start(),
            systemAudioStream: await systemCapture.start()
        )

        let outputStream = mixer.start()

        // Emit system chunk
        let systemChunk = AudioChunk(
            samples: Array(repeating: 0.7, count: 16000),
            timestamp: 0.0,
            source: .systemAudio
        )
        systemCapture.emit(systemChunk)

        // Give time to process
        try? await Task.sleep(nanoseconds: 50_000_000)

        micCapture.finish()
        systemCapture.finish()

        // Collect output
        var collected: [LabeledAudioChunk] = []
        for await chunk in outputStream {
            collected.append(chunk)
            if collected.count >= 1 {
                break
            }
        }

        #expect(collected.count == 1)
        #expect(collected[0].speaker == "Others")
    }

    @Test("timestamps from both sources are comparable within 50ms")
    func testTimestampsComparable() async throws {
        let micCapture = MockAudioMixerCapture()
        let systemCapture = MockAudioMixerCapture()

        let mixer = AudioMixer(
            microphoneStream: await micCapture.start(),
            systemAudioStream: await systemCapture.start()
        )

        let outputStream = mixer.start()

        // Emit chunks with similar timestamps
        let baseTime = ProcessInfo.processInfo.systemUptime
        let micChunk = AudioChunk(
            samples: Array(repeating: 0.5, count: 16000),
            timestamp: baseTime,
            source: .microphone
        )
        let systemChunk = AudioChunk(
            samples: Array(repeating: 0.7, count: 16000),
            timestamp: baseTime + 0.02, // 20ms difference
            source: .systemAudio
        )

        micCapture.emit(micChunk)
        systemCapture.emit(systemChunk)

        // Give time to process
        try? await Task.sleep(nanoseconds: 100_000_000)

        micCapture.finish()
        systemCapture.finish()

        // Collect output
        var collected: [LabeledAudioChunk] = []
        for await chunk in outputStream {
            collected.append(chunk)
            if collected.count >= 2 {
                break
            }
        }

        #expect(collected.count == 2)

        // Verify timestamps are comparable (within 50ms)
        if collected.count >= 2 {
            let timeDiff = abs(collected[0].timestamp - collected[1].timestamp)
            #expect(timeDiff <= 0.05) // 50ms tolerance
        }
    }

    @Test("if one source stops, other continues")
    func testOneSourceStopsOtherContinues() async throws {
        let micCapture = MockAudioMixerCapture()
        let systemCapture = MockAudioMixerCapture()

        let mixer = AudioMixer(
            microphoneStream: await micCapture.start(),
            systemAudioStream: await systemCapture.start()
        )

        let outputStream = mixer.start()

        // Emit mic chunk then stop mic
        let micChunk = AudioChunk(
            samples: Array(repeating: 0.5, count: 16000),
            timestamp: 0.0,
            source: .microphone
        )
        micCapture.emit(micChunk)
        try? await Task.sleep(nanoseconds: 50_000_000)
        micCapture.finish()

        // Continue emitting system chunks
        let systemChunk1 = AudioChunk(
            samples: Array(repeating: 0.7, count: 16000),
            timestamp: 0.1,
            source: .systemAudio
        )
        let systemChunk2 = AudioChunk(
            samples: Array(repeating: 0.8, count: 16000),
            timestamp: 0.2,
            source: .systemAudio
        )
        systemCapture.emit(systemChunk1)
        try? await Task.sleep(nanoseconds: 50_000_000)
        systemCapture.emit(systemChunk2)

        try? await Task.sleep(nanoseconds: 50_000_000)
        systemCapture.finish()

        // Collect output
        var collected: [LabeledAudioChunk] = []
        for await chunk in outputStream {
            collected.append(chunk)
        }

        // Should receive mic chunk + system chunks even after mic stopped
        #expect(collected.count >= 2)

        // Verify we got both speaker types
        let youChunks = collected.filter { $0.speaker == "You" }
        let othersChunks = collected.filter { $0.speaker == "Others" }

        #expect(youChunks.count >= 1)
        #expect(othersChunks.count >= 2)
    }

    @Test("chunks are kept separate, not mixed into single waveform")
    func testChunksKeptSeparate() async throws {
        let micCapture = MockAudioMixerCapture()
        let systemCapture = MockAudioMixerCapture()

        let mixer = AudioMixer(
            microphoneStream: await micCapture.start(),
            systemAudioStream: await systemCapture.start()
        )

        let outputStream = mixer.start()

        // Emit distinct chunks with different sample values
        let micChunk = AudioChunk(
            samples: Array(repeating: 0.5, count: 16000),
            timestamp: 0.0,
            source: .microphone
        )
        let systemChunk = AudioChunk(
            samples: Array(repeating: 0.9, count: 16000),
            timestamp: 0.0,
            source: .systemAudio
        )

        micCapture.emit(micChunk)
        systemCapture.emit(systemChunk)

        try? await Task.sleep(nanoseconds: 100_000_000)

        micCapture.finish()
        systemCapture.finish()

        // Collect output
        var collected: [LabeledAudioChunk] = []
        for await chunk in outputStream {
            collected.append(chunk)
            if collected.count >= 2 {
                break
            }
        }

        #expect(collected.count == 2)

        // Verify original sample values preserved (not averaged/mixed)
        let youChunk = collected.first { $0.speaker == "You" }
        let othersChunk = collected.first { $0.speaker == "Others" }

        #expect(youChunk != nil)
        #expect(othersChunk != nil)

        if let youChunk = youChunk {
            #expect(youChunk.samples[0] == 0.5)
        }

        if let othersChunk = othersChunk {
            #expect(othersChunk.samples[0] == 0.9)
        }
    }
}
