//
//  WhisperLayers.swift
//  MLXAudioSTT
//
//  Whisper neural network layers matching mlx-audio Python implementation.
//

import Foundation
import MLX
import MLXNN

// MARK: - Sinusoidal Position Embeddings

/// Generate sinusoidal positional embeddings.
func sinusoids(length: Int, channels: Int, maxTimescale: Float = 10000.0) -> MLXArray {
    assert(channels % 2 == 0, "channels must be even")
    let logTimescaleIncrement = log(maxTimescale) / Float(channels / 2 - 1)
    let invTimescales = MLX.exp(-logTimescaleIncrement * MLXArray(0..<(channels / 2)))
    let scaledTime = MLXArray(0..<length).expandedDimensions(axis: 1) * invTimescales.expandedDimensions(axis: 0)
    return MLX.concatenated([MLX.sin(scaledTime), MLX.cos(scaledTime)], axis: 1)
}

// MARK: - Multi-Head Attention

/// Multi-head attention for Whisper.
public class WhisperMultiHeadAttention: Module {
    let nState: Int
    let nHead: Int

    @ModuleInfo(key: "query") var query: Linear
    @ModuleInfo(key: "key") var key: Linear
    @ModuleInfo(key: "value") var value: Linear
    @ModuleInfo(key: "out") var out: Linear

    public init(nState: Int, nHead: Int) {
        self.nState = nState
        self.nHead = nHead

        self._query.wrappedValue = Linear(nState, nState, bias: true)
        self._key.wrappedValue = Linear(nState, nState, bias: false)
        self._value.wrappedValue = Linear(nState, nState, bias: true)
        self._out.wrappedValue = Linear(nState, nState, bias: true)
    }

    /// Forward pass with optional cross-attention.
    ///
    /// - Parameters:
    ///   - x: Query input, shape (batch, n_ctx, n_state)
    ///   - xa: Optional cross-attention input (encoder output), shape (batch, n_audio_ctx, n_state)
    ///   - mask: Optional attention mask
    ///   - kvCache: Optional KV cache tuple (k, v)
    /// - Returns: Tuple of (output, updated_kv_cache, attention_weights)
    public func callAsFunction(
        _ x: MLXArray,
        xa: MLXArray? = nil,
        mask: MLXArray? = nil,
        kvCache: (MLXArray, MLXArray)? = nil
    ) -> (MLXArray, (MLXArray, MLXArray), MLXArray?) {
        let q = query(x)

        var k: MLXArray
        var v: MLXArray

        // Self-attention or cross-attention
        if let xa = xa {
            // Cross-attention: use xa for keys and values
            if let kvCache = kvCache {
                // Use cached keys and values
                k = kvCache.0
                v = kvCache.1
            } else {
                // Compute keys and values from xa
                k = key(xa)
                v = value(xa)
            }
        } else {
            // Self-attention: compute from x
            k = key(x)
            v = value(x)

            // Update cache if provided
            if let kvCache = kvCache {
                k = MLX.concatenated([kvCache.0, k], axis: 1)
                v = MLX.concatenated([kvCache.1, v], axis: 1)
            }
        }

        let (wv, qk) = qkvAttention(q: q, k: k, v: v, mask: mask)
        return (out(wv), (k, v), qk)
    }

    /// QKV attention computation.
    private func qkvAttention(q: MLXArray, k: MLXArray, v: MLXArray, mask: MLXArray?) -> (MLXArray, MLXArray) {
        let nBatch = q.shape[0]
        let nCtx = q.shape[1]
        let nState = q.shape[2]

        let scale = pow(Float(nState / nHead), -0.25)

        // Reshape and transpose: (batch, ctx, state) -> (batch, head, ctx, head_dim)
        let qReshaped = q.reshaped([nBatch, nCtx, nHead, nState / nHead]).transposed(0, 2, 1, 3) * scale
        let kReshaped = k.reshaped([nBatch, k.shape[1], nHead, nState / nHead]).transposed(0, 2, 3, 1) * scale
        let vReshaped = v.reshaped([nBatch, v.shape[1], nHead, nState / nHead]).transposed(0, 2, 1, 3)

        // Compute attention scores
        var qk = MLX.matmul(qReshaped, kReshaped)

        // Apply mask if provided
        if let mask = mask {
            let maskSlice = mask[0..<nCtx, 0..<nCtx]
            qk = qk + maskSlice
        }

        // Softmax and apply to values
        let w = MLX.softmax(qk, axis: -1)
        let outTransposed = MLX.matmul(w, vReshaped).transposed(0, 2, 1, 3)
        let output = outTransposed.reshaped([nBatch, nCtx, nState])

        return (output, qk)
    }
}

