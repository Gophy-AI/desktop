import Foundation
@preconcurrency import CoreImage
import AppKit
import MLXVLM
import MLXLMCommon

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
        guard currentState.isUnloaded else {
            return
        }

        currentState = .loading

        do {
            guard let ocrModel = modelRegistry.availableModels().first(where: { $0.type == .ocr }) else {
                throw OCRError.noModelAvailable
            }

            let modelPath = modelRegistry.downloadPath(for: ocrModel)
            let configuration = ModelConfiguration(directory: modelPath)

            modelContainer = try await loadModelContainer(configuration: configuration)
            currentState = .ready
        } catch {
            currentState = .error(error)
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
        guard currentState.isReady else {
            throw OCRError.modelNotLoaded
        }

        guard let modelContainer else {
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
    case noModelAvailable
    case invalidImage
    case processingFailed(String)
}

extension OCREngine.State {
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
}
