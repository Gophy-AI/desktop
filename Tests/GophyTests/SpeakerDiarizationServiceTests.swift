import Testing
@testable import Gophy

@Suite("SpeakerDiarizationService Tests")
struct SpeakerDiarizationServiceTests {

    // MARK: - Mock Backend

    actor MockDiarizationBackend: DiarizationBackend {
        var segmentsToReturn: [SpeakerSegment] = []
        var processCallCount = 0
        var lastSamples: [Float]?
        var lastSampleRate: Int?
        private var _isModelAvailable = true

        nonisolated var isModelAvailable: Bool { true }

        func setModelAvailable(_ available: Bool) {
            _isModelAvailable = available
        }

        func setSegments(_ segments: [SpeakerSegment]) {
            segmentsToReturn = segments
        }

        func process(samples: [Float], sampleRate: Int) async throws -> [SpeakerSegment] {
            processCallCount += 1
            lastSamples = samples
            lastSampleRate = sampleRate
            return segmentsToReturn
        }
    }

    private func makeService(segments: [SpeakerSegment] = []) async -> (
        service: SpeakerDiarizationService,
        backend: MockDiarizationBackend
    ) {
        let backend = MockDiarizationBackend()
        await backend.setSegments(segments)
        let service = SpeakerDiarizationService(backend: backend)
        return (service, backend)
    }

    // MARK: - Diarize Tests

    @Test("Diarize returns DiarizationResult with speaker segments")
    func diarizeReturnsDiarizationResultWithSpeakerSegments() async throws {
        let segments = [
            SpeakerSegment(speakerLabel: "Speaker 1", startTime: 0.0, endTime: 5.0),
            SpeakerSegment(speakerLabel: "Speaker 2", startTime: 5.0, endTime: 10.0),
            SpeakerSegment(speakerLabel: "Speaker 1", startTime: 10.0, endTime: 15.0),
        ]
        let (service, _) = await makeService(segments: segments)

        let samples = [Float](repeating: 0.1, count: 16000 * 15)
        let result = try await service.diarize(samples: samples, sampleRate: 16000)

        #expect(result.segments.count == 3)
        #expect(result.speakerCount == 2)
    }

    @Test("Each segment has speakerLabel, startTime, endTime")
    func eachSegmentHasSpeakerLabelStartTimeEndTime() async throws {
        let segments = [
            SpeakerSegment(speakerLabel: "Speaker 1", startTime: 0.0, endTime: 3.5),
            SpeakerSegment(speakerLabel: "Speaker 2", startTime: 3.5, endTime: 8.2),
        ]
        let (service, _) = await makeService(segments: segments)

        let samples = [Float](repeating: 0.1, count: 16000 * 9)
        let result = try await service.diarize(samples: samples, sampleRate: 16000)

        let first = result.segments[0]
        #expect(first.speakerLabel == "Speaker 1")
        #expect(first.startTime == 0.0)
        #expect(first.endTime == 3.5)

        let second = result.segments[1]
        #expect(second.speakerLabel == "Speaker 2")
        #expect(second.startTime == 3.5)
        #expect(second.endTime == 8.2)
    }

    @Test("Speaker labels are consistent across segments")
    func speakerLabelsAreConsistentAcrossSegments() async throws {
        let segments = [
            SpeakerSegment(speakerLabel: "Speaker 1", startTime: 0.0, endTime: 5.0),
            SpeakerSegment(speakerLabel: "Speaker 2", startTime: 5.0, endTime: 10.0),
            SpeakerSegment(speakerLabel: "Speaker 1", startTime: 10.0, endTime: 15.0),
            SpeakerSegment(speakerLabel: "Speaker 2", startTime: 15.0, endTime: 20.0),
        ]
        let (service, _) = await makeService(segments: segments)

        let samples = [Float](repeating: 0.1, count: 16000 * 20)
        let result = try await service.diarize(samples: samples, sampleRate: 16000)

        // Same speaker gets same label across non-contiguous segments
        #expect(result.segments[0].speakerLabel == result.segments[2].speakerLabel)
        #expect(result.segments[1].speakerLabel == result.segments[3].speakerLabel)
        #expect(result.segments[0].speakerLabel != result.segments[1].speakerLabel)
    }

    // MARK: - speakerLabelAt Tests

