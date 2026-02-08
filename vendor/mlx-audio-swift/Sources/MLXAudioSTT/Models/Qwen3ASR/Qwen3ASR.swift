//
//  Qwen3ASR.swift
//  MLXAudioSTT
//
// Qwen3 ASR model with generation and streaming.
//

import Foundation
import MLX
import MLXNN
import MLXLMCommon
import MLXAudioCore
import HuggingFace
import Tokenizers
import Hub

// MARK: - Transcript Segment

/// A transcript segment with timestamps.
public struct TranscriptSegment {
    public let text: String
    public let start: Float
    public let end: Float

    public init(text: String, start: Float, end: Float) {
        self.text = text
        self.start = start
        self.end = end
    }
}

// MARK: - Qwen3 ASR Model

/// Qwen3 ASR model combining audio encoder and text decoder.
public class Qwen3ASRModel: Module, @unchecked Sendable {
    let config: Qwen3ASRModelConfig

    @ModuleInfo(key: "audio_tower") var audioTower: Qwen3ASRAudioEncoder
    @ModuleInfo(key: "text_model") var textModel: TextModel
    @ModuleInfo(key: "lm_head") var lmHead: Linear

    public var tokenizer: Tokenizer?

    public init(config: Qwen3ASRModelConfig) {
        self.config = config

        self._audioTower.wrappedValue = Qwen3ASRAudioEncoder(config: config.audioConfig)
        self._textModel.wrappedValue = TextModel(config: config.textConfig)
        self._lmHead.wrappedValue = Linear(config.textConfig.hiddenSize, config.textConfig.vocabSize, bias: false)
    }

    public func callAsFunction(
        _ inputFeatures: MLXArray,
        _ inputIds: MLXArray,
        cache: [KVCacheSimple]? = nil
    ) -> MLXArray {
        // Encode audio features
        let audioFeatures = audioTower(inputFeatures)  // [audio_len, output_dim]

        // Embed input tokens
        var hiddenStates = textModel.embedTokens(inputIds)  // [batch, seq_len, hidden_size]

        // Find positions where audio_token_id appears and replace with audio features
        let audioTokenId = config.audioTokenId
        let batchSize = hiddenStates.shape[0]
        let seqLen = hiddenStates.shape[1]

        // For each batch item, find audio token positions
        for b in 0..<batchSize {
            let tokenIds = inputIds[b]
            for s in 0..<seqLen {
                let tokenId = tokenIds[s].item(Int.self)
                if tokenId == audioTokenId {
                    // Replace with audio features
                    // Note: In practice, we'd need to handle the audio feature length
                    // For simplicity, assume audio features fit at this position
                    let audioLen = audioFeatures.shape[0]
                    let featDim = audioFeatures.shape[1]
                    let hiddenDim = hiddenStates.shape[2]

                    // Project audio features to match hidden_size if needed
                    if featDim != hiddenDim {
                        precondition(featDim == hiddenDim,
                                     "Audio feature dim (\(featDim)) must match text hidden size (\(hiddenDim))")
                    }

                    let endPos = min(s + audioLen, seqLen)
                    let audioSlice = audioFeatures[0..<(endPos - s)]
                    hiddenStates[b, s..<endPos] = audioSlice
                }
            }
        }

        // Run through text model layers
        for (i, layer) in textModel.layers.enumerated() {
            let layerCache = cache?[i]
            hiddenStates = layer(hiddenStates, cache: layerCache)
        }

        hiddenStates = textModel.norm(hiddenStates)

        // Generate logits
        let logits = lmHead(hiddenStates)
        return logits
    }

    /// Sanitize weights from HuggingFace format.
    public static func sanitize(weights: [String: MLXArray]) -> [String: MLXArray] {
        var sanitized = weights

        // Transpose Conv2d weights (swap dims -1, -2)
        for key in sanitized.keys {
            if key.contains("conv2d") && key.hasSuffix(".weight") {
                let weight = sanitized[key]!
                let ndim = weight.ndim
                if ndim >= 2 {
                    sanitized[key] = weight.swappedAxes(-1, -2)
                }
            }
        }

        return sanitized
    }

