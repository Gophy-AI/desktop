//
//  VoxtralRealtimeModel.swift
//  MLXAudioSTT
//
// Voxtral Mini 4B Realtime STT model: causal whisper encoder + adaptive-norm language model
// Ported from voxmlx Python implementation

import Foundation
import MLX
import MLXNN
import MLXAudioCore
import MLXLMCommon
import HuggingFace
import Tokenizers
import os.log

// MARK: - Audio Processing Constants

private enum VoxtralRealtimeAudioConstants {
    static let sampleRate = 16000
    static let nFft = 400
    static let hopLength = 160
    static let nMels = 128
    static let globalLogMelMax: Float = 1.5
    /// hop * conv_stride * downsample = 160 * 2 * 4 = 1280
    static let samplesPerToken = hopLength * 2 * 4
}

private let voxtralRealtimeLogger = Logger(subsystem: "com.gophy.mlx-audio", category: "VoxtralRealtime")

// MARK: - Causal Conv1d

/// Left-padded causal 1D convolution.
class VoxtralRealtimeCausalConv1d: Module {
    let stride: Int
    let kernelSize: Int
    let paddingTotal: Int

    @ModuleInfo var weight: MLXArray
    @ModuleInfo var bias: MLXArray

    init(inChannels: Int, outChannels: Int, kernelSize: Int, stride: Int = 1) {
        self.stride = stride
        self.kernelSize = kernelSize
        self.paddingTotal = kernelSize - stride
        self._weight.wrappedValue = MLXArray.zeros([outChannels, kernelSize, inChannels])
        self._bias.wrappedValue = MLXArray.zeros([outChannels])
        super.init()
    }

    func callAsFunction(_ x: MLXArray) -> MLXArray {
        // x: [batch, time, channels] (NHC layout)
        var input = x
        if paddingTotal > 0 {
            input = padded(input, widths: [IntOrPair((0, 0)), IntOrPair((paddingTotal, 0)), IntOrPair((0, 0))])
        }
        return MLX.conv1d(input, weight, stride: stride) + bias
    }
}

// MARK: - Encoder Components

/// Encoder attention with RoPE. q/v/o have bias, k does not.
class VoxtralRealtimeEncoderAttention: Module {
    let nHeads: Int
    let headDim: Int
    let scale: Float
    let ropeTheta: Float

    @ModuleInfo(key: "q_proj") var qProj: Linear
    @ModuleInfo(key: "k_proj") var kProj: Linear
    @ModuleInfo(key: "v_proj") var vProj: Linear
    @ModuleInfo(key: "o_proj") var oProj: Linear

    init(dim: Int = 1280, nHeads: Int = 32, headDim: Int = 64, ropeTheta: Float = 1e6) {
        self.nHeads = nHeads
        self.headDim = headDim
        self.scale = pow(Float(headDim), -0.5)
        self.ropeTheta = ropeTheta

        self._qProj.wrappedValue = Linear(dim, nHeads * headDim, bias: true)
        self._kProj.wrappedValue = Linear(dim, nHeads * headDim, bias: false)
        self._vProj.wrappedValue = Linear(dim, nHeads * headDim, bias: true)
        self._oProj.wrappedValue = Linear(nHeads * headDim, dim, bias: true)
    }

    func callAsFunction(_ x: MLXArray, offset: Int, mask: MLXFast.ScaledDotProductAttentionMaskMode, cache: KVCache? = nil) -> MLXArray {
        let B = x.dim(0)
        let L = x.dim(1)

        var q = qProj(x).reshaped(B, L, nHeads, headDim).transposed(0, 2, 1, 3)
        var k = kProj(x).reshaped(B, L, nHeads, headDim).transposed(0, 2, 1, 3)
        var v = vProj(x).reshaped(B, L, nHeads, headDim).transposed(0, 2, 1, 3)

        let ropeOffset = cache?.offset ?? offset
        q = MLXFast.RoPE(q, dimensions: headDim, traditional: true, base: ropeTheta, scale: 1.0, offset: ropeOffset)
        k = MLXFast.RoPE(k, dimensions: headDim, traditional: true, base: ropeTheta, scale: 1.0, offset: ropeOffset)

        if let cache = cache {
            (k, v) = cache.update(keys: k, values: v)
        }

        let out = MLXFast.scaledDotProductAttention(
            queries: q, keys: k, values: v, scale: scale, mask: mask
        ).transposed(0, 2, 1, 3).reshaped(B, L, -1)

        return oProj(out)
    }
}

/// Encoder SwiGLU MLP. gate/up have no bias, down has bias.
class VoxtralRealtimeEncoderSwiGLU: Module {
    @ModuleInfo(key: "gate_proj") var gateProj: Linear
    @ModuleInfo(key: "up_proj") var upProj: Linear
    @ModuleInfo(key: "down_proj") var downProj: Linear

    init(dim: Int = 1280, hiddenDim: Int = 5120) {
        self._gateProj.wrappedValue = Linear(dim, hiddenDim, bias: false)
        self._upProj.wrappedValue = Linear(dim, hiddenDim, bias: false)
        self._downProj.wrappedValue = Linear(hiddenDim, dim, bias: true)
    }

    func callAsFunction(_ x: MLXArray) -> MLXArray {
        downProj(silu(gateProj(x)) * upProj(x))
    }
}

