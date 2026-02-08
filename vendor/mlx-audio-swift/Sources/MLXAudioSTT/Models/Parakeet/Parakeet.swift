//
//  Parakeet.swift
//  MLXAudioSTT
//
//  Parakeet STT model variants (TDT, RNNT, CTC, TDTCTC).
//

import Foundation
import MLX
import MLXNN
import HuggingFace

// MARK: - Base Model

/// Base Parakeet model with factory method.
open class ParakeetModel: Module {
    /// Create model from configuration dictionary.
    ///
    /// Factory dispatches based on config structure:
    /// - Config with "durations" key -> ParakeetTDT
    /// - Config with "joint" key but no "durations" -> ParakeetRNNT
    /// - Config with "decoder" key but no "joint" -> ParakeetCTC
    ///
    /// - Parameter config: Configuration dictionary
    /// - Returns: Appropriate Parakeet model variant
    public static func fromConfig(_ config: [String: Any]) throws -> ParakeetModel {
        if config["durations"] != nil {
            // TDT model
            let data = try JSONSerialization.data(withJSONObject: config)
            let args = try JSONDecoder().decode(ParakeetTDTArgs.self, from: data)
            return ParakeetTDT(args: args)
        } else if config["joint"] != nil {
            // RNNT model
            let data = try JSONSerialization.data(withJSONObject: config)
            let args = try JSONDecoder().decode(ParakeetRNNTArgs.self, from: data)
            return ParakeetRNNT(args: args)
        } else if config["decoder"] != nil {
            // CTC model
            let data = try JSONSerialization.data(withJSONObject: config)
            let args = try JSONDecoder().decode(ParakeetCTCArgs.self, from: data)
            return ParakeetCTC(args: args)
        } else {
            throw NSError(
                domain: "ParakeetModel",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Unknown Parakeet model configuration"]
            )
        }
    }

    /// Generate transcription from audio (implemented by subclasses).
    open func generate(audio: MLXArray) -> STTOutput {
        fatalError("generate() must be implemented by subclass")
    }