// MARK: - Residual Attention Block

/// Residual attention block with optional cross-attention.
public class ResidualAttentionBlock: Module {
    let nState: Int
    let crossAttention: Bool

    @ModuleInfo(key: "attn") var attn: WhisperMultiHeadAttention
    @ModuleInfo(key: "attn_ln") var attnLn: LayerNorm

    @ModuleInfo(key: "cross_attn") var crossAttn: WhisperMultiHeadAttention?
    @ModuleInfo(key: "cross_attn_ln") var crossAttnLn: LayerNorm?

    @ModuleInfo(key: "mlp1") var mlp1: Linear
    @ModuleInfo(key: "mlp2") var mlp2: Linear
    @ModuleInfo(key: "mlp_ln") var mlpLn: LayerNorm

    public init(nState: Int, nHead: Int, crossAttention: Bool = false) {
        self.nState = nState
        self.crossAttention = crossAttention

        self._attn.wrappedValue = WhisperMultiHeadAttention(nState: nState, nHead: nHead)
        self._attnLn.wrappedValue = LayerNorm(dimensions: nState)

        if crossAttention {
            self._crossAttn.wrappedValue = WhisperMultiHeadAttention(nState: nState, nHead: nHead)
            self._crossAttnLn.wrappedValue = LayerNorm(dimensions: nState)
        }

        let nMlp = nState * 4
        self._mlp1.wrappedValue = Linear(nState, nMlp)
        self._mlp2.wrappedValue = Linear(nMlp, nState)
        self._mlpLn.wrappedValue = LayerNorm(dimensions: nState)
    }

    public func callAsFunction(
        _ x: MLXArray,
        xa: MLXArray? = nil,
        mask: MLXArray? = nil,
        kvCache: ((MLXArray, MLXArray)?, (MLXArray, MLXArray)?)? = nil
    ) -> (MLXArray, ((MLXArray, MLXArray)?, (MLXArray, MLXArray)?), MLXArray?) {
        let (selfKv, crossKv) = kvCache ?? (nil, nil)

        // Self-attention
        let (y, updatedSelfKv, _) = attn(attnLn(x), mask: mask, kvCache: selfKv)
        var h = x + y

        // Cross-attention (if enabled)
        var updatedCrossKv: (MLXArray, MLXArray)? = crossKv
        var crossQk: MLXArray? = nil
        if crossAttention, let crossAttn = crossAttn, let crossAttnLn = crossAttnLn {
            let (crossY, newCrossKv, newCrossQk) = crossAttn(crossAttnLn(h), xa: xa, kvCache: crossKv)
            h = h + crossY
            updatedCrossKv = newCrossKv
            crossQk = newCrossQk
        }

        // MLP
        h = h + mlp2(gelu(mlp1(mlpLn(h))))

        return (h, (updatedSelfKv, updatedCrossKv), crossQk)
    }
}

// MARK: - Audio Encoder

/// Whisper audio encoder.
public class WhisperAudioEncoder: Module {
    let config: ModelDimensions
    let positionalEmbedding: MLXArray

    @ModuleInfo(key: "conv1") var conv1: Conv1d
    @ModuleInfo(key: "conv2") var conv2: Conv1d
    @ModuleInfo(key: "blocks") var blocks: [ResidualAttentionBlock]
    @ModuleInfo(key: "ln_post") var lnPost: LayerNorm

    public init(config: ModelDimensions, dtype: DType = .float16) {
        self.config = config

        self._conv1.wrappedValue = Conv1d(
            inputChannels: config.nMels,
            outputChannels: config.nAudioState,
            kernelSize: 3,
            padding: 1
        )
        self._conv2.wrappedValue = Conv1d(
            inputChannels: config.nAudioState,
            outputChannels: config.nAudioState,
            kernelSize: 3,
            stride: 2,
            padding: 1
        )

        // Compute sinusoidal positional embeddings
        self.positionalEmbedding = sinusoids(
            length: config.nAudioCtx,
            channels: config.nAudioState
        ).asType(dtype)

        var encoderBlocks: [ResidualAttentionBlock] = []
        for _ in 0..<config.nAudioLayer {
            encoderBlocks.append(ResidualAttentionBlock(
                nState: config.nAudioState,
                nHead: config.nAudioHead,
                crossAttention: false
            ))
        }
        self._blocks.wrappedValue = encoderBlocks
        self._lnPost.wrappedValue = LayerNorm(dimensions: config.nAudioState)
    }

