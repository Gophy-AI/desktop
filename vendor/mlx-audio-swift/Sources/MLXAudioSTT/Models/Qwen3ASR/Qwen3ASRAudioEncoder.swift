//
//  Qwen3ASRAudioEncoder.swift
//  MLXAudioSTT
//
// Qwen3 ASR audio encoder with Conv2d frontend.
//

import Foundation
import MLX
import MLXNN
import Accelerate

// MARK: - Audio Encoder

/// Qwen3 ASR Audio Encoder with Conv2d frontend and transformer layers.
public class Qwen3ASRAudioEncoder: Module {
    let config: AudioEncoderConfig
    let embedScale: Float
    let numMelBins: Int
    let maxSourcePositions: Int
    let nWindow: Int

    @ModuleInfo(key: "conv2d1") var conv2d1: Conv2d
    @ModuleInfo(key: "conv2d2") var conv2d2: Conv2d
    @ModuleInfo(key: "conv2d3") var conv2d3: Conv2d
    @ModuleInfo(key: "conv_out") var convOut: Linear
    @ModuleInfo(key: "positional_embedding") var positionalEmbedding: SinusoidalPositionEmbedding
    @ModuleInfo(key: "layers") var layers: [AudioEncoderLayer]
    @ModuleInfo(key: "ln_post") var lnPost: LayerNorm
    @ModuleInfo(key: "proj1") var proj1: Linear
    @ModuleInfo(key: "proj2") var proj2: Linear

    public init(config: AudioEncoderConfig) {
        self.config = config
        let embedDim = config.dModel
        self.numMelBins = config.numMelBins
        self.maxSourcePositions = config.maxSourcePositions
        self.embedScale = config.scaleEmbedding ? sqrt(Float(embedDim)) : 1.0
        self.nWindow = config.nWindow

        // Conv2d frontend: 3 layers with stride=2 each (8x total downsampling)
        self._conv2d1.wrappedValue = Conv2d(
            inputChannels: 1,
            outputChannels: config.downsampleHiddenSize,
            kernelSize: .init((3, 3)),
            stride: .init((2, 2)),
            padding: .init((1, 1))
        )
        self._conv2d2.wrappedValue = Conv2d(
            inputChannels: config.downsampleHiddenSize,
            outputChannels: config.downsampleHiddenSize,
            kernelSize: .init((3, 3)),
            stride: .init((2, 2)),
            padding: .init((1, 1))
        )
        self._conv2d3.wrappedValue = Conv2d(
            inputChannels: config.downsampleHiddenSize,
            outputChannels: config.downsampleHiddenSize,
            kernelSize: .init((3, 3)),
            stride: .init((2, 2)),
            padding: .init((1, 1))
        )

        // Calculate frequency dimension after 3 conv layers
        let freqAfterConv = ((((config.numMelBins + 1) / 2) + 1) / 2 + 1) / 2
        self._convOut.wrappedValue = Linear(config.downsampleHiddenSize * freqAfterConv, embedDim, bias: false)

        self._positionalEmbedding.wrappedValue = SinusoidalPositionEmbedding(
            length: maxSourcePositions,
            channels: embedDim
        )

        self._layers.wrappedValue = (0..<config.encoderLayers).map { _ in
            AudioEncoderLayer(config: config)
        }

        self._lnPost.wrappedValue = LayerNorm(dimensions: embedDim)
        self._proj1.wrappedValue = Linear(embedDim, embedDim)
        self._proj2.wrappedValue = Linear(embedDim, config.outputDim)
    }

    /// Create block attention mask for windowed self-attention.
    private func createBlockAttentionMask(seqLen: Int, cuSeqlens: [Int], dtype: DType) -> MLXArray {
        var mask = MLXArray.full([seqLen, seqLen], values: MLXArray(Float(-1e9)))
        for i in 0..<(cuSeqlens.count - 1) {
            let start = cuSeqlens[i]
            let end = cuSeqlens[i + 1]
            mask[start..<end, start..<end] = MLXArray.zeros([end - start, end - start])
        }
        return mask
    }

    /// Compute output length after Conv2d frontend.
    private func getFeatExtractOutputLengths(_ inputLengths: MLXArray) -> MLXArray {
        let inputLengthsLeave = inputLengths % 100
        let featLengths = floorDiv(inputLengthsLeave - 1, 2) + 1
        let outputLengths = floorDiv(floorDiv(featLengths - 1, 2) + 1 - 1, 2) + 1 + (inputLengths / 100) * 13
        return outputLengths
    }

