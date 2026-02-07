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

    /// Maximum dimension for OCR input images. Larger images are scaled down
    /// to reduce the number of vision tokens and speed up inference.
    private static let maxOCRImageDimension: CGFloat = 1280

    private func performExtraction(with image: CIImage) async throws -> String {
        ocrLogger.info("performExtraction called, state=\(self.currentState.debugLabel, privacy: .public)")

        if currentState.isUnloaded || currentState.isError {
            ocrLogger.info("performExtraction: engine not ready, attempting auto-load...")
            try await load()
        }

        guard currentState.isReady else {
            ocrLogger.error("performExtraction: engine still not ready after auto-load, state=\(self.currentState.debugLabel, privacy: .public)")
            throw OCRError.modelNotLoaded
        }

        guard let modelContainer else {
            ocrLogger.error("performExtraction: modelContainer is nil")
            throw OCRError.modelNotLoaded
        }

        currentState = .processing

        do {
            // Downscale large images to reduce vision token count
            let processedImage = Self.downscaleForOCR(image)
            ocrLogger.info("OCR image size: \(Int(processedImage.extent.width), privacy: .public)x\(Int(processedImage.extent.height), privacy: .public) (original: \(Int(image.extent.width), privacy: .public)x\(Int(image.extent.height), privacy: .public))")

            let userInput = UserInput(
                chat: [
                    .user(
                        "Read and transcribe all visible text in this image exactly as written. Output only the text content, preserving paragraphs. Do not describe the image or add commentary.",
                        images: [.ciImage(processedImage)]
                    )
                ],
                additionalContext: ["enable_thinking": false]
            )

            let input = try await modelContainer.prepare(input: userInput)

            let ocrMaxTokens = UserDefaults.standard.integer(forKey: "inference.ocrMaxTokens")
            let parameters = GenerateParameters(
                maxTokens: ocrMaxTokens > 0 ? ocrMaxTokens : 4096,
                temperature: 0.0,
                repetitionPenalty: 1.2,
                repetitionContextSize: 64
            )

            var extractedText = ""
            var recentChunks: [String] = []

            let stream = try await modelContainer.generate(
                input: input,
                parameters: parameters
            )

            for await generation in stream {
                switch generation {
                case .chunk(let text):
                    extractedText += text

                    // Repetition detection: track recent chunks and stop if looping
                    recentChunks.append(text)
                    if recentChunks.count > 20 {
                        recentChunks.removeFirst()
                    }
                    if recentChunks.count >= 10, Self.detectRepetition(in: recentChunks) {
                        ocrLogger.warning("Repetition detected after \(extractedText.count, privacy: .public) chars, stopping generation")
                        break
                    }
                case .info(let info):
                    ocrLogger.info("OCR generation: \(info.generationTokenCount, privacy: .public) tokens, \(String(format: "%.1f", info.tokensPerSecond), privacy: .public) tok/s, prompt \(String(format: "%.2f", info.promptTime), privacy: .public)s")
                case .toolCall:
                    break
                }
            }

            // Strip <think>...</think> blocks (Qwen3 thinking mode)
            var strippedText = Self.stripThinkingBlocks(extractedText)

            // Trim trailing repetitive content
            strippedText = Self.trimRepetitiveTrailing(strippedText)

            currentState = .ready
            return strippedText.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            currentState = .error(error)
            throw error
        }
    }

    /// Downscale image if either dimension exceeds maxOCRImageDimension.
    private static func downscaleForOCR(_ image: CIImage) -> CIImage {
        let extent = image.extent
        let maxDim = max(extent.width, extent.height)
        guard maxDim > maxOCRImageDimension else { return image }

        let scale = maxOCRImageDimension / maxDim
        return image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
    }

    /// Strip `<think>...</think>` blocks produced by Qwen3 thinking mode.
    /// The actual response follows after the last `</think>` tag.
    private static func stripThinkingBlocks(_ text: String) -> String {
        // If there's a </think> tag, the real content is everything after the last one
        if let lastThinkEnd = text.range(of: "</think>", options: .backwards) {
            return String(text[lastThinkEnd.upperBound...])
        }
        // If there's an opening <think> with no closing tag, model is still thinking — no real content yet
        if text.range(of: "<think>") != nil {
            return ""
        }
        return text
    }

    /// Detect if recent chunks form a repeating pattern.
    private static func detectRepetition(in chunks: [String]) -> Bool {
        let joined = chunks.joined()
        guard joined.count > 40 else { return false }

        // Check if the last portion is repeating a pattern
        // Split into lines and check for repeated lines
        let lines = joined.components(separatedBy: .newlines).filter { !$0.isEmpty }
        guard lines.count >= 4 else { return false }

        let lastLines = Array(lines.suffix(6))
        let uniqueLines = Set(lastLines)
        // If 6 recent lines have 2 or fewer unique values, it's repeating
        if lastLines.count >= 4 && uniqueLines.count <= 2 {
            return true
        }

        // Check for substring repetition in the last 200 chars
        let tail = String(joined.suffix(200))
        for patternLen in 10...min(60, tail.count / 3) {
            let pattern = String(tail.suffix(patternLen))
            let count = tail.components(separatedBy: pattern).count - 1
            if count >= 3 {
                return true
            }
        }

        return false
    }

    /// Trim trailing repetitive content from extracted text.
    private static func trimRepetitiveTrailing(_ text: String) -> String {
        let lines = text.components(separatedBy: .newlines)
        guard lines.count > 3 else { return text }

        // Find where repetition starts by looking backwards
        var cutIndex = lines.count
        var seen = Set<String>()
        var repeatCount = 0

        for i in stride(from: lines.count - 1, through: max(0, lines.count - 30), by: -1) {
            let line = lines[i].trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            if seen.contains(line) {
                repeatCount += 1
                if repeatCount >= 3 {
                    cutIndex = i
                }
            } else {
                if repeatCount < 3 {
                    seen.insert(line)
                    repeatCount = 0
                } else {
                    break
                }
            }
        }

        if cutIndex < lines.count {
            return lines[0..<cutIndex].joined(separator: "\n")
        }
        return text
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
