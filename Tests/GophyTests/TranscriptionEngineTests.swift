import XCTest
import Foundation
@testable import Gophy

final class TranscriptionEngineTests: XCTestCase {
    var mockModelRegistry: TranscriptionMockModelRegistry!
    var mockWhisperKit: MockWhisperKit!
    var engine: TranscriptionEngine!

    override func setUp() async throws {
        try await super.setUp()
        mockModelRegistry = TranscriptionMockModelRegistry()
        let whisperKit = MockWhisperKit()
        mockWhisperKit = whisperKit

        engine = TranscriptionEngine(
            modelRegistry: mockModelRegistry,
            whisperKitLoader: { _ in whisperKit }
        )
    }

    override func tearDown() async throws {
        engine = nil
        mockModelRegistry = nil
        mockWhisperKit = nil
        try await super.tearDown()
    }

    func testTranscriptionEngineCanBeInitialized() {
        XCTAssertNotNil(engine)
        XCTAssertFalse(engine.isLoaded)
    }

    func testTranscriptionEngineLoadSetsIsLoadedToTrue() async throws {
        try await engine.load()
        XCTAssertTrue(engine.isLoaded)
    }

    func testTranscriptionEngineThrowsWhenTranscribingWithoutLoading() async {
        let audioArray: [Float] = Array(repeating: 0.0, count: 16000)

        do {
            _ = try await engine.transcribe(audioArray: audioArray)
            XCTFail("Expected TranscriptionError.modelNotLoaded")
        } catch TranscriptionError.modelNotLoaded {
            XCTAssertTrue(true)
        } catch {
            XCTFail("Expected TranscriptionError.modelNotLoaded but got \(error)")
        }
    }

    func testTranscriptionEngineReturnsSegmentsWithTextStartTimeEndTime() async throws {
        try await engine.load()

        let audioArray: [Float] = Array(repeating: 0.0, count: 16000)
        let segments = try await engine.transcribe(audioArray: audioArray)

        XCTAssertFalse(segments.isEmpty)
        for segment in segments {
            XCTAssertFalse(segment.text.isEmpty)
            XCTAssertGreaterThanOrEqual(segment.endTime, segment.startTime)
        }
    }

    func testUnloadSetsIsLoadedToFalse() async throws {
        try await engine.load()
        XCTAssertTrue(engine.isLoaded)

        engine.unload()
        XCTAssertFalse(engine.isLoaded)
    }

    func testUnloadAllowsReloading() async throws {
        try await engine.load()
        XCTAssertTrue(engine.isLoaded)

        engine.unload()
        XCTAssertFalse(engine.isLoaded)

        try await engine.load()
        XCTAssertTrue(engine.isLoaded)
    }

    func testTranscribeWithNilLanguageUsesAutoDetect() async throws {
        try await engine.load()
        let audioArray: [Float] = Array(repeating: 0.0, count: 16000)
        _ = try await engine.transcribe(audioArray: audioArray, language: nil)
        XCTAssertNil(mockWhisperKit.lastLanguage)
    }

    func testTranscribeWithRussianLanguagePassesLanguageHint() async throws {
        try await engine.load()
        let audioArray: [Float] = Array(repeating: 0.0, count: 16000)
        _ = try await engine.transcribe(audioArray: audioArray, language: "ru")
        XCTAssertEqual(mockWhisperKit.lastLanguage, "ru")
    }

    func testTranscribeWithSpanishLanguagePassesLanguageHint() async throws {
        try await engine.load()
        let audioArray: [Float] = Array(repeating: 0.0, count: 16000)
        _ = try await engine.transcribe(audioArray: audioArray, language: "es")
        XCTAssertEqual(mockWhisperKit.lastLanguage, "es")
    }
}

final class TranscriptionMockModelRegistry: ModelRegistryProtocol {
    func availableModels() -> [ModelDefinition] {
        return [
            ModelDefinition(
                id: "test-whisper",
                name: "Test Whisper",
                type: .stt,
                huggingFaceID: "test/whisper",
                approximateSizeGB: 0.1,
                memoryUsageGB: 0.1
            )
        ]
    }

    func downloadPath(for model: ModelDefinition) -> URL {
        URL(fileURLWithPath: "/tmp/test-models/\(model.id)")
    }

    func isDownloaded(_ model: ModelDefinition) -> Bool {
        return true
    }
}

final class MockWhisperKit: WhisperKitProtocol, @unchecked Sendable {
    var lastLanguage: String?

    func transcribe(audioArray: [Float], language: String? = nil) async throws -> [WhisperResultProtocol] {
        lastLanguage = language
        return [
            MockWhisperResult(segments: [
                MockWhisperSegment(text: "Hello world", start: 0.0, end: 1.0),
                MockWhisperSegment(text: "This is a test", start: 1.0, end: 2.5)
            ])
        ]
    }
}

struct MockWhisperResult: WhisperResultProtocol {
    let segments: [WhisperSegmentProtocol]
}

struct MockWhisperSegment: WhisperSegmentProtocol {
    let text: String
    let start: Float
    let end: Float
}