/// Encoder transformer layer with pre-norm residual connections.
class VoxtralRealtimeEncoderLayer: Module {
    @ModuleInfo(key: "attn_norm") var attnNorm: RMSNorm
    @ModuleInfo(key: "attention") var attention: VoxtralRealtimeEncoderAttention
    @ModuleInfo(key: "ffn_norm") var ffnNorm: RMSNorm
    @ModuleInfo(key: "mlp") var mlp: VoxtralRealtimeEncoderSwiGLU

    init(dim: Int = 1280, nHeads: Int = 32, headDim: Int = 64, hiddenDim: Int = 5120, ropeTheta: Float = 1e6) {
        self._attnNorm.wrappedValue = RMSNorm(dimensions: dim, eps: 1e-5)
        self._attention.wrappedValue = VoxtralRealtimeEncoderAttention(dim: dim, nHeads: nHeads, headDim: headDim, ropeTheta: ropeTheta)
        self._ffnNorm.wrappedValue = RMSNorm(dimensions: dim, eps: 1e-5)
        self._mlp.wrappedValue = VoxtralRealtimeEncoderSwiGLU(dim: dim, hiddenDim: hiddenDim)
    }

    func callAsFunction(_ x: MLXArray, offset: Int, mask: MLXFast.ScaledDotProductAttentionMaskMode, cache: KVCache? = nil) -> MLXArray {
        var h = x + attention(attnNorm(x), offset: offset, mask: mask, cache: cache)
        h = h + mlp(ffnNorm(h))
        return h
    }
}

/// Causal Whisper encoder: conv frontend + transformer layers + final norm.
class VoxtralRealtimeCausalWhisperEncoder: Module {
    @ModuleInfo(key: "conv1") var conv1: VoxtralRealtimeCausalConv1d
    @ModuleInfo(key: "conv2") var conv2: VoxtralRealtimeCausalConv1d
    let layers: [VoxtralRealtimeEncoderLayer]
    @ModuleInfo(key: "norm") var norm: RMSNorm
    let slidingWindow: Int

    init(
        inChannels: Int = 128,
        dim: Int = 1280,
        nLayers: Int = 32,
        nHeads: Int = 32,
        headDim: Int = 64,
        hiddenDim: Int = 5120,
        ropeTheta: Float = 1e6,
        slidingWindow: Int = 750
    ) {
        self._conv1.wrappedValue = VoxtralRealtimeCausalConv1d(inChannels: inChannels, outChannels: dim, kernelSize: 3, stride: 1)
        self._conv2.wrappedValue = VoxtralRealtimeCausalConv1d(inChannels: dim, outChannels: dim, kernelSize: 3, stride: 2)
        self.layers = (0..<nLayers).map { _ in
            VoxtralRealtimeEncoderLayer(dim: dim, nHeads: nHeads, headDim: headDim, hiddenDim: hiddenDim, ropeTheta: ropeTheta)
        }
        self._norm.wrappedValue = RMSNorm(dimensions: dim, eps: 1e-5)
        self.slidingWindow = slidingWindow
    }

    func callAsFunction(_ mel: MLXArray) -> MLXArray {
        // mel: [nMels, T] -> transpose to [1, T, nMels]
        var x = mel.transposed(0, 1).expandedDimensions(axis: 0)
        x = x.asType(conv1.weight.dtype)
        x = gelu(conv1(x))
        x = gelu(conv2(x))
        // x: [1, T/2, dim]

        let mask: MLXFast.ScaledDotProductAttentionMaskMode = .causal
        for layer in layers {
            x = layer(x, offset: 0, mask: mask)
        }
        x = norm(x)
        return x  // [1, T/2, dim]
    }
}

// MARK: - Decoder (Language Model) Components

/// Decoder attention with GQA (grouped query attention). No bias on any projection.
class VoxtralRealtimeDecoderAttention: Module {
    let nHeads: Int
    let nKvHeads: Int
    let headDim: Int
    let scale: Float
    let ropeTheta: Float

    @ModuleInfo(key: "q_proj") var qProj: Linear
    @ModuleInfo(key: "k_proj") var kProj: Linear
    @ModuleInfo(key: "v_proj") var vProj: Linear
    @ModuleInfo(key: "o_proj") var oProj: Linear

    init(dim: Int = 3072, nHeads: Int = 32, nKvHeads: Int = 8, headDim: Int = 128, ropeTheta: Float = 1e6) {
        self.nHeads = nHeads
        self.nKvHeads = nKvHeads
        self.headDim = headDim
        self.scale = pow(Float(headDim), -0.5)
        self.ropeTheta = ropeTheta

        self._qProj.wrappedValue = Linear(dim, nHeads * headDim, bias: false)
        self._kProj.wrappedValue = Linear(dim, nKvHeads * headDim, bias: false)
        self._vProj.wrappedValue = Linear(dim, nKvHeads * headDim, bias: false)
        self._oProj.wrappedValue = Linear(nHeads * headDim, dim, bias: false)
    }

