import Foundation
import WhisperKit
import os.log

private let transcriptionLogger = Logger(subsystem: "com.gophy.app", category: "TranscriptionEngine")

public typealias WhisperKitLoader = @Sendable (String) async throws -> any WhisperKitProtocol

public final class TranscriptionEngine: @unchecked Sendable {
    private var whisperKit: (any WhisperKitProtocol)?
    private(set) public var isLoaded: Bool = false
    private let modelRegistry: any ModelRegistryProtocol
    private let whisperKitLoader: WhisperKitLoader

    public init(
        modelRegistry: any ModelRegistryProtocol = ModelRegistry.shared,
        whisperKitLoader: @escaping WhisperKitLoader = { modelPath in
            try await WhisperKitWrapper(modelFolder: modelPath)
        }
    ) {
        self.modelRegistry = modelRegistry
        self.whisperKitLoader = whisperKitLoader
    }

    public func load() async throws {
        let selectedId = UserDefaults.standard.string(forKey: "selectedSTTModelId") ?? "whisperkit-large-v3-turbo"
        let sttModels = modelRegistry.availableModels().filter { $0.type == .stt }

        guard let sttModel = sttModels.first(where: { $0.id == selectedId && modelRegistry.isDownloaded($0) })
                ?? sttModels.first(where: { modelRegistry.isDownloaded($0) })
                ?? sttModels.first else {
            throw TranscriptionError.noModelAvailable
        }
        let modelPath = modelRegistry.downloadPath(for: sttModel).path

        whisperKit = try await whisperKitLoader(modelPath)
        isLoaded = true
    }

    public func transcribe(audioArray: [Float], sampleRate: Int = 16000, language: String? = nil) async throws -> [TranscriptionSegment] {
        guard let whisperKit else {
            transcriptionLogger.error("TranscriptionEngine.transcribe: model not loaded")
            throw TranscriptionError.modelNotLoaded
        }

        transcriptionLogger.info("TranscriptionEngine.transcribe: processing \(audioArray.count, privacy: .public) samples")
        let results = try await whisperKit.transcribe(audioArray: audioArray, language: language)
        transcriptionLogger.info("TranscriptionEngine.transcribe: WhisperKit returned \(results.count, privacy: .public) results")

        let segments = results.flatMap { result in
            transcriptionLogger.info("Result has \(result.segments.count, privacy: .public) segments")
            return result.segments.compactMap { segment -> TranscriptionSegment? in
                let cleanedText = cleanWhisperText(segment.text)
                transcriptionLogger.info("Segment: \"\(cleanedText, privacy: .public)\"")

                // Skip empty segments after cleaning
                guard !cleanedText.isEmpty else {
                    return nil
                }

                return TranscriptionSegment(
                    text: cleanedText,
                    startTime: TimeInterval(segment.start),
                    endTime: TimeInterval(segment.end)
                )
            }
        }

        transcriptionLogger.info("TranscriptionEngine.transcribe: returning \(segments.count, privacy: .public) segments")
        return segments
    }

    /// Remove WhisperKit special tokens from transcription text
    private func cleanWhisperText(_ text: String) -> String {
        var cleaned = text

        // Remove special tokens: <|...|>
        // Matches: <|startoftranscript|>, <|en|>, <|transcribe|>, <|0.00|>, <|endoftext|>, etc.
        let tokenPattern = #"<\|[^|>]+\|>"#
        if let regex = try? NSRegularExpression(pattern: tokenPattern, options: []) {
            let range = NSRange(cleaned.startIndex..., in: cleaned)
            cleaned = regex.stringByReplacingMatches(in: cleaned, options: [], range: range, withTemplate: "")
        }

        // Trim whitespace and normalize multiple spaces
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        while cleaned.contains("  ") {
            cleaned = cleaned.replacingOccurrences(of: "  ", with: " ")
        }

        return cleaned
    }

    public func unload() {
        whisperKit = nil
        isLoaded = false
    }
}

public enum TranscriptionError: Error, Sendable {
    case modelNotLoaded
    case invalidAudioFormat
    case noModelAvailable
}
