//
//  Qwen3ForcedAligner.swift
//  MLXAudioSTT
//
// Qwen3 Forced Aligner for word-level timestamp alignment.
//

import Foundation
import MLX
import MLXNN
import MLXLMCommon
import MLXAudioCore

// MARK: - Forced Aligner Result

/// Result from forced alignment.
public struct ForcedAlignResult {
    public let items: [ForcedAlignItem]

    public init(items: [ForcedAlignItem]) {
        self.items = items
    }
}

/// A single aligned item (word with timestamps).
public struct ForcedAlignItem {
    public let word: String
    public let start: Float
    public let end: Float

    public init(word: String, start: Float, end: Float) {
        self.word = word
        self.start = start
        self.end = end
    }
}

// MARK: - Force Align Processor

/// Text tokenization processor for forced alignment.
public class ForceAlignProcessor {
    /// Tokenize text for alignment based on language.
    public static func tokenize(_ text: String, language: String = "en") -> [String] {
        // CJK characters: tokenized individually
        if isCJK(text) {
            return Array(text).map { String($0) }
        }

        // Japanese: regex for Katakana/Hiragana grouping
        if language == "ja" {
            return tokenizeJapanese(text)
        }

        // Korean: tokenized by Jamo
        if language == "ko" {
            return tokenizeKorean(text)
        }

        // English/other: whitespace-separated words
        return text.split(separator: " ").map { String($0) }
    }

    private static func isCJK(_ text: String) -> Bool {
        for scalar in text.unicodeScalars {
            let value = scalar.value
            // CJK Unified Ideographs ranges
            if (value >= 0x4E00 && value <= 0x9FFF) ||
               (value >= 0x3400 && value <= 0x4DBF) ||
               (value >= 0x20000 && value <= 0x2A6DF) {
                return true
            }
        }
        return false
    }

    private static func tokenizeJapanese(_ text: String) -> [String] {
        var tokens: [String] = []
        var currentToken = ""

        for char in text {
            let scalar = char.unicodeScalars.first!.value
            // Hiragana (0x3040-0x309F) or Katakana (0x30A0-0x30FF)
            if (scalar >= 0x3040 && scalar <= 0x309F) || (scalar >= 0x30A0 && scalar <= 0x30FF) {
                currentToken.append(char)
            } else {
                if !currentToken.isEmpty {
                    tokens.append(currentToken)
                    currentToken = ""
                }
                if !char.isWhitespace {
                    tokens.append(String(char))
                }
            }
        }

        if !currentToken.isEmpty {
            tokens.append(currentToken)
        }

        return tokens
    }

    private static func tokenizeKorean(_ text: String) -> [String] {
        // Simple split by character for Hangul
        return Array(text).map { String($0) }.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }
}

// MARK: - Timestamp LIS Correction

/// Fix non-monotonic timestamps using Longest Increasing Subsequence.
public func fixTimestampsWithLIS(items: [ForcedAlignItem]) -> [ForcedAlignItem] {
    if items.isEmpty {
        return items
    }

    // Extract timestamps
    let timestamps = items.map { $0.start }

    // Find LIS indices
    let lisIndices = longestIncreasingSubsequence(timestamps)

    // Create fixed items
    var fixedItems = items
    var lisSet = Set(lisIndices)

    // Interpolate non-LIS timestamps
    for i in 0..<items.count {
        if !lisSet.contains(i) {
            // Find previous and next LIS points
            var prevIdx: Int? = nil
            var nextIdx: Int? = nil

            for j in (0..<i).reversed() {
                if lisSet.contains(j) {
                    prevIdx = j
                    break
                }
            }

            for j in (i + 1)..<items.count {
                if lisSet.contains(j) {
                    nextIdx = j
                    break
                }
            }

            // Interpolate
            let newStart: Float
            if let prev = prevIdx, let next = nextIdx {
                let prevTime = items[prev].start
                let nextTime = items[next].start
                let ratio = Float(i - prev) / Float(next - prev)
                newStart = prevTime + ratio * (nextTime - prevTime)
            } else if let prev = prevIdx {
                newStart = items[prev].start + 0.1
            } else if let next = nextIdx {
                newStart = items[next].start - 0.1
            } else {
                newStart = items[i].start
            }

            fixedItems[i] = ForcedAlignItem(
                word: items[i].word,
                start: newStart,
                end: newStart + 0.1
            )
        }
    }

    return fixedItems
}