    func callAsFunction(_ x: MLXArray, mask: MLXFast.ScaledDotProductAttentionMaskMode, cache: KVCache? = nil) -> MLXArray {
        let B = x.dim(0)
        let L = x.dim(1)

        var q = qProj(x).reshaped(B, L, nHeads, headDim).transposed(0, 2, 1, 3)
        var k = kProj(x).reshaped(B, L, nKvHeads, headDim).transposed(0, 2, 1, 3)
        var v = vProj(x).reshaped(B, L, nKvHeads, headDim).transposed(0, 2, 1, 3)

        let offset = cache?.offset ?? 0
        q = MLXFast.RoPE(q, dimensions: headDim, traditional: true, base: ropeTheta, scale: 1.0, offset: offset)
        k = MLXFast.RoPE(k, dimensions: headDim, traditional: true, base: ropeTheta, scale: 1.0, offset: offset)

        if let cache = cache {
            (k, v) = cache.update(keys: k, values: v)
        }

        let out = MLXFast.scaledDotProductAttention(
            queries: q, keys: k, values: v, scale: scale, mask: mask
        ).transposed(0, 2, 1, 3).reshaped(B, L, -1)

        return oProj(out)
    }
}

/// Decoder SwiGLU MLP. No bias on any projection.
class VoxtralRealtimeDecoderSwiGLU: Module {
    @ModuleInfo(key: "gate_proj") var gateProj: Linear
    @ModuleInfo(key: "up_proj") var upProj: Linear
    @ModuleInfo(key: "down_proj") var downProj: Linear

    init(dim: Int = 3072, hiddenDim: Int = 9216) {
        self._gateProj.wrappedValue = Linear(dim, hiddenDim, bias: false)
        self._upProj.wrappedValue = Linear(dim, hiddenDim, bias: false)
        self._downProj.wrappedValue = Linear(hiddenDim, dim, bias: false)
    }

    func callAsFunction(_ x: MLXArray) -> MLXArray {
        downProj(silu(gateProj(x)) * upProj(x))
    }
}

/// Adaptive norm for time conditioning: linear_in -> GELU -> linear_out.
class VoxtralRealtimeAdaptiveNorm: Module {
    @ModuleInfo(key: "linear_in") var linearIn: Linear
    @ModuleInfo(key: "linear_out") var linearOut: Linear

    init(dim: Int = 3072, condDim: Int = 32) {
        self._linearIn.wrappedValue = Linear(dim, condDim, bias: false)
        self._linearOut.wrappedValue = Linear(condDim, dim, bias: false)
    }

    func callAsFunction(_ tCond: MLXArray) -> MLXArray {
        linearOut(gelu(linearIn(tCond)))
    }
}

/// Decoder layer with adaptive norm modulation on FFN.
class VoxtralRealtimeDecoderLayer: Module {
    @ModuleInfo(key: "attn_norm") var attnNorm: RMSNorm
    @ModuleInfo(key: "attention") var attention: VoxtralRealtimeDecoderAttention
    @ModuleInfo(key: "ada_norm") var adaNorm: VoxtralRealtimeAdaptiveNorm
    @ModuleInfo(key: "ffn_norm") var ffnNorm: RMSNorm
    @ModuleInfo(key: "mlp") var mlp: VoxtralRealtimeDecoderSwiGLU

    init(
        dim: Int = 3072,
        nHeads: Int = 32,
        nKvHeads: Int = 8,
        headDim: Int = 128,
        hiddenDim: Int = 9216,
        ropeTheta: Float = 1e6,
        condDim: Int = 32
    ) {
        self._attnNorm.wrappedValue = RMSNorm(dimensions: dim, eps: 1e-5)
        self._attention.wrappedValue = VoxtralRealtimeDecoderAttention(dim: dim, nHeads: nHeads, nKvHeads: nKvHeads, headDim: headDim, ropeTheta: ropeTheta)
        self._adaNorm.wrappedValue = VoxtralRealtimeAdaptiveNorm(dim: dim, condDim: condDim)
        self._ffnNorm.wrappedValue = RMSNorm(dimensions: dim, eps: 1e-5)
        self._mlp.wrappedValue = VoxtralRealtimeDecoderSwiGLU(dim: dim, hiddenDim: hiddenDim)
    }

    func callAsFunction(_ x: MLXArray, tCond: MLXArray, mask: MLXFast.ScaledDotProductAttentionMaskMode, cache: KVCache? = nil) -> MLXArray {
        let h = attention(attnNorm(x), mask: mask, cache: cache)
        var out = x + h
        let ffnIn = ffnNorm(out) * (1.0 + adaNorm(tCond))
        out = out + mlp(ffnIn)
        return out
    }
}

/// Language model: embed_tokens -> decoder layers -> norm -> tied linear for logits.
class VoxtralRealtimeLanguageModel: Module {
    @ModuleInfo(key: "embed_tokens") var embedTokens: Embedding
    let layers: [VoxtralRealtimeDecoderLayer]
    @ModuleInfo(key: "norm") var norm: RMSNorm
    let dim: Int

    init(
        dim: Int = 3072,
        nLayers: Int = 26,
        nHeads: Int = 32,
        nKvHeads: Int = 8,
        headDim: Int = 128,
        hiddenDim: Int = 9216,
        vocabSize: Int = 131072,
        ropeTheta: Float = 1e6,
        condDim: Int = 32
    ) {
        self.dim = dim
        self._embedTokens.wrappedValue = Embedding(embeddingCount: vocabSize, dimensions: dim)
        self.layers = (0..<nLayers).map { _ in
            VoxtralRealtimeDecoderLayer(
                dim: dim, nHeads: nHeads, nKvHeads: nKvHeads,
                headDim: headDim, hiddenDim: hiddenDim,
                ropeTheta: ropeTheta, condDim: condDim
            )
        }
        self._norm.wrappedValue = RMSNorm(dimensions: dim, eps: 1e-5)
    }

