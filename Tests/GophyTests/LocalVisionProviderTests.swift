import Testing
import Foundation
@preconcurrency import CoreImage
@testable import Gophy

@Suite("LocalVisionProvider Tests")
struct LocalVisionProviderTests {

    @Test("Conforms to VisionProvider protocol")
    func testProtocolConformance() async {
        let mockEngine = StubOCREngine()
        let provider: any VisionProvider = LocalVisionProvider(engine: mockEngine)
        _ = provider
    }

    @Test("ExtractText returns OCR result")
    func testExtractText() async throws {
        let mockEngine = StubOCREngine()
        await mockEngine.setLoaded(true)
        await mockEngine.setTextToReturn("Hello from OCR")

        let provider = LocalVisionProvider(engine: mockEngine)

        // Create a minimal 1x1 PNG image
        let imageData = createMinimalPNGData()
        let result = try await provider.extractText(from: imageData, prompt: "Extract text")

        #expect(result == "Hello from OCR")
    }

    @Test("Unloaded engine throws ProviderError.notConfigured")
    func testUnloadedEngineThrows() async {
        let mockEngine = StubOCREngine()
        await mockEngine.setLoaded(false)

        let provider = LocalVisionProvider(engine: mockEngine)
        let imageData = createMinimalPNGData()

        do {
            _ = try await provider.extractText(from: imageData, prompt: "Extract text")
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

    @Test("AnalyzeImage returns streaming result")
    func testAnalyzeImage() async throws {
        let mockEngine = StubOCREngine()
        await mockEngine.setLoaded(true)
        await mockEngine.setTextToReturn("Analyzed text content")

        let provider = LocalVisionProvider(engine: mockEngine)
        let imageData = createMinimalPNGData()

        var collected = ""
        let stream = provider.analyzeImage(imageData: imageData, prompt: "Analyze")
        for try await chunk in stream {
            collected += chunk
        }

        #expect(collected == "Analyzed text content")
    }

    private func createMinimalPNGData() -> Data {
        // Minimal 1x1 white PNG
        let pngBytes: [UInt8] = [
            0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, // PNG signature
            0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, // IHDR chunk
            0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
            0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53,
            0xDE, 0x00, 0x00, 0x00, 0x0C, 0x49, 0x44, 0x41, // IDAT chunk
            0x54, 0x08, 0xD7, 0x63, 0xF8, 0xCF, 0xC0, 0x00,
            0x00, 0x00, 0x02, 0x00, 0x01, 0xE2, 0x21, 0xBC,
            0x33, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, // IEND chunk
            0x44, 0xAE, 0x42, 0x60, 0x82
        ]
        return Data(pngBytes)
    }
}

actor StubOCREngine: VisionCapable {
    private var _isLoadedValue = false
    private var _textToReturn = ""

    nonisolated var isLoaded: Bool {
        get async {
            await getIsLoaded()
        }
    }

    private func getIsLoaded() -> Bool {
        return _isLoadedValue
    }

    func setLoaded(_ value: Bool) {
        _isLoadedValue = value
    }

    func setTextToReturn(_ text: String) {
        _textToReturn = text
    }

    func load() async throws {
        _isLoadedValue = true
    }

    func unload() async {
        _isLoadedValue = false
    }

    nonisolated func extractText(from image: CIImage) async throws -> String {
        let loaded = await getIsLoaded()
        guard loaded else {
            throw OCRError.modelNotLoaded
        }
        return await getTextToReturn()
    }

    private func getTextToReturn() -> String {
        return _textToReturn
    }
}