    /// Split audio into chunks based on energy.
    public static func splitAudioIntoChunks(
        audio: [Float],
        sampleRate: Int,
        maxChunkDuration: Float = 1200.0
    ) -> [(audio: [Float], offset: Float)] {
        let totalSamples = audio.count
        let totalSeconds = Float(totalSamples) / Float(sampleRate)

        if totalSeconds <= maxChunkDuration {
            return [(audio, 0.0)]
        }

        var chunks: [(audio: [Float], offset: Float)] = []
        var startSample = 0
        let maxChunkSamples = Int(maxChunkDuration * Float(sampleRate))
        let searchSamples = Int(5.0 * Float(sampleRate))
        let minWindowSamples = Int(0.1 * Float(sampleRate))

        while startSample < totalSamples {
            let endSample = min(startSample + maxChunkSamples, totalSamples)

            if endSample >= totalSamples {
                let chunk = Array(audio[startSample..<totalSamples])
                let offset = Float(startSample) / Float(sampleRate)
                chunks.append((chunk, offset))
                break
            }

            // Find low-energy point
            let searchStart = max(startSample, endSample - searchSamples)
            let searchEnd = min(totalSamples, endSample + searchSamples)
            let searchRegion = Array(audio[searchStart..<searchEnd])

            var cutSample = endSample
            if searchRegion.count > minWindowSamples {
                // Calculate energy using sliding window
                var minEnergy = Float.infinity
                var minIdx = 0
                for i in 0..<(searchRegion.count - minWindowSamples) {
                    let window = searchRegion[i..<(i + minWindowSamples)]
                    let energy = window.reduce(0.0) { $0 + $1 * $1 } / Float(minWindowSamples)
                    if energy < minEnergy {
                        minEnergy = energy
                        minIdx = i
                    }
                }
                cutSample = searchStart + minIdx + minWindowSamples / 2
            }

            // Ensure progress
            cutSample = max(cutSample, startSample + sampleRate)

            let chunk = Array(audio[startSample..<cutSample])
            let offset = Float(startSample) / Float(sampleRate)
            chunks.append((chunk, offset))
            startSample = cutSample
        }

        return chunks
    }

    /// Parse timestamps from generated text.
    public static func parseTimestamps(text: String) -> [TranscriptSegment] {
        var segments: [TranscriptSegment] = []

        let pattern = "<\\|(\\d{2}):(\\d{2}):(\\d{2})\\|>([^<]*)"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return segments
        }