    func embed(_ inputIds: MLXArray) -> MLXArray {
        embedTokens(inputIds)
    }

    func callAsFunction(_ x: MLXArray, tCond: MLXArray, mask: MLXFast.ScaledDotProductAttentionMaskMode, cache: [KVCache]? = nil) -> MLXArray {
        var h = x
        let tCondCast = tCond.asType(h.dtype)
        for (i, layer) in layers.enumerated() {
            let layerCache = cache?[i]
            h = layer(h, tCond: tCondCast, mask: mask, cache: layerCache)
        }
        h = norm(h)
        // Tied embeddings: use embed_tokens weight as output projection
        return embedTokens.asLinear(h)
    }
}

// MARK: - Model Components

/// Sinusoidal time embedding for delay token conditioning.
class VoxtralRealtimeTimeEmbedding: Module {
    let dim: Int
    let theta: Float

    init(dim: Int = 32, theta: Float = 10000.0) {
        self.dim = dim
        self.theta = theta
        super.init()
    }

    func callAsFunction(_ t: MLXArray) -> MLXArray {
        // inv_freq is a computed constant, not a trained parameter —
        // must not be a stored MLXArray property to avoid weight-loading mismatch
        let halfDim = dim / 2
        let logTheta = -Foundation.log(theta)
        let arange = MLXArray(Array(0..<halfDim).map { Float($0) })
        let invFreq = MLX.exp(logTheta * arange / Float(halfDim))

        // t: scalar or [B]
        let tReshaped = t.reshaped(-1, 1).asType(.float32)  // [B, 1]
        let emb = tReshaped * invFreq  // [B, dim//2]
        return MLX.concatenated([MLX.cos(emb), MLX.sin(emb)], axis: -1)  // [B, dim]
    }
}

/// Audio-language adapter: projects encoder dim * downsample_factor to LM dim.
class VoxtralRealtimeAudioLanguageAdapter: Module {
    @ModuleInfo(key: "w_in") var wIn: Linear
    @ModuleInfo(key: "w_out") var wOut: Linear

    init(inDim: Int = 5120, outDim: Int = 3072) {
        self._wIn.wrappedValue = Linear(inDim, outDim, bias: false)
        self._wOut.wrappedValue = Linear(outDim, outDim, bias: false)
    }

    func callAsFunction(_ x: MLXArray) -> MLXArray {
        wOut(gelu(wIn(x)))
    }
}

// MARK: - Mel Spectrogram (Slaney-style, matching voxmlx audio.py)

/// Slaney-style mel filterbank matching mistral_common/audio.py.
private func voxtralRealtimeMelFilterBank(
    sampleRate: Int = VoxtralRealtimeAudioConstants.sampleRate,
    nFft: Int = VoxtralRealtimeAudioConstants.nFft,
    nMels: Int = VoxtralRealtimeAudioConstants.nMels,
    fMin: Float = 0.0,
    fMax: Float = 8000.0
) -> [[Float]] {
    func hzToMel(_ f: Float) -> Float {
        let minLogHz: Float = 1000.0
        let minLogMel: Float = 15.0
        let logstep: Float = 27.0 / Foundation.log(6.4)
        if f >= minLogHz {
            return minLogMel + Foundation.log(f / minLogHz) * logstep
        }
        return 3.0 * f / 200.0
    }

    func melToHz(_ m: Float) -> Float {
        let minLogHz: Float = 1000.0
        let minLogMel: Float = 15.0
        let logstep: Float = Foundation.log(6.4) / 27.0
        if m >= minLogMel {
            return minLogHz * Foundation.exp(logstep * (m - minLogMel))
        }
        return 200.0 * m / 3.0
    }

    let nFreqs = nFft / 2 + 1
    let fftFreqs = (0..<nFreqs).map { Float($0) * Float(sampleRate) / Float(2 * (nFreqs - 1)) }
    let melMin = hzToMel(fMin)
    let melMax = hzToMel(fMax)
    let melFreqs = (0...nMels + 1).map { melMin + Float($0) * (melMax - melMin) / Float(nMels + 1) }
    let filterFreqs = melFreqs.map { melToHz($0) }

    var filterDiff = [Float](repeating: 0, count: nMels + 1)
    for i in 0..<(nMels + 1) {
        filterDiff[i] = filterFreqs[i + 1] - filterFreqs[i]
    }

    // fb[mel][freq]
    var fb = [[Float]](repeating: [Float](repeating: 0, count: nFreqs), count: nMels)
    for mel in 0..<nMels {
        let enorm = 2.0 / (filterFreqs[mel + 2] - filterFreqs[mel])
        for freq in 0..<nFreqs {
            let downSlope = (fftFreqs[freq] - filterFreqs[mel]) / filterDiff[mel]
            let upSlope = (filterFreqs[mel + 2] - fftFreqs[freq]) / filterDiff[mel + 1]
            let val = max(0, min(downSlope, upSlope))
            fb[mel][freq] = val * enorm
        }
    }
    return fb
}

/// Cached mel filter bank as MLXArray [nMels, nFreqs].
nonisolated(unsafe) private let voxtralRealtimeMelFilters: MLXArray = {
    let fb = voxtralRealtimeMelFilterBank()
    let flat = fb.flatMap { $0 }
    return MLXArray(flat, [VoxtralRealtimeAudioConstants.nMels, VoxtralRealtimeAudioConstants.nFft / 2 + 1])
}()