    @Test("speakerLabelAt returns correct speaker for a given timestamp")
    func speakerLabelAtReturnsCorrectSpeaker() async throws {
        let segments = [
            SpeakerSegment(speakerLabel: "Speaker 1", startTime: 0.0, endTime: 5.0),
            SpeakerSegment(speakerLabel: "Speaker 2", startTime: 5.0, endTime: 10.0),
            SpeakerSegment(speakerLabel: "Speaker 3", startTime: 10.0, endTime: 15.0),
        ]
        let (service, _) = await makeService(segments: segments)

        let samples = [Float](repeating: 0.1, count: 16000 * 15)
        _ = try await service.diarize(samples: samples, sampleRate: 16000)

        let speaker1 = await service.speakerLabelAt(time: 2.5)
        #expect(speaker1 == "Speaker 1")

        let speaker2 = await service.speakerLabelAt(time: 7.0)
        #expect(speaker2 == "Speaker 2")

        let speaker3 = await service.speakerLabelAt(time: 12.0)
        #expect(speaker3 == "Speaker 3")
    }

    @Test("speakerLabelAt returns nil for timestamp outside segments")
    func speakerLabelAtReturnsNilForOutsideTimestamp() async throws {
        let segments = [
            SpeakerSegment(speakerLabel: "Speaker 1", startTime: 2.0, endTime: 5.0),
        ]
        let (service, _) = await makeService(segments: segments)

        let samples = [Float](repeating: 0.1, count: 16000 * 5)
        _ = try await service.diarize(samples: samples, sampleRate: 16000)

        let label = await service.speakerLabelAt(time: 1.0)
        #expect(label == nil)

        let labelAfter = await service.speakerLabelAt(time: 6.0)
        #expect(labelAfter == nil)
    }

    // MARK: - renameSpeaker Tests

    @Test("renameSpeaker updates all segments with that label")
    func renameSpeakerUpdatesAllSegments() async throws {
        let segments = [
            SpeakerSegment(speakerLabel: "Speaker 1", startTime: 0.0, endTime: 5.0),
            SpeakerSegment(speakerLabel: "Speaker 2", startTime: 5.0, endTime: 10.0),
            SpeakerSegment(speakerLabel: "Speaker 1", startTime: 10.0, endTime: 15.0),
        ]
        let (service, _) = await makeService(segments: segments)

        let samples = [Float](repeating: 0.1, count: 16000 * 15)
        _ = try await service.diarize(samples: samples, sampleRate: 16000)

        await service.renameSpeaker(from: "Speaker 1", to: "Alice")

        let labelAt2 = await service.speakerLabelAt(time: 2.5)
        #expect(labelAt2 == "Alice")

        let labelAt7 = await service.speakerLabelAt(time: 7.0)
        #expect(labelAt7 == "Speaker 2")

        let labelAt12 = await service.speakerLabelAt(time: 12.0)
        #expect(labelAt12 == "Alice")
    }

    // MARK: - Empty/Silence Tests

    @Test("Diarize with empty samples returns empty result")
    func diarizeWithEmptySamplesReturnsEmptyResult() async throws {
        let (service, _) = await makeService(segments: [])

        let result = try await service.diarize(samples: [], sampleRate: 16000)

        #expect(result.segments.isEmpty)
        #expect(result.speakerCount == 0)
    }

    @Test("Diarize with silence returns empty result")
    func diarizeWithSilenceReturnsEmptyResult() async throws {
        // Backend returns no segments for silence
        let (service, _) = await makeService(segments: [])

        let silentSamples = [Float](repeating: 0.0, count: 16000 * 5)
        let result = try await service.diarize(samples: silentSamples, sampleRate: 16000)

        #expect(result.segments.isEmpty)
        #expect(result.speakerCount == 0)
    }

    // MARK: - isAvailable Test

    @Test("isAvailable reflects backend model availability")
    func isAvailableReflectsBackendModelAvailability() async {
        let (service, _) = await makeService()

        let available = await service.isAvailable
        #expect(available == true)
    }

    // MARK: - Backend Integration Tests

    @Test("Diarize passes samples and sampleRate to backend")
    func diarizePassesSamplesAndSampleRateToBackend() async throws {
        let (service, backend) = await makeService(segments: [
            SpeakerSegment(speakerLabel: "Speaker 1", startTime: 0.0, endTime: 1.0),
        ])

        let samples: [Float] = [0.1, 0.2, 0.3, 0.4, 0.5]
        _ = try await service.diarize(samples: samples, sampleRate: 44100)

        let callCount = await backend.processCallCount
        #expect(callCount == 1)

        let lastSamples = await backend.lastSamples
        #expect(lastSamples == samples)

        let lastSampleRate = await backend.lastSampleRate
        #expect(lastSampleRate == 44100)
    }
}