        let nsText = text as NSString
        let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsText.length))

        var currentStart: Float = 0.0
        var currentText = ""

        for match in matches {
            if match.numberOfRanges >= 5 {
                let hoursStr = nsText.substring(with: match.range(at: 1))
                let minutesStr = nsText.substring(with: match.range(at: 2))
                let secondsStr = nsText.substring(with: match.range(at: 3))
                let segmentText = nsText.substring(with: match.range(at: 4)).trimmingCharacters(in: .whitespacesAndNewlines)

                if let hours = Float(hoursStr), let minutes = Float(minutesStr), let seconds = Float(secondsStr) {
                    let timestamp = hours * 3600 + minutes * 60 + seconds

                    if !currentText.isEmpty {
                        segments.append(TranscriptSegment(text: currentText, start: currentStart, end: timestamp))
                    }

                    currentStart = timestamp
                    currentText = segmentText
                }
            }
        }

        if !currentText.isEmpty {
            segments.append(TranscriptSegment(text: currentText, start: currentStart, end: currentStart + 1.0))
        }

        return segments
    }

    /// Generate transcription from audio features.
    public func generate(
        audio: [Float],
        maxTokens: Int = 1024,
        temperature: Float = 0.0
    ) throws -> STTOutput {
        guard let tokenizer = tokenizer else {
            throw STTError.modelNotInitialized("Tokenizer not loaded")
        }

        let startTime = Date()

        let audioArray = MLXArray(audio)
        let mel = preprocessAudio(audioArray)

        let audioFeatures = audioTower(mel)
        eval(audioFeatures)

        let audioLen = audioFeatures.shape[0]
        var tokens = [config.audioStartTokenId]
        tokens.append(contentsOf: Array(repeating: config.audioTokenId, count: audioLen))
        tokens.append(config.audioEndTokenId)

        let inputIds = MLXArray(tokens.map { Int32($0) }).expandedDimensions(axis: 0)
        let promptTokenCount = inputIds.shape[1]

        let cache = makeCache()
        var logits = self(mel, inputIds, cache: cache)
        eval(logits)

        var generatedTokens: [Int] = []
        let eosTokenId = tokenizer.eosTokenId ?? 151643

        for _ in 0..<maxTokens {
            var lastLogits = logits[0..., -1, 0...]
            if temperature > 0 {
                lastLogits = lastLogits / temperature
            }

            let nextToken = lastLogits.argMax(axis: -1).item(Int.self)

            if nextToken == eosTokenId {
                break
            }

            generatedTokens.append(nextToken)

            let nextTokenArray = MLXArray([Int32(nextToken)]).expandedDimensions(axis: 0)
            let emptyFeatures = MLXArray.zeros([0, config.audioConfig.outputDim])
            var hiddenStates = textModel.embedTokens(nextTokenArray)

            for (i, layer) in textModel.layers.enumerated() {
                hiddenStates = layer(hiddenStates, cache: cache[i])
            }
            hiddenStates = textModel.norm(hiddenStates)
            logits = lmHead(hiddenStates)
            eval(logits)
        }

        let endTime = Date()
        Memory.clearCache()

        let text = tokenizer.decode(tokens: generatedTokens)
        let segments = Qwen3ASRModel.parseTimestamps(text: text)
        let totalTime = endTime.timeIntervalSince(startTime)

        return STTOutput(
            text: text.trimmingCharacters(in: .whitespacesAndNewlines),
            segments: segments.map { segment in
                ["text": segment.text, "start": segment.start, "end": segment.end]
            },
            language: nil,
            promptTokens: promptTokenCount,
            generationTokens: generatedTokens.count,
            totalTokens: promptTokenCount + generatedTokens.count,
            promptTps: Double(promptTokenCount) / totalTime,
            generationTps: Double(generatedTokens.count) / totalTime,
            totalTime: totalTime,
            peakMemoryUsage: Double(Memory.peakMemory) / 1e9
        )
    }

    /// Generate streaming transcription.
    public func generateStream(
        audio: [Float],
        maxTokens: Int = 1024,
        temperature: Float = 0.0
    ) -> AsyncThrowingStream<STTGeneration, Error> {
        return AsyncThrowingStream { continuation in
            Task { @Sendable in
                do {
                    guard let tokenizer = self.tokenizer else {
                        throw STTError.modelNotInitialized("Tokenizer not loaded")
                    }

                    let startTime = Date()

                    let audioArray = MLXArray(audio)
                    let mel = self.preprocessAudio(audioArray)

                    let audioFeatures = self.audioTower(mel)
                    eval(audioFeatures)

                    let prefillEndTime = Date()
                    let prefillTime = prefillEndTime.timeIntervalSince(startTime)

                    let audioLen = audioFeatures.shape[0]
                    var tokens = [self.config.audioStartTokenId]
                    tokens.append(contentsOf: Array(repeating: self.config.audioTokenId, count: audioLen))
                    tokens.append(self.config.audioEndTokenId)

                    let inputIds = MLXArray(tokens.map { Int32($0) }).expandedDimensions(axis: 0)
                    let promptTokenCount = inputIds.shape[1]

                    let cache = self.makeCache()
                    var logits = self(mel, inputIds, cache: cache)
                    eval(logits)

                    let generateStartTime = Date()
                    var generatedTokens: [Int] = []
                    let eosTokenId = tokenizer.eosTokenId ?? 151643

                    for _ in 0..<maxTokens {
                        var lastLogits = logits[0..., -1, 0...]
                        if temperature > 0 {
                            lastLogits = lastLogits / temperature
                        }

                        let nextToken = lastLogits.argMax(axis: -1).item(Int.self)

                        if nextToken == eosTokenId {
                            break
                        }

                        generatedTokens.append(nextToken)

                        let tokenText = tokenizer.decode(tokens: [nextToken])
                        continuation.yield(.token(tokenText))

                        let nextTokenArray = MLXArray([Int32(nextToken)]).expandedDimensions(axis: 0)
                        var hiddenStates = self.textModel.embedTokens(nextTokenArray)

                        for (i, layer) in self.textModel.layers.enumerated() {
                            hiddenStates = layer(hiddenStates, cache: cache[i])
                        }
                        hiddenStates = self.textModel.norm(hiddenStates)
                        logits = self.lmHead(hiddenStates)
                        eval(logits)
                    }

                    let endTime = Date()
                    let generateTime = endTime.timeIntervalSince(generateStartTime)
                    let totalTime = endTime.timeIntervalSince(startTime)

                    Memory.clearCache()

                    let tokensPerSecond = generateTime > 0 ? Double(generatedTokens.count) / generateTime : 0
                    let peakMemory = Double(Memory.peakMemory) / 1e9
                    let info = STTGenerationInfo(
                        promptTokenCount: promptTokenCount,
                        generationTokenCount: generatedTokens.count,
                        prefillTime: prefillTime,
                        generateTime: generateTime,
                        tokensPerSecond: tokensPerSecond,
                        peakMemoryUsage: peakMemory
                    )
                    continuation.yield(.info(info))

                    let text = tokenizer.decode(tokens: generatedTokens)
                    let segments = Qwen3ASRModel.parseTimestamps(text: text)
                    let output = STTOutput(
                        text: text.trimmingCharacters(in: .whitespacesAndNewlines),
                        segments: segments.map { segment in
                            ["text": segment.text, "start": segment.start, "end": segment.end]
                        },
                        language: nil,
                        promptTokens: promptTokenCount,
                        generationTokens: generatedTokens.count,
                        totalTokens: promptTokenCount + generatedTokens.count,
                        promptTps: Double(promptTokenCount) / prefillTime,
                        generationTps: tokensPerSecond,
                        totalTime: totalTime,
                        peakMemoryUsage: peakMemory
                    )
                    continuation.yield(.result(output))

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    /// Load model from pretrained weights.
    public static func fromPretrained(modelPath: String) async throws -> Qwen3ASRModel {
        let client = HubClient.default
        let cache = client.cache ?? HubCache.default

        guard let repoID = Repo.ID(rawValue: modelPath) else {
            throw NSError(
                domain: "Qwen3ASRModel",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Invalid repository ID: \(modelPath)"]
            )
        }

        let modelDir = try await resolveOrDownloadModel(
            client: client,
            cache: cache,
            repoID: repoID
        )

        let configPath = modelDir.appendingPathComponent("config.json")
        let configData = try Data(contentsOf: configPath)
        let config = try JSONDecoder().decode(Qwen3ASRModelConfig.self, from: configData)

        let model = Qwen3ASRModel(config: config)

        model.tokenizer = try await AutoTokenizer.from(modelFolder: modelDir)

        var weights: [String: MLXArray] = [:]
        let fileManager = FileManager.default
        let files = try fileManager.contentsOfDirectory(at: modelDir, includingPropertiesForKeys: nil)
        let safetensorFiles = files.filter { $0.pathExtension == "safetensors" }

        for file in safetensorFiles {
            let fileWeights = try MLX.loadArrays(url: file)
            weights.merge(fileWeights) { _, new in new }
        }

        let sanitizedWeights = sanitize(weights: weights)
        try model.update(parameters: ModuleParameters.unflattened(sanitizedWeights), verify: [.all])

        eval(model)

        return model
    }

    /// Preprocess audio to mel spectrogram.
    public func preprocessAudio(_ audio: MLXArray) -> MLXArray {
        let nMels = config.audioConfig.numMelBins

        if audio.ndim == 3 {
            return audio
        }

        let melSpec = MLXAudioCore.computeMelSpectrogram(
            audio: audio,
            sampleRate: 16000,
            nFft: 400,
            hopLength: 160,
            nMels: nMels
        )

        return melSpec.expandedDimensions(axis: 0)
    }

    /// Create KV cache for generation.
    public func makeCache() -> [KVCacheSimple] {
        return (0..<config.textConfig.numHiddenLayers).map { _ in
            KVCacheSimple()
        }
    }

    private static func resolveOrDownloadModel(
        client: HubClient,
        cache: HubCache,
        repoID: Repo.ID
    ) async throws -> URL {
        let modelSubdir = repoID.description.replacingOccurrences(of: "/", with: "_")
        let modelDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("mlx-audio")
            .appendingPathComponent(modelSubdir)

        let configPath = modelDir.appendingPathComponent("config.json")
        if FileManager.default.fileExists(atPath: configPath.path) {
            let files = try? FileManager.default.contentsOfDirectory(at: modelDir, includingPropertiesForKeys: nil)
            let hasSafetensors = files?.contains { $0.pathExtension == "safetensors" } ?? false

            if hasSafetensors {
                print("Using cached model at: \(modelDir.path)")
                return modelDir
            }
        }

        try FileManager.default.createDirectory(at: modelDir, withIntermediateDirectories: true)

        print("Downloading model \(repoID)...")
        _ = try await client.downloadSnapshot(
            of: repoID,
            kind: .model,
            to: modelDir,
            revision: "main",
            progressHandler: { progress in
                print("\(progress.completedUnitCount)/\(progress.totalUnitCount) files")
            }
        )

        print("Model downloaded to: \(modelDir.path)")
        return modelDir
    }
}
