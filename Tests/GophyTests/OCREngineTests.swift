import XCTest
@testable import Gophy

final class OCREngineTests: XCTestCase {
    func testOCREngineCanBeInitialized() {
        let engine = OCREngine()
        XCTAssertNotNil(engine)
    }

    func testOCREngineInitialStateIsNotLoaded() async {
        let engine = OCREngine()
        let isLoaded = await engine.isLoaded
        XCTAssertFalse(isLoaded, "Engine should not be loaded initially")
    }

    func testOCREngineLoadThrowsWhenNoModelAvailable() async {
        let emptyRegistry = EmptyModelRegistry()
        let engine = OCREngine(modelRegistry: emptyRegistry)

        do {
            try await engine.load()
            XCTFail("Expected OCRError.noModelAvailable")
        } catch OCRError.noModelAvailable {
            XCTAssertTrue(true)
        } catch {
            XCTFail("Expected OCRError.noModelAvailable but got \(error)")
        }
    }

    func testOCREngineExtractTextThrowsWhenModelNotLoaded() async {
        let engine = OCREngine()
        let image = createTestImage()

        do {
            _ = try await engine.extractText(from: image)
            XCTFail("Expected OCRError.modelNotLoaded")
        } catch OCRError.modelNotLoaded {
            XCTAssertTrue(true)
        } catch {
            XCTFail("Expected OCRError.modelNotLoaded but got \(error)")
        }
    }

    func testOCREngineExtractTextFromCGImageThrowsWhenModelNotLoaded() async {
        let engine = OCREngine()
        let cgImage = createTestCGImage()

        do {
            _ = try await engine.extractText(from: cgImage)
            XCTFail("Expected OCRError.modelNotLoaded")
        } catch OCRError.modelNotLoaded {
            XCTAssertTrue(true)
        } catch {
            XCTFail("Expected OCRError.modelNotLoaded but got \(error)")
        }
    }

    func testOCREngineUnloadSetsIsLoadedToFalse() async {
        let engine = OCREngine()
        await engine.unload()
        let isLoaded = await engine.isLoaded
        XCTAssertFalse(isLoaded, "Engine should not be loaded after unload()")
    }

    private func createTestImage() -> CIImage {
        let size = CGSize(width: 100, height: 100)
        return CIImage(color: .white).cropped(to: CGRect(origin: .zero, size: size))
    }

    private func createTestCGImage() -> CGImage {
        let width = 100
        let height = 100
        let bitsPerComponent = 8
        let bytesPerRow = width * 4
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

        var data = [UInt8](repeating: 255, count: width * height * 4)

        let context = CGContext(
            data: &data,
            width: width,
            height: height,
            bitsPerComponent: bitsPerComponent,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        )!

        return context.makeImage()!
    }
}

final class EmptyModelRegistry: ModelRegistryProtocol {
    func availableModels() -> [ModelDefinition] {
        return []
    }

    func downloadPath(for model: ModelDefinition) -> URL {
        URL(fileURLWithPath: "/tmp/empty")
    }

    func isDownloaded(_ model: ModelDefinition) -> Bool {
        return false
    }
}