/// Compute log mel spectrogram matching voxmlx audio.py.
/// Returns [nMels, T] (mel bins x time frames).
private func voxtralRealtimeLogMelSpectrogram(audio: MLXArray) -> MLXArray {
    let nFft = VoxtralRealtimeAudioConstants.nFft
    let hopLength = VoxtralRealtimeAudioConstants.hopLength

    // Hanning window matching Python: np.hanning(N_FFT+1)[:-1]
    let windowVals = (0..<nFft).map { Float(0.5 * (1.0 - Foundation.cos(2.0 * .pi * Double($0) / Double(nFft)))) }
    let window = MLXArray(windowVals)

    // Pad audio (STFT left+right padding of N_FFT//2)
    let padLen = nFft / 2
    let audioPadded = padded(audio, widths: [IntOrPair((padLen, padLen))])

    // Frame the signal
    let nFrames = 1 + (audioPadded.dim(0) - nFft) / hopLength
    var frameSlices: [MLXArray] = []
    for i in 0..<nFrames {
        let start = i * hopLength
        frameSlices.append(audioPadded[start..<(start + nFft)])
    }
    let frames = MLX.stacked(frameSlices, axis: 0) * window  // [nFrames, nFft]

    // Real FFT (hardware-accelerated via Metal)
    let fftResult = MLXFFT.rfft(frames, axis: 1)  // [nFrames, nFreqs] complex

    // Power spectrum, drop last frame to match torch.stft(...)[:-1]
    let nFramesTrunc = nFrames - 1
    let magnitudes = MLX.abs(fftResult[0..<nFramesTrunc]).square()  // [nFrames-1, nFreqs]

    // Mel filterbank
    let melFilters = voxtralRealtimeMelFilters  // [nMels, nFreqs]
    let melSpec = MLX.matmul(magnitudes, melFilters.transposed(1, 0))  // [nFrames-1, nMels]

    // Log scale
    var logSpec = MLX.log10(MLX.maximum(melSpec, MLXArray(Float(1e-10))))

    // Normalize
    logSpec = MLX.maximum(logSpec, MLXArray(VoxtralRealtimeAudioConstants.globalLogMelMax - 8.0))
    logSpec = (logSpec + 4.0) / 4.0

    // Transpose to [nMels, T]
    return logSpec.transposed(0, 1)
}

// MARK: - Voxtral Realtime Model

/// Voxtral Mini 4B Realtime STT model.
///
/// Architecture: CausalWhisperEncoder -> downsample+adapter -> LanguageModel with adaptive norm.
/// Uses streaming-style generation: audio embeddings are added to text embeddings position by position.
public class VoxtralRealtimeModel: Module {
    public let config: VoxtralRealtimeConfig

    @ModuleInfo(key: "encoder") var encoder: VoxtralRealtimeCausalWhisperEncoder
    @ModuleInfo(key: "adapter") var adapter: VoxtralRealtimeAudioLanguageAdapter
    @ModuleInfo(key: "language_model") var languageModel: VoxtralRealtimeLanguageModel
    @ModuleInfo(key: "time_embedding") var timeEmbedding: VoxtralRealtimeTimeEmbedding

    let downsampleFactor: Int
    let encoderDim: Int

    public var tokenizer: Tokenizer?

    /// BOS token ID.
    private let bosTokenId: Int = 1
    /// EOS token ID.
    private let eosTokenId: Int = 2
    /// Default delay tokens.
    private let defaultDelayTokens: Int = 6
    /// Default left pad tokens for streaming.
    private let defaultLeftPadTokens: Int = 32
    /// Sliding window for decoder KV cache.
    private let decoderSlidingWindow: Int = 8192

    public init(config: VoxtralRealtimeConfig) {
        self.config = config

        let enc = config.multimodal.whisperModelArgs.encoderArgs
        let audioEnc = enc.audioEncodingArgs
        let downsample = config.multimodal.whisperModelArgs.downsampleArgs.downsampleFactor

        self._encoder.wrappedValue = VoxtralRealtimeCausalWhisperEncoder(
            inChannels: audioEnc.numMelBins,
            dim: enc.dim,
            nLayers: enc.nLayers,
            nHeads: enc.nHeads,
            headDim: enc.headDim,
            hiddenDim: enc.hiddenDim,
            ropeTheta: enc.ropeTheta,
            slidingWindow: enc.slidingWindow
        )

        let adapterIn = enc.dim * downsample
        self._adapter.wrappedValue = VoxtralRealtimeAudioLanguageAdapter(inDim: adapterIn, outDim: config.dim)

        let condDim = config.adaRmsNormTCondDim
        self._languageModel.wrappedValue = VoxtralRealtimeLanguageModel(
            dim: config.dim,
            nLayers: config.nLayers,
            nHeads: config.nHeads,
            nKvHeads: config.nKvHeads,
            headDim: config.headDim,
            hiddenDim: config.hiddenDim,
            vocabSize: config.vocabSize,
            ropeTheta: config.ropeTheta,
            condDim: condDim
        )

        self._timeEmbedding.wrappedValue = VoxtralRealtimeTimeEmbedding(dim: config.dim)
        self.downsampleFactor = downsample
        self.encoderDim = enc.dim
    }