/// Find Longest Increasing Subsequence indices.
private func longestIncreasingSubsequence(_ arr: [Float]) -> [Int] {
    if arr.isEmpty {
        return []
    }

    var dp: [(value: Float, prevIdx: Int)] = []
    var maxLength = 0
    var maxIdx = 0

    for i in 0..<arr.count {
        var length = 1
        var prevIdx = -1

        for j in 0..<i {
            if arr[j] < arr[i] && dp[j].prevIdx + 1 >= length {
                length = dp[j].prevIdx + 2
                prevIdx = j
            }
        }

        dp.append((arr[i], prevIdx))

        if length > maxLength {
            maxLength = length
            maxIdx = i
        }
    }

    // Reconstruct LIS indices
    var indices: [Int] = []
    var idx = maxIdx
    while idx >= 0 {
        indices.append(idx)
        idx = dp[idx].prevIdx
    }

    return indices.reversed()
}

// MARK: - Forced Aligner Model

/// Forced Aligner model sharing components with Qwen3 ASR.
public class ForcedAlignerModel: Module {
    let config: ForcedAlignerConfig

    @ModuleInfo(key: "audio_tower") var audioTower: Qwen3ASRAudioEncoder
    @ModuleInfo(key: "text_model") var textModel: TextModel
    @ModuleInfo(key: "lm_head") var lmHead: Linear  // classify_num outputs

    public init(config: ForcedAlignerConfig) {
        self.config = config

        self._audioTower.wrappedValue = Qwen3ASRAudioEncoder(config: config.audioConfig)
        self._textModel.wrappedValue = TextModel(config: config.textConfig)
        self._lmHead.wrappedValue = Linear(config.textConfig.hiddenSize, config.classifyNum, bias: false)
    }

    public func callAsFunction(
        _ inputFeatures: MLXArray,
        _ inputIds: MLXArray,
        cache: [KVCacheSimple]? = nil
    ) -> MLXArray {
        // Encode audio features
        let audioFeatures = audioTower(inputFeatures)

        // Embed input tokens
        var hiddenStates = textModel.embedTokens(inputIds)

        // Run through text model layers
        for (i, layer) in textModel.layers.enumerated() {
            let layerCache = cache?[i]
            hiddenStates = layer(hiddenStates, cache: layerCache)
        }

        hiddenStates = textModel.norm(hiddenStates)

        // Generate classification logits for timestamps
        let logits = lmHead(hiddenStates)
        return logits
    }

    /// Generate forced alignment from audio and text.
    public func generate(audio: [Float], text: String) throws -> ForcedAlignResult {
        let words = ForceAlignProcessor.tokenize(text)

        let audioArray = MLXArray(audio)
        let mel = preprocessAudio(audioArray)

        let audioFeatures = audioTower(mel)
        eval(audioFeatures)

        let audioLen = audioFeatures.shape[0]
        var tokens = [config.audioTokenId]
        tokens.append(contentsOf: Array(repeating: config.audioTokenId, count: audioLen))

        let inputIds = MLXArray(tokens.map { Int32($0) }).expandedDimensions(axis: 0)

        let cache = makeCache()
        let logits = self(mel, inputIds, cache: cache)
        eval(logits)

        let timestampProbs = softmax(logits[0..., -1, 0...], axis: -1)

        var items: [ForcedAlignItem] = []
        let audioDuration = Float(audio.count) / 16000.0
        let binDuration = audioDuration / Float(config.classifyNum)

        for (i, word) in words.enumerated() {
            let wordIdx = min(i, timestampProbs.shape[0] - 1)
            let probs = timestampProbs[wordIdx]
            let bin = probs.argMax(axis: -1).item(Int.self)

            let start = Float(bin) * binDuration
            let end = min(start + binDuration, audioDuration)
            items.append(ForcedAlignItem(word: word, start: start, end: end))
        }

        let correctedItems = fixTimestampsWithLIS(items: items)

        return ForcedAlignResult(items: correctedItems)
    }

    /// Load model from pretrained weights.
    public static func fromPretrained(modelPath: String) async throws -> ForcedAlignerModel {
        let modelDirectory = URL(fileURLWithPath: modelPath)

        let configURL = modelDirectory.appendingPathComponent("config.json")
        let configData = try Data(contentsOf: configURL)
        let config = try JSONDecoder().decode(ForcedAlignerConfig.self, from: configData)

        let model = ForcedAlignerModel(config: config)

        var weights: [String: MLXArray] = [:]
        let fileManager = FileManager.default
        let files = try fileManager.contentsOfDirectory(at: modelDirectory, includingPropertiesForKeys: nil)
        let safetensorFiles = files.filter { $0.pathExtension == "safetensors" }

        for file in safetensorFiles {
            let fileWeights = try MLX.loadArrays(url: file)
            weights.merge(fileWeights) { _, new in new }
        }

        let sanitizedWeights = Qwen3ASRModel.sanitize(weights: weights)
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
}