    /// Load model from pretrained weights.
    public static func fromPretrained(_ modelPath: String) async throws -> ParakeetModel {
        let client = HubClient.default
        let cache = client.cache ?? HubCache.default

        guard let repoID = Repo.ID(rawValue: modelPath) else {
            throw NSError(
                domain: "ParakeetModel",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Invalid repository ID: \(modelPath)"]
            )
        }

        let modelDir = try await resolveOrDownloadModel(client: client, cache: cache, repoID: repoID)

        // Load config
        let configPath = modelDir.appendingPathComponent("config.json")
        let configData = try Data(contentsOf: configPath)
        guard let configDict = try JSONSerialization.jsonObject(with: configData) as? [String: Any] else {
            throw NSError(domain: "ParakeetModel", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid config format"])
        }

        // Create model from config
        let model = try fromConfig(configDict)

        // Load weights
        var weights: [String: MLXArray] = [:]
        let fileManager = FileManager.default
        let files = try fileManager.contentsOfDirectory(at: modelDir, includingPropertiesForKeys: nil)
        let safetensorFiles = files.filter { $0.pathExtension == "safetensors" }

        for file in safetensorFiles {
            let fileWeights = try MLX.loadArrays(url: file)
            weights.merge(fileWeights) { _, new in new }
        }

        // Load weights into model
        try model.update(parameters: ModuleParameters.unflattened(weights), verify: [.all])
        eval(model)

        return model
    }

    private static func resolveOrDownloadModel(client: HubClient, cache: HubCache, repoID: Repo.ID) async throws -> URL {
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

// MARK: - Parakeet TDT

/// Parakeet Token-and-Duration Transducer.
public class ParakeetTDT: ParakeetModel {
    public let args: ParakeetTDTArgs

    @ModuleInfo(key: "conformer") var conformer: Conformer
    @ModuleInfo(key: "predict") var predict: PredictNetwork
    @ModuleInfo(key: "joint") var joint: JointNetwork

    public init(args: ParakeetTDTArgs) {
        self.args = args
        self._conformer.wrappedValue = Conformer(args: args.conformer)
        self._predict.wrappedValue = PredictNetwork(args: args.predict)
        self._joint.wrappedValue = JointNetwork(args: args.joint)
    }

    public override func generate(audio: MLXArray) -> STTOutput {
        let startTime = Date()

        // Preprocess audio to mel spectrogram
        let mel = logMelSpectrogram(audio: audio, args: args.preprocess)

        // Add batch dimension if needed
        let melBatched = mel.ndim == 2 ? mel.expandedDimensions(axis: 0).expandedDimensions(axis: 0) : mel

        // Encode audio
        let encOut = conformer(melBatched)
        eval(encOut)

        // TDT greedy decoding
        let tokens = greedyTDTDecode(encOut: encOut)

        // Convert tokens to text
        let text = tokens.map { args.labels[$0] }.joined()

        // Create aligned result (simplified - no word-level timing in this version)
        let alignedTokens = tokens.map { tokenIdx in
            AlignedToken(token: args.labels[tokenIdx], start: 0, end: 0)
        }
        let sentence = AlignedSentence(tokens: alignedTokens, text: text, start: 0, end: 0)
        let aligned = AlignedResult(sentences: [sentence])

        let endTime = Date()
        let totalTime = endTime.timeIntervalSince(startTime)

        return STTOutput(
            text: text,
            segments: aligned.toSTTOutput(),
            language: nil,
            promptTokens: encOut.size,
            generationTokens: tokens.count,
            totalTokens: encOut.size + tokens.count,
            promptTps: Double(encOut.size) / totalTime,
            generationTps: Double(tokens.count) / totalTime,
            totalTime: totalTime,
            peakMemoryUsage: Double(Memory.peakMemory) / 1e9
        )
    }

    private func greedyTDTDecode(encOut: MLXArray) -> [Int] {
        var tokens: [Int] = []
        let blankIdx = args.labels.count
        var predState: LSTMState? = nil

        let T = encOut.dim(1)
        var t = 0

        while t < T {
            // Predict next token
            let lastToken = tokens.isEmpty ? blankIdx : tokens.last!
            let predInput = MLXArray(Int32(lastToken)).expandedDimensions(axis: 0).expandedDimensions(axis: 0)
            let (predOut, newState) = predict(predInput, state: predState)
            predState = newState

            // Joint network
            let encFrame = encOut[0, t, 0...].expandedDimensions(axis: 0).expandedDimensions(axis: 0)
            let logits = joint(encFrame, predOut: predOut)

            // Sample token
            let tokenIdx = logits[0, 0, 0...].argMax().item(Int.self)

            if tokenIdx == blankIdx {
                // Blank - advance time
                t += 1
            } else if args.durations.contains(tokenIdx) {
                // Duration token - advance time by duration
                let durationSteps = args.durations.firstIndex(of: tokenIdx) ?? 0
                t += max(1, durationSteps)
            } else {
                // Regular token
                tokens.append(tokenIdx)
            }
        }

        return tokens
    }
}

// MARK: - Parakeet RNNT

/// Parakeet standard RNN-Transducer.
public class ParakeetRNNT: ParakeetModel {
    public let args: ParakeetRNNTArgs

    @ModuleInfo(key: "conformer") var conformer: Conformer
    @ModuleInfo(key: "predict") var predict: PredictNetwork
    @ModuleInfo(key: "joint") var joint: JointNetwork

    public init(args: ParakeetRNNTArgs) {
        self.args = args
        self._conformer.wrappedValue = Conformer(args: args.conformer)
        self._predict.wrappedValue = PredictNetwork(args: args.predict)
        self._joint.wrappedValue = JointNetwork(args: args.joint)
    }

    public override func generate(audio: MLXArray) -> STTOutput {
        let startTime = Date()

        let mel = logMelSpectrogram(audio: audio, args: args.preprocess)
        let melBatched = mel.ndim == 2 ? mel.expandedDimensions(axis: 0).expandedDimensions(axis: 0) : mel
        let encOut = conformer(melBatched)
        eval(encOut)

        let tokens = greedyRNNTDecode(encOut: encOut)
        let text = tokens.map { args.labels[$0] }.joined()

        let alignedTokens = tokens.map { tokenIdx in
            AlignedToken(token: args.labels[tokenIdx], start: 0, end: 0)
        }
        let sentence = AlignedSentence(tokens: alignedTokens, text: text, start: 0, end: 0)
        let aligned = AlignedResult(sentences: [sentence])

        let endTime = Date()
        let totalTime = endTime.timeIntervalSince(startTime)

        return STTOutput(
            text: text,
            segments: aligned.toSTTOutput(),
            language: nil,
            promptTokens: encOut.size,
            generationTokens: tokens.count,
            totalTokens: encOut.size + tokens.count,
            promptTps: Double(encOut.size) / totalTime,
            generationTps: Double(tokens.count) / totalTime,
            totalTime: totalTime,
            peakMemoryUsage: Double(Memory.peakMemory) / 1e9
        )
    }

    private func greedyRNNTDecode(encOut: MLXArray) -> [Int] {
        var tokens: [Int] = []
        let blankIdx = args.labels.count
        var predState: LSTMState? = nil

        let T = encOut.dim(1)

        for t in 0..<T {
            var emittingToken = true

            while emittingToken {
                let lastToken = tokens.isEmpty ? blankIdx : tokens.last!
                let predInput = MLXArray(Int32(lastToken)).expandedDimensions(axis: 0).expandedDimensions(axis: 0)
                let (predOut, newState) = predict(predInput, state: predState)
                predState = newState

                let encFrame = encOut[0, t, 0...].expandedDimensions(axis: 0).expandedDimensions(axis: 0)
                let logits = joint(encFrame, predOut: predOut)
                let tokenIdx = logits[0, 0, 0...].argMax().item(Int.self)

                if tokenIdx == blankIdx {
                    emittingToken = false
                } else {
                    tokens.append(tokenIdx)
                }
            }
        }

        return tokens
    }
}

// MARK: - Parakeet CTC

/// Parakeet CTC greedy decoder.
public class ParakeetCTC: ParakeetModel {
    public let args: ParakeetCTCArgs

    @ModuleInfo(key: "conformer") var conformer: Conformer
    @ModuleInfo(key: "decoder") var decoder: ConvASRDecoder

    public init(args: ParakeetCTCArgs) {
        self.args = args
        self._conformer.wrappedValue = Conformer(args: args.conformer)
        self._decoder.wrappedValue = ConvASRDecoder(args: args.decoder)
    }

    public override func generate(audio: MLXArray) -> STTOutput {
        let startTime = Date()

        let mel = logMelSpectrogram(audio: audio, args: args.preprocess)
        let melBatched = mel.ndim == 2 ? mel.expandedDimensions(axis: 0).expandedDimensions(axis: 0) : mel
        let encOut = conformer(melBatched)
        let logProbs = decoder(encOut)
        eval(logProbs)

        let tokens = greedyCTCDecode(logProbs: logProbs)
        let text = tokens.map { args.labels[$0] }.joined()

        let alignedTokens = tokens.map { tokenIdx in
            AlignedToken(token: args.labels[tokenIdx], start: 0, end: 0)
        }
        let sentence = AlignedSentence(tokens: alignedTokens, text: text, start: 0, end: 0)
        let aligned = AlignedResult(sentences: [sentence])

        let endTime = Date()
        let totalTime = endTime.timeIntervalSince(startTime)

        return STTOutput(
            text: text,
            segments: aligned.toSTTOutput(),
            language: nil,
            promptTokens: encOut.size,
            generationTokens: tokens.count,
            totalTokens: encOut.size + tokens.count,
            promptTps: Double(encOut.size) / totalTime,
            generationTps: Double(tokens.count) / totalTime,
            totalTime: totalTime,
            peakMemoryUsage: Double(Memory.peakMemory) / 1e9
        )
    }

    private func greedyCTCDecode(logProbs: MLXArray) -> [Int] {
        let T = logProbs.dim(1)
        let blankIdx = args.labels.count

        var tokens: [Int] = []
        var lastToken: Int? = nil

        for t in 0..<T {
            let frameLogProbs = logProbs[0, t, 0...]
            let tokenIdx = frameLogProbs.argMax().item(Int.self)

            // CTC: collapse repeats and remove blanks
            if tokenIdx != blankIdx && tokenIdx != lastToken {
                tokens.append(tokenIdx)
            }

            lastToken = tokenIdx
        }

        return tokens
    }
}
