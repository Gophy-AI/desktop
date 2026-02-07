import Foundation
import os
@preconcurrency import CoreImage
import AppKit
import MLXVLM
import MLXLMCommon

private let ocrLogger = Logger(subsystem: "com.gophy.app", category: "OCREngine")

public protocol OCREngineProtocol: Sendable {
    var isLoaded: Bool { get async }
    func load() async throws
    nonisolated func extractText(from image: CIImage) async throws -> String
    nonisolated func extractText(from image: CGImage) async throws -> String
    func unload() async
}

public actor OCREngine: OCREngineProtocol {
    public enum State: Sendable {
        case unloaded
        case loading
        case ready
        case processing
        case error(Error)
    }

    private var modelContainer: ModelContainer?
    private var currentState: State = .unloaded
    private let modelRegistry: any ModelRegistryProtocol

    public nonisolated var isLoaded: Bool {
        get async {
            await getState().isReady
        }
    }

    private func getState() -> State {
        return currentState
    }

    public init(modelRegistry: any ModelRegistryProtocol = ModelRegistry.shared) {
        self.modelRegistry = modelRegistry
    }

    public func load() async throws {
        ocrLogger.info("load() called, currentState=\(self.currentState.debugLabel, privacy: .public)")
        guard currentState.isUnloaded || currentState.isError else {
            ocrLogger.debug("load() called but state is not unloaded/error, skipping")
            return
        }

        currentState = .loading
        ocrLogger.info("OCR engine loading started")

        do {
            let selectedId = UserDefaults.standard.string(forKey: "selectedOCRModelId") ?? "qwen2.5-vl-7b-instruct-4bit"
            let ocrModels = modelRegistry.availableModels().filter { $0.type == .ocr }

            guard let ocrModel = ocrModels.first(where: { $0.id == selectedId && modelRegistry.isDownloaded($0) })
                    ?? ocrModels.first(where: { modelRegistry.isDownloaded($0) })
                    ?? ocrModels.first else {
                ocrLogger.error("No OCR model found in registry")
                throw OCRError.noModelAvailable
            }

            ocrLogger.info("OCR model found: id=\(ocrModel.id) hf=\(ocrModel.huggingFaceID)")

            let isDownloaded = modelRegistry.isDownloaded(ocrModel)
            let downloadPath = modelRegistry.downloadPath(for: ocrModel)
            ocrLogger.info("isDownloaded=\(isDownloaded) downloadPath=\(downloadPath.path)")

            guard isDownloaded else {
                ocrLogger.error("OCR model not downloaded at \(downloadPath.path)")
                throw OCRError.modelNotDownloaded
            }

            // Log directory contents
            if let contents = try? FileManager.default.contentsOfDirectory(atPath: downloadPath.path) {
                ocrLogger.info("Model directory contents (\(contents.count) files): \(contents.joined(separator: ", "))")
            }

            let configuration = ModelConfiguration(directory: downloadPath)
            ocrLogger.info("Loading model container from \(downloadPath.path)")

            modelContainer = try await VLMModelFactory.shared.loadContainer(configuration: configuration)
            currentState = .ready
            ocrLogger.info("OCR engine loaded successfully")
        } catch {
            currentState = .error(error)
            ocrLogger.error("OCR engine load failed: \(error)")
            throw error
        }
    }

    nonisolated public func extractText(from image: CIImage) async throws -> String {
        return try await performExtraction(with: image)
    }

    nonisolated public func extractText(from cgImage: CGImage) async throws -> String {
        let ciImage = CIImage(cgImage: cgImage)
        return try await performExtraction(with: ciImage)
    }

    private func performExtraction(with image: CIImage) async throws -> String {
        ocrLogger.info("performExtraction called, state=\(self.currentState.debugLabel, privacy: .public)")

        guard currentState.isReady else {
            ocrLogger.error("performExtraction: engine not ready, state=\(self.currentState.debugLabel, privacy: .public)")
            throw OCRError.modelNotLoaded
        }

        guard let modelContainer else {
            ocrLogger.error("performExtraction: modelContainer is nil")
            throw OCRError.modelNotLoaded
        }

        currentState = .processing

        do {
            let userInput = UserInput(
                prompt: "Extract all text from this image. Return only the extracted text without any additional commentary.",
                images: [.ciImage(image)]
            )

            let input = try await modelContainer.prepare(input: userInput)

            let parameters = GenerateParameters(
                maxTokens: 2048,
                temperature: 0.0
            )

            var extractedText = ""

            let stream = try await modelContainer.generate(
                input: input,
                parameters: parameters
            )

            for await generation in stream {
                switch generation {
                case .chunk(let text):
                    extractedText += text
                case .info:
                    break
                case .toolCall:
                    break
                }
            }

            currentState = .ready
            return extractedText.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            currentState = .error(error)
            throw error
        }
    }

    public func unload() async {
        modelContainer = nil
        currentState = .unloaded
    }
}

public enum OCRError: Error, Sendable {
    case modelNotLoaded
    case modelNotDownloaded
    case noModelAvailable
    case invalidImage
    case processingFailed(String)
}

extension OCREngine.State {
    var debugLabel: String {
        switch self {
        case .unloaded: return "unloaded"
        case .loading: return "loading"
        case .ready: return "ready"
        case .processing: return "processing"
        case .error(let error): return "error(\(error))"
        }
    }

    fileprivate var isReady: Bool {
        if case .ready = self {
            return true
        }
        return false
    }

    fileprivate var isUnloaded: Bool {
        if case .unloaded = self {
            return true
        }
        return false
    }

    fileprivate var isError: Bool {
        if case .error = self {
            return true
        }
        return false
    }
}