    public func callAsFunction(_ x: MLXArray) -> MLXArray {
        // Input: (batch, n_mels, n_frames)
        var h = gelu(conv1(x))
        h = gelu(conv2(h))
        // After conv2 with stride 2: (batch, n_audio_state, n_frames/2)

        // Transpose to (batch, seq_len, hidden): (batch, n_frames/2, n_audio_state)
        h = h.transposed(0, 2, 1)

        // Add positional embeddings
        assert(h.shape[1] == positionalEmbedding.shape[0], "incorrect audio shape")
        h = h + positionalEmbedding

        // Apply encoder blocks
        for block in blocks {
            let (output, _, _) = block(h)
            h = output
        }

        return lnPost(h)
    }
}

// MARK: - Text Decoder

/// Whisper text decoder.
public class WhisperTextDecoder: Module {
    let config: ModelDimensions
    let mask: MLXArray

    @ModuleInfo(key: "token_embedding") var tokenEmbedding: Embedding
    @ModuleInfo(key: "positional_embedding") var positionalEmbedding: MLXArray
    @ModuleInfo(key: "blocks") var blocks: [ResidualAttentionBlock]
    @ModuleInfo(key: "ln") var ln: LayerNorm

    public init(config: ModelDimensions, dtype: DType = .float16) {
        self.config = config

        // Create causal mask (local computation, doesn't need super.init)
        let ones = MLXArray.ones([config.nTextCtx, config.nTextCtx])
        let triangular = MLX.tril(ones)
        let inverted = (1.0 - triangular) * Float(-1e9)
        self.mask = inverted.asType(dtype)

        self._tokenEmbedding.wrappedValue = Embedding(
            embeddingCount: config.nVocab,
            dimensions: config.nTextState
        )

        // Learned positional embeddings (initialized to zeros, loaded from weights)
        self._positionalEmbedding.wrappedValue = MLXArray.zeros([config.nTextCtx, config.nTextState])

        var decoderBlocks: [ResidualAttentionBlock] = []
        for _ in 0..<config.nTextLayer {
            decoderBlocks.append(ResidualAttentionBlock(
                nState: config.nTextState,
                nHead: config.nTextHead,
                crossAttention: true
            ))
        }
        self._blocks.wrappedValue = decoderBlocks
        self._ln.wrappedValue = LayerNorm(dimensions: config.nTextState)
    }

    /// Forward pass.
    ///
    /// - Parameters:
    ///   - x: Token IDs, shape (batch, seq_len)
    ///   - xa: Encoder output, shape (batch, n_audio_ctx, n_audio_state)
    ///   - kvCache: Optional list of KV caches for each block
    /// - Returns: Tuple of (logits, updated_kv_cache, cross_attention_weights)
    public func callAsFunction(
        _ x: MLXArray,
        xa: MLXArray,
        kvCache: [((MLXArray, MLXArray)?, (MLXArray, MLXArray)?)]? = nil
    ) -> (MLXArray, [((MLXArray, MLXArray)?, (MLXArray, MLXArray)?)], [MLXArray?]) {
        let offset = kvCache?[0].0?.0.shape[1] ?? 0
        let seqLen = x.shape[x.ndim - 1]

        // Embed tokens and add positional embeddings
        let posSlice = positionalEmbedding[offset..<(offset + seqLen)]
        var h = tokenEmbedding(x) + posSlice

        // Initialize cache if not provided
        var updatedKvCache: [((MLXArray, MLXArray)?, (MLXArray, MLXArray)?)] = kvCache ?? Array(repeating: (nil, nil), count: blocks.count)
        var crossQk: [MLXArray?] = Array(repeating: nil, count: blocks.count)

        // Apply decoder blocks
        for (i, block) in blocks.enumerated() {
            let (output, newCache, newCrossQk) = block(h, xa: xa, mask: mask, kvCache: updatedKvCache[i])
            h = output
            updatedKvCache[i] = newCache
            crossQk[i] = newCrossQk
        }

        h = ln(h)

        // Project to vocabulary using token embedding as linear layer
        let logits = tokenEmbedding.asLinear(h)

        return (logits, updatedKvCache, crossQk)
    }
}