    private func floorDiv(_ a: MLXArray, _ b: Int) -> MLXArray {
        return MLX.floor(a.asType(.float32) / Float(b)).asType(.int32)
    }

    public func callAsFunction(_ inputFeatures: MLXArray, featureAttentionMask: MLXArray? = nil) -> MLXArray {
        let batchSize = inputFeatures.shape[0]
        let timeSteps = inputFeatures.shape[2]

        let featureLens: MLXArray
        if let mask = featureAttentionMask {
            featureLens = mask.sum(axis: -1).asType(.int32)
        } else {
            featureLens = MLXArray.full([batchSize], values: MLXArray(Int32(timeSteps)))
        }

        let chunkSize = nWindow * 2
        let chunkNum = MLX.ceil(featureLens.asType(.float32) / Float(chunkSize)).asType(.int32)

        // Compute chunk lengths
        var chunkLengths: [Int] = []
        for i in 0..<batchSize {
            let numChunks = Int(chunkNum[i].item(Int.self))
            let featLen = Int(featureLens[i].item(Int.self))
            for j in 0..<numChunks {
                if j == numChunks - 1 {
                    let remainder = featLen % chunkSize
                    chunkLengths.append(remainder == 0 ? chunkSize : remainder)
                } else {
                    chunkLengths.append(chunkSize)
                }
            }
        }

        // Process each sample through Conv2d frontend
        var chunks: [MLXArray] = []
        for i in 0..<batchSize {
            let feat = inputFeatures[i]  // [n_mels, time]
            let featLen = Int(featureLens[i].item(Int.self))

            // Split into chunks
            let numChunks = Int(chunkNum[i].item(Int.self))
            for j in 0..<numChunks {
                let start = j * chunkSize
                let end = min(start + chunkSize, featLen)
                let chunkFeat = feat[0..., start..<end]  // [n_mels, chunk_time]

                // Permute to [chunk_time, n_mels] for Conv2d
                let permuted = chunkFeat.transposed(0, 1)  // [chunk_time, n_mels]
                // Add batch and channel dims: [1, 1, chunk_time, n_mels]
                let input4d = permuted.reshaped([1, 1, permuted.shape[0], permuted.shape[1]])

                // Apply 3 Conv2d layers with GELU
                var h = gelu(conv2d1(input4d))
                h = gelu(conv2d2(h))
                h = gelu(conv2d3(h))

                // h shape: [1, C, T', F']
                // Flatten frequency dimension: [1, T', C*F']
                let timeAfterConv = h.shape[2]
                let freqAfterConv = h.shape[3]
                h = h.transposed(0, 2, 1, 3)  // [1, T', C, F']
                h = h.reshaped([1, timeAfterConv, config.downsampleHiddenSize * freqAfterConv])

                // Project to embed_dim
                h = convOut(h)  // [1, T', embed_dim]

                chunks.append(h[0])  // [T', embed_dim]
            }
        }

        // Concatenate all chunks
        var hiddenStates = MLX.concatenated(chunks, axis: 0)  // [total_T, embed_dim]

        // Add positional embedding
        let seqLen = hiddenStates.shape[0]
        let posEmbed = positionalEmbedding(seqLen)
        hiddenStates = hiddenStates + posEmbed

        // Create block attention mask
        var cuSeqlens = [0]
        for length in chunkLengths {
            // Each chunk is downsampled 8x in time
            let afterCnnLen = ((((length + 1) / 2) + 1) / 2 + 1) / 2
            cuSeqlens.append(cuSeqlens.last! + afterCnnLen)
        }

        let attentionMask = createBlockAttentionMask(
            seqLen: seqLen,
            cuSeqlens: cuSeqlens,
            dtype: hiddenStates.dtype
        )

        // Apply transformer layers
        for layer in layers {
            hiddenStates = layer(hiddenStates, mask: attentionMask)
        }

        // Final layer norm and projection
        hiddenStates = lnPost(hiddenStates)
        hiddenStates = gelu(proj1(hiddenStates))
        hiddenStates = proj2(hiddenStates)

        return hiddenStates
    }
}