    // MARK: - Audio Preprocessing

    /// Pad audio for streaming (left_pad + right_pad).
    private func padAudio(_ audio: MLXArray, leftPadTokens: Int = 32, rightPadTokens: Int = 17) -> MLXArray {
        let spt = VoxtralRealtimeAudioConstants.samplesPerToken
        let leftPad = leftPadTokens * spt
        let audioLen = audio.dim(0)
        let rightAlign = (spt - (audioLen % spt)) % spt
        let rightPad = rightAlign + rightPadTokens * spt
        return padded(audio, widths: [IntOrPair((leftPad, rightPad))])
    }

    /// Compute log mel spectrogram from audio.
    private func computeMel(_ audio: MLXArray) -> MLXArray {
        voxtralRealtimeLogMelSpectrogram(audio: audio)
    }

    // MARK: - Encode

    /// Encode mel spectrogram to audio embeddings.
    public func encode(_ mel: MLXArray) -> MLXArray {
        // mel: [nMels, T]
        var melInput = mel
        let T = melInput.dim(1)
        if T % 2 != 0 {
            melInput = melInput[0..., 1...]
        }

        var x = encoder(melInput)  // [1, T/2, encoderDim]
        x = x.squeezed(axis: 0)   // [T/2, encoderDim]

        // Truncate to be divisible by downsample_factor
        let L = x.dim(0)
        let remainder = L % downsampleFactor
        if remainder != 0 {
            x = x[remainder...]
        }
        let truncL = x.dim(0)

        // Reshape: [T/2, encoderDim] -> [T/8, encoderDim*4]
        x = x.reshaped(truncL / downsampleFactor, -1)

        // Adapter: [T/8, encoderDim*4] -> [T/8, dim]
        x = adapter(x)
        return x
    }

    // MARK: - Decode

    /// Decode embeddings through language model.
    public func decode(_ embeddings: MLXArray, tCond: MLXArray, mask: MLXFast.ScaledDotProductAttentionMaskMode, cache: [KVCache]?) -> MLXArray {
        languageModel(embeddings, tCond: tCond, mask: mask, cache: cache)
    }

    // MARK: - Generation

    /// Build prompt tokens for streaming: [BOS] + [STREAMING_PAD] * (leftPad + delay).
    private func buildPromptTokens(streamingPadId: Int, leftPadTokens: Int = 32, delayTokens: Int = 6) -> [Int] {
        let prefixLen = leftPadTokens + delayTokens
        return [bosTokenId] + Array(repeating: streamingPadId, count: prefixLen)
    }

    /// Find STREAMING_PAD token ID from tokenizer.
    private func findStreamingPadId() -> Int {
        // [STREAMING_PAD] is special token ID 32 in Mistral's Tekkenizer convention.
        if let tokenizer = tokenizer,
           let id = tokenizer.convertTokenToId("[STREAMING_PAD]") {
            return id
        }
        return 32
    }

    /// Generate transcription from audio.
    public func generate(
        audio: MLXArray,
        maxTokens: Int = 4096,
        temperature: Float = 0.0
    ) -> STTOutput {
        guard let tokenizer = tokenizer else {
            fatalError("Tokenizer not loaded")
        }

        let startTime = Date()

        // Preprocess audio
        let paddedAudio = padAudio(audio)
        let mel = computeMel(paddedAudio)

        // Encode audio
        let audioEmbeds = encode(mel)  // [N_audio, dim]
        let nAudio = audioEmbeds.dim(0)

        // Time conditioning
        let tCond = timeEmbedding(MLXArray([Float(defaultDelayTokens)]))  // [1, dim]

        // Build prompt tokens
        let streamingPadId = findStreamingPadId()
        let promptTokens = buildPromptTokens(
            streamingPadId: streamingPadId,
            leftPadTokens: defaultLeftPadTokens,
            delayTokens: defaultDelayTokens
        )
        let prefixLen = promptTokens.count

        // Embed prompt tokens
        let promptIds = MLXArray(promptTokens.map { Int32($0) }).expandedDimensions(axis: 0)  // [1, prefixLen]
        let textEmbeds = languageModel.embed(promptIds).squeezed(axis: 0)  // [prefixLen, dim]

        // Each prefix position: tok_embed + audio_embed (elementwise addition)
        let prefixEmbeds = (textEmbeds + audioEmbeds[0..<prefixLen]).expandedDimensions(axis: 0)  // [1, prefixLen, dim]

        // Create decoder KV cache (RotatingKVCache for sliding window)
        let nLayers = languageModel.layers.count
        let cache: [KVCache] = (0..<nLayers).map { _ in
            RotatingKVCache(maxSize: decoderSlidingWindow)
        }

        // Prefill
        var logits = decode(prefixEmbeds, tCond: tCond, mask: .causal, cache: cache)
        eval(logits)
        for c in cache { eval(c) }

        let prefillEndTime = Date()

        // Greedy decode first token from prefill
        func sample(_ logits: MLXArray) -> Int {
            if temperature <= 0 {
                return logits[0, logits.dim(1) - 1].argMax(axis: -1).item(Int.self)
            }
            let scaled = (logits[0, logits.dim(1) - 1] / temperature).expandedDimensions(axis: 0)
            return categorical(scaled).item(Int.self)
        }

        var outputTokens: [Int] = []
        var y = sample(logits)

        // Autoregressive loop: for each position from prefixLen to N_audio
        // Process all audio positions by default, maxTokens acts as safety limit
        for pos in prefixLen..<nAudio {
            if y == eosTokenId {
                break
            }
            if outputTokens.count >= maxTokens {
                break
            }
            outputTokens.append(y)

            // Build step embedding: text_embed(token) + audio_embed(pos)
            let tokenEmbed = languageModel.embed(MLXArray([Int32(y)]).expandedDimensions(axis: 0)).squeezed(axes: [0, 1])  // [dim]
            let stepEmbed = (audioEmbeds[pos] + tokenEmbed).expandedDimensions(axes: [0, 1])  // [1, 1, dim]

            logits = decode(stepEmbed, tCond: tCond, mask: .none, cache: cache)
            eval(logits)

            y = sample(logits)

            if pos % 256 == 0 {
                Memory.clearCache()
            }
        }

        // Check last pending token
        if y != eosTokenId && outputTokens.count < maxTokens {
            outputTokens.append(y)
        }

        let endTime = Date()
        Memory.clearCache()

        let text = tokenizer.decode(tokens: outputTokens, skipSpecialTokens: true)
        let totalTime = endTime.timeIntervalSince(startTime)
        let prefillTime = prefillEndTime.timeIntervalSince(startTime)
        let generateTime = endTime.timeIntervalSince(prefillEndTime)

        return STTOutput(
            text: text.trimmingCharacters(in: .whitespacesAndNewlines),
            promptTokens: prefixLen,
            generationTokens: outputTokens.count,
            totalTokens: prefixLen + outputTokens.count,
            promptTps: Double(prefixLen) / max(prefillTime, 0.001),
            generationTps: generateTime > 0 ? Double(outputTokens.count) / generateTime : 0,
            totalTime: totalTime,
            peakMemoryUsage: Double(Memory.peakMemory) / 1e9
        )
    }

