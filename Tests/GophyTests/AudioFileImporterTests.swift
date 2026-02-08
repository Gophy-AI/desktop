import Testing
import Foundation
@testable import Gophy

@Suite("AudioFileImporter Tests")
struct AudioFileImporterTests {

    private func testResourceURL(_ name: String) -> URL? {
        // Look relative to current file location for test resources
        let testDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let resourceURL = testDir.appendingPathComponent("Resources").appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: resourceURL.path) {
            return resourceURL
        }
        return nil
    }

    @Test("supportedFormats contains all required formats")
    func testSupportedFormats() {
        let expected: Set<String> = ["mp3", "wav", "m4a", "mp4", "aiff", "caf", "flac", "mov", "mkv", "webm"]
        let actual = Set(AudioFileImporter.supportedFormats)
        #expect(actual == expected)
    }

    @Test("importFile with .wav URL returns valid AudioFileInfo")
    func testImportWAV() async throws {
        guard let url = testResourceURL("test-recording.wav") else {
            Issue.record("test-recording.wav not found in Resources")
            return
        }

        let importer = AudioFileImporter()
        let info = try await importer.importFile(url: url)

        #expect(info.fileURL == url)
        #expect(info.duration > 0.9 && info.duration < 1.1, "Expected ~1s duration, got \(info.duration)")
        #expect(info.sampleRate == 16000.0, "Expected 16kHz sample rate, got \(info.sampleRate)")
        #expect(info.channelCount == 1, "Expected mono, got \(info.channelCount) channels")
        #expect(info.format == "wav")
    }

    @Test("importFile with unsupported format throws unsupportedFormat")
    func testUnsupportedFormat() async {
        let url = URL(fileURLWithPath: "/tmp/fake.webm")
        let importer = AudioFileImporter()

        await #expect(throws: AudioFileImportError.self) {
            try await importer.importFile(url: url)
        }
    }

    @Test("importFile with nonexistent path throws fileNotFound")
    func testFileNotFound() async {
        let url = URL(fileURLWithPath: "/nonexistent/path/audio.wav")
        let importer = AudioFileImporter()

        await #expect(throws: AudioFileImportError.self) {
            try await importer.importFile(url: url)
        }
    }

    @Test("AudioFileInfo stores correct metadata")
    func testAudioFileInfoMetadata() {
        let url = URL(fileURLWithPath: "/test/audio.wav")
        let info = AudioFileInfo(
            fileURL: url,
            duration: 120.5,
            sampleRate: 44100.0,
            channelCount: 2,
            format: "wav"
        )

        #expect(info.fileURL == url)
        #expect(info.duration == 120.5)
        #expect(info.sampleRate == 44100.0)
        #expect(info.channelCount == 2)
        #expect(info.format == "wav")
    }
}
