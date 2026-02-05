import Testing
import Foundation
import QuartzCore
@testable import Gophy

@Suite("VADFilter Tests")
struct VADFilterTests {

    @Test("silent chunks (low RMS) filtered out")
    func testSilentChunksFilteredOut() async throws {
        let filter = VADFilter()

        // Create silent chunk (all zeros)
        let silentChunk = LabeledAudioChunk(
            samples: Array(repeating: 0.0, count: 16000),
            timestamp: 0.0,
            speaker: "You"
        )

        let result = filter.filter(chunk: silentChunk)

        #expect(result == nil, "Silent chunk should be filtered out")
    }

    @Test("speech chunks pass through unchanged")
    func testSpeechChunksPassThrough() async throws {
        let filter = VADFilter()

        // Create chunk with speech-level audio (440Hz sine wave at -20dB)
        let samples = (0..<16000).map { i in
            Float(0.1 * sin(Double(i) * 2.0 * .pi * 440.0 / 16000.0))
        }
        let speechChunk = LabeledAudioChunk(
            samples: samples,
            timestamp: 0.0,
            speaker: "You"
        )

        let result = filter.filter(chunk: speechChunk)

        #expect(result != nil, "Speech chunk should pass through")
        #expect(result?.samples == samples, "Samples should be unchanged")
        #expect(result?.timestamp == 0.0)
        #expect(result?.speaker == "You")
    }

    @Test("hold-open window keeps chunks between words")
    func testHoldOpenWindow() async throws {
        let filter = VADFilter()

        // First, pass a speech chunk to activate
        let speechSamples = (0..<16000).map { i in
            Float(0.1 * sin(Double(i) * 2.0 * .pi * 440.0 / 16000.0))
        }
        let speechChunk = LabeledAudioChunk(
            samples: speechSamples,
            timestamp: 0.0,
            speaker: "You"
        )
        let speechResult = filter.filter(chunk: speechChunk)
        #expect(speechResult != nil)

        // Now pass a silent chunk within hold-open window (< 300ms)
        let silentChunk = LabeledAudioChunk(
            samples: Array(repeating: 0.0, count: 16000),
            timestamp: 0.1, // 100ms later
            speaker: "You"
        )
        let silentResult = filter.filter(chunk: silentChunk)

        // Should pass through due to hold-open window
        #expect(silentResult != nil, "Silent chunk should pass through during hold-open window")
    }

    @Test("adjustable threshold changes sensitivity")
    func testAdjustableThreshold() async throws {
        // Test with high threshold (more permissive)
        let permissiveFilter = VADFilter(thresholdDB: -50)

        // Create very quiet chunk
        let quietSamples = Array(repeating: Float(0.001), count: 16000)
        let quietChunk = LabeledAudioChunk(
            samples: quietSamples,
            timestamp: 0.0,
            speaker: "You"
        )

        let permissiveResult = permissiveFilter.filter(chunk: quietChunk)
        #expect(permissiveResult != nil, "Quiet chunk should pass with permissive threshold")

        // Test with low threshold (more restrictive)
        let restrictiveFilter = VADFilter(thresholdDB: -20)

        let restrictiveResult = restrictiveFilter.filter(chunk: quietChunk)
        #expect(restrictiveResult == nil, "Quiet chunk should be filtered with restrictive threshold")
    }

    @Test("filter adds less than 1ms latency")
    func testLowLatency() async throws {
        let filter = VADFilter()

        let samples = (0..<16000).map { i in
            Float(0.1 * sin(Double(i) * 2.0 * .pi * 440.0 / 16000.0))
        }
        let chunk = LabeledAudioChunk(
            samples: samples,
            timestamp: 0.0,
            speaker: "You"
        )

        let startTime = CACurrentMediaTime()
        _ = filter.filter(chunk: chunk)
        let endTime = CACurrentMediaTime()

        let latency = endTime - startTime
        #expect(latency < 0.001, "Filter should add less than 1ms latency")
    }

    @Test("hold-open expires after 300ms of silence")
    func testHoldOpenExpires() async throws {
        let filter = VADFilter()

        // First, pass a speech chunk to activate
        let speechSamples = (0..<16000).map { i in
            Float(0.1 * sin(Double(i) * 2.0 * .pi * 440.0 / 16000.0))
        }
        let speechChunk = LabeledAudioChunk(
            samples: speechSamples,
            timestamp: 0.0,
            speaker: "You"
        )
        _ = filter.filter(chunk: speechChunk)

        // Pass a silent chunk after hold-open window expires (> 300ms)
        let silentChunk = LabeledAudioChunk(
            samples: Array(repeating: 0.0, count: 16000),
            timestamp: 0.4, // 400ms later
            speaker: "You"
        )
        let silentResult = filter.filter(chunk: silentChunk)

        // Should be filtered out after hold-open expires
        #expect(silentResult == nil, "Silent chunk should be filtered after hold-open expires")
    }

    @Test("very low amplitude noise is filtered")
    func testLowAmplitudeNoiseFiltered() async throws {
        let filter = VADFilter()

        // Create chunk with very low amplitude noise
        let noiseSamples = (0..<16000).map { _ in
            Float.random(in: -0.001...0.001)
        }
        let noiseChunk = LabeledAudioChunk(
            samples: noiseSamples,
            timestamp: 0.0,
            speaker: "You"
        )

        let result = filter.filter(chunk: noiseChunk)

        #expect(result == nil, "Low amplitude noise should be filtered out")
    }
}