    /// Generate transcription with streaming token output.
    public func generateStream(
        audio: MLXArray,
        maxTokens: Int = 4096,
        temperature: Float = 0.0
    ) -> AsyncThrowingStream<STTGeneration, Error> {
        AsyncThrowingStream { continuation in
            do {
                guard let tokenizer = self.tokenizer else {
                    throw STTError.modelNotInitialized("Tokenizer not loaded")
                }

                let startTime = Date()

                let paddedAudio = self.padAudio(audio)
                let mel = self.computeMel(paddedAudio)
                let audioEmbeds = self.encode(mel)
                let nAudio = audioEmbeds.dim(0)
                let tCond = self.timeEmbedding(MLXArray([Float(self.defaultDelayTokens)]))
                let streamingPadId = self.findStreamingPadId()
                let promptTokens = self.buildPromptTokens(
                    streamingPadId: streamingPadId,
                    leftPadTokens: self.defaultLeftPadTokens,
                    delayTokens: self.defaultDelayTokens
                )
                let prefixLen = promptTokens.count

                let promptIds = MLXArray(promptTokens.map { Int32($0) }).expandedDimensions(axis: 0)
                let textEmbeds = self.languageModel.embed(promptIds).squeezed(axis: 0)
                let prefixEmbeds = (textEmbeds + audioEmbeds[0..<prefixLen]).expandedDimensions(axis: 0)

                let nLayers = self.languageModel.layers.count
                let cache: [KVCache] = (0..<nLayers).map { _ in
                    RotatingKVCache(maxSize: self.decoderSlidingWindow)
                }

                var logits = self.decode(prefixEmbeds, tCond: tCond, mask: .causal, cache: cache)
                eval(logits)
                for c in cache { eval(c) }

                let prefillEndTime = Date()

                func sample(_ logits: MLXArray) -> Int {
                    if temperature <= 0 {
                        return logits[0, logits.dim(1) - 1].argMax(axis: -1).item(Int.self)
                    }
                    let scaled = (logits[0, logits.dim(1) - 1] / temperature).expandedDimensions(axis: 0)
                    return categorical(scaled).item(Int.self)
                }

                var outputTokens: [Int] = []
                var y = sample(logits)

                // Process all audio positions by default, maxTokens acts as safety limit
                for pos in prefixLen..<nAudio {
                    if y == self.eosTokenId {
                        break
                    }
                    if outputTokens.count >= maxTokens {
                        break
                    }
                    outputTokens.append(y)

                    let tokenText = tokenizer.decode(tokens: [y], skipSpecialTokens: true)
                    if !tokenText.isEmpty {
                        continuation.yield(.token(tokenText))
                    }

                    let tokenEmbed = self.languageModel.embed(MLXArray([Int32(y)]).expandedDimensions(axis: 0)).squeezed(axes: [0, 1])
                    let stepEmbed = (audioEmbeds[pos] + tokenEmbed).expandedDimensions(axes: [0, 1])

                    logits = self.decode(stepEmbed, tCond: tCond, mask: .none, cache: cache)
                    eval(logits)

                    y = sample(logits)

                    if pos % 256 == 0 {
                        Memory.clearCache()
                    }
                }

                if y != self.eosTokenId && outputTokens.count < maxTokens {
                    outputTokens.append(y)
                    let tokenText = tokenizer.decode(tokens: [y], skipSpecialTokens: true)
                    if !tokenText.isEmpty {
                        continuation.yield(.token(tokenText))
                    }
                }

                let endTime = Date()
                Memory.clearCache()

                let prefillTime = prefillEndTime.timeIntervalSince(startTime)
                let generateTime = endTime.timeIntervalSince(prefillEndTime)
                let totalTime = endTime.timeIntervalSince(startTime)
                let tokensPerSecond = generateTime > 0 ? Double(outputTokens.count) / generateTime : 0
                let peakMemory = Double(Memory.peakMemory) / 1e9

                let info = STTGenerationInfo(
                    promptTokenCount: prefixLen,
                    generationTokenCount: outputTokens.count,
                    prefillTime: prefillTime,
                    generateTime: generateTime,
                    tokensPerSecond: tokensPerSecond,
                    peakMemoryUsage: peakMemory
                )
                continuation.yield(.info(info))

                let text = tokenizer.decode(tokens: outputTokens, skipSpecialTokens: true)
                let output = STTOutput(
                    text: text.trimmingCharacters(in: .whitespacesAndNewlines),
                    promptTokens: prefixLen,
                    generationTokens: outputTokens.count,
                    totalTokens: prefixLen + outputTokens.count,
                    promptTps: Double(prefixLen) / max(prefillTime, 0.001),
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

    // MARK: - Weight Loading

    /// Sanitize weights: mlx-community pre-converted models already in MLX layout.
    public func sanitize(weights: [String: MLXArray]) -> [String: MLXArray] {
        // mlx-community pre-converted models store conv weights in MLX layout already.
        // No transposition needed (matches Python voxmlx _load_converted path).
        return weights
    }

    /// Load model from pretrained weights (HuggingFace Hub or local).
    public static func fromPretrained(_ modelPath: String) async throws -> VoxtralRealtimeModel {
        let client = HubClient.default
        let cache = client.cache ?? HubCache.default

        guard let repoID = Repo.ID(rawValue: modelPath) else {
            throw NSError(
                domain: "VoxtralRealtimeModel",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Invalid repository ID: \(modelPath)"]
            )
        }

        let modelDir = try await resolveOrDownloadModel(
            client: client,
            cache: cache,
            repoID: repoID
        )

        // Load config (Mistral-native format: config.json)
        let configPath = modelDir.appendingPathComponent("config.json")
        let configData = try Data(contentsOf: configPath)
        let config = try JSONDecoder().decode(VoxtralRealtimeConfig.self, from: configData)

        // Create model
        let model = VoxtralRealtimeModel(config: config)

        // Apply quantization before loading weights
        if let quantConfig = config.quantization {
            let groupSize = quantConfig.groupSize
            quantize(
                model: model,
                groupSize: groupSize,
                bits: quantConfig.bits,
                filter: { _, module in
                    if let linear = module as? Linear {
                        return linear.weight.dim(-1) % groupSize == 0
                    }
                    if let embedding = module as? Embedding {
                        return embedding.weight.dim(-1) % groupSize == 0
                    }
                    return false
                }
            )
        }

        // Load tokenizer — Mistral models use tekken.json (tiktoken-style BPE),
        // which swift-transformers' AutoTokenizer cannot parse. Use TekkenTokenizer directly.
        let tekkenPath = modelDir.appendingPathComponent("tekken.json")
        if FileManager.default.fileExists(atPath: tekkenPath.path) {
            model.tokenizer = try TekkenTokenizer(url: tekkenPath)
        } else {
            model.tokenizer = try await AutoTokenizer.from(modelFolder: modelDir)
        }

        // Load weights (single or sharded)
        var weights: [String: MLXArray] = [:]
        let fileManager = FileManager.default

        let indexPath = modelDir.appendingPathComponent("model.safetensors.index.json")
        if fileManager.fileExists(atPath: indexPath.path) {
            let indexData = try Data(contentsOf: indexPath)
            let index = try JSONDecoder().decode(SafetensorsIndex.self, from: indexData)
            let shardFiles = Set(index.weightMap.values).sorted()
            for shardFile in shardFiles {
                let shardPath = modelDir.appendingPathComponent(shardFile)
                let shardWeights = try MLX.loadArrays(url: shardPath)
                weights.merge(shardWeights) { _, new in new }
            }
        } else {
            let files = try fileManager.contentsOfDirectory(at: modelDir, includingPropertiesForKeys: nil)
            let safetensorFiles = files.filter { $0.pathExtension == "safetensors" }
            for file in safetensorFiles {
                let fileWeights = try MLX.loadArrays(url: file)
                weights.merge(fileWeights) { _, new in new }
            }
        }

        // Sanitize and load weights
        let sanitizedWeights = model.sanitize(weights: weights)
        try model.update(parameters: ModuleParameters.unflattened(sanitizedWeights), verify: [.all])
        eval(model)

        return model
    }

    // MARK: - Private Helpers

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
                return modelDir
            }
        }

        try FileManager.default.createDirectory(at: modelDir, withIntermediateDirectories: true)

        _ = try await client.downloadSnapshot(
            of: repoID,
            kind: .model,
            to: modelDir,
            revision: "main",
            progressHandler: { progress in
                voxtralRealtimeLogger.info("\(progress.completedUnitCount)/\(progress.totalUnitCount) files")
            }
        )

        return modelDir
    }
}

// MARK: - Safetensors Index

private struct SafetensorsIndex: Codable {
    let weightMap: [String: String]

    enum CodingKeys: String, CodingKey {
        case weightMap = "weight_map"
    }
}
