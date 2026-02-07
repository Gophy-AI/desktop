import Testing
import Foundation
@testable import Gophy

@Suite("LocalSTTProvider Tests")
struct LocalSTTProviderTests {

    @Test("Conforms to STTProvider protocol")
    func testProtocolConformance() async {
        let mockEngine = StubTranscriptionEngine()
        let provider: any STTProvider = LocalSTTProvider(engine: mockEngine)
        _ = provider
    }

    @Test("Transcribe returns segments from engine")
    func testTranscribe() async throws {
        let mockEngine = StubTranscriptionEngine()
        mockEngine.simulateLoaded = true
        mockEngine.segmentsToReturn = [
            TranscriptionSegment(text: "Hello world", startTime: 0.0, endTime: 1.5),
            TranscriptionSegment(text: "How are you", startTime: 1.5, endTime: 3.0)
        ]

        let provider = LocalSTTProvider(engine: mockEngine)

        // Create minimal WAV data (44 byte header + some audio data)
        let wavData = createMinimalWAVData(sampleCount: 16000)
        let segments = try await provider.transcribe(audioData: wavData, format: .wav)

        #expect(segments.count == 2)
        #expect(segments[0].text == "Hello world")
        #expect(segments[1].text == "How are you")
    }

    @Test("Unloaded engine throws ProviderError.notConfigured")
    func testUnloadedEngineThrows() async {
        let mockEngine = StubTranscriptionEngine()
        mockEngine.simulateLoaded = false

        let provider = LocalSTTProvider(engine: mockEngine)
        let wavData = createMinimalWAVData(sampleCount: 16000)

        do {
            _ = try await provider.transcribe(audioData: wavData, format: .wav)
            Issue.record("Expected error to be thrown")
        } catch let error as ProviderError {
            if case .notConfigured = error {
                // Expected
            } else {
                Issue.record("Expected ProviderError.notConfigured, got \(error)")
            }
        } catch {
            Issue.record("Expected ProviderError, got \(error)")
        }
    }

    private func createMinimalWAVData(sampleCount: Int) -> Data {
        var data = Data()
        // RIFF header
        let dataSize = UInt32(sampleCount * 2) // 16-bit samples
        let fileSize = UInt32(36 + dataSize)

        data.append(contentsOf: "RIFF".utf8)
        data.append(contentsOf: withUnsafeBytes(of: fileSize.littleEndian) { Array($0) })
        data.append(contentsOf: "WAVE".utf8)

        // fmt chunk
        data.append(contentsOf: "fmt ".utf8)
        data.append(contentsOf: withUnsafeBytes(of: UInt32(16).littleEndian) { Array($0) }) // chunk size
        data.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Array($0) })  // PCM
        data.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Array($0) })  // mono
        data.append(contentsOf: withUnsafeBytes(of: UInt32(16000).littleEndian) { Array($0) }) // sample rate
        data.append(contentsOf: withUnsafeBytes(of: UInt32(32000).littleEndian) { Array($0) }) // byte rate
        data.append(contentsOf: withUnsafeBytes(of: UInt16(2).littleEndian) { Array($0) })  // block align
        data.append(contentsOf: withUnsafeBytes(of: UInt16(16).littleEndian) { Array($0) }) // bits per sample

        // data chunk
        data.append(contentsOf: "data".utf8)
        data.append(contentsOf: withUnsafeBytes(of: dataSize.littleEndian) { Array($0) })
        // Silence
        data.append(Data(count: Int(dataSize)))

        return data
    }
}

final class StubTranscriptionEngine: TranscriptionCapable, @unchecked Sendable {
    var loadCalled = false
    var simulateLoaded = false
    var segmentsToReturn: [TranscriptionSegment] = []

    var isLoaded: Bool { simulateLoaded }

    func load() async throws {
        loadCalled = true
        simulateLoaded = true
    }

    func unload() {
        simulateLoaded = false
    }

    func transcribe(audioArray: [Float], sampleRate: Int, language: String?) async throws -> [TranscriptionSegment] {
        guard simulateLoaded else {
            throw TranscriptionError.modelNotLoaded
        }
        return segmentsToReturn
    }
}
