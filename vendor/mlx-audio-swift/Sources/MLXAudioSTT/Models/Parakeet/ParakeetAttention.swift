//
//  ParakeetAttention.swift
//  MLXAudioSTT
//
//  Attention modules for Parakeet Conformer encoder.
//

import Foundation
import MLX
import MLXNN

// MARK: - Multi-Head Attention

/// Standard multi-head attention.
public class MultiHeadAttention: Module {
    let dModel: Int
    let nHeads: Int
    let headDim: Int
    let scale: Float

    @ModuleInfo(key: "q_proj") var qProj: Linear
    @ModuleInfo(key: "k_proj") var kProj: Linear
    @ModuleInfo(key: "v_proj") var vProj: Linear
    @ModuleInfo(key: "out_proj") var outProj: Linear

    public init(dModel: Int, nHeads: Int, useBias: Bool = true) {
        self.dModel = dModel
        self.nHeads = nHeads
        self.headDim = dModel / nHeads
        self.scale = pow(Float(headDim), -0.5)

        self._qProj.wrappedValue = Linear(dModel, dModel, bias: useBias)
        self._kProj.wrappedValue = Linear(dModel, dModel, bias: useBias)
        self._vProj.wrappedValue = Linear(dModel, dModel, bias: useBias)
        self._outProj.wrappedValue = Linear(dModel, dModel, bias: useBias)
    }

    public func callAsFunction(_ x: MLXArray, mask: MLXArray? = nil) -> MLXArray {
        let (B, L, _) = (x.dim(0), x.dim(1), x.dim(2))

        var queries = qProj(x).reshaped(B, L, nHeads, headDim).transposed(0, 2, 1, 3)
        var keys = kProj(x).reshaped(B, L, nHeads, headDim).transposed(0, 2, 1, 3)
        var values = vProj(x).reshaped(B, L, nHeads, headDim).transposed(0, 2, 1, 3)

        // Manual scaled dot-product attention
        var scores = matmul(queries, keys.transposed(0, 1, 3, 2)) * scale
        if let mask = mask {
            scores = scores + mask
        }
        let attnWeights = softmax(scores, axis: -1)
        let output = matmul(attnWeights, values).transposed(0, 2, 1, 3).reshaped(B, L, dModel)

        return outProj(output)
    }
}

// MARK: - Relative Positional Encoding

/// Sinusoidal positional encoding with dynamic max_len expansion for relative attention.
public class RelPositionalEncoding: Module {
    let dModel: Int
    var maxLen: Int
    var pe: MLXArray

    public init(dModel: Int, maxLen: Int = 5000) {
        self.dModel = dModel
        self.maxLen = maxLen
        self.pe = RelPositionalEncoding.computePositionalEncoding(dModel: dModel, maxLen: maxLen)
    }

    private static func computePositionalEncoding(dModel: Int, maxLen: Int) -> MLXArray {
        var pe = MLXArray.zeros([maxLen, dModel])

        let position = MLXArray(Array(0..<maxLen).map { Float($0) }).expandedDimensions(axis: 1)
        let divTerm = exp(
            MLXArray(stride(from: 0, to: dModel, by: 2).map { Float($0) }) * (-log(10000.0) / Float(dModel))
        )

        for i in 0..<maxLen {
            for j in stride(from: 0, to: dModel, by: 2) {
                let angle = Float(i) * divTerm[j / 2].item(Float.self)
                pe[i, j] = MLXArray(sin(angle))
                if j + 1 < dModel {
                    pe[i, j + 1] = MLXArray(cos(angle))
                }
            }
        }

        return pe
    }

    /// Extend positional encoding if needed.
    private func extendPE(to newLen: Int) {
        if newLen > maxLen {
            maxLen = newLen
            pe = RelPositionalEncoding.computePositionalEncoding(dModel: dModel, maxLen: maxLen)
        }
    }

    public func callAsFunction(_ x: MLXArray) -> (MLXArray, MLXArray) {
        let seqLen = x.dim(1)
        extendPE(to: seqLen)

        let posEmb = pe[0..<seqLen]
        return (x, posEmb)
    }
}

// MARK: - Relative Position Multi-Head Attention

/// Multi-head attention with relative positional encoding.
///
/// Uses learned bias parameters (pos_bias_u, pos_bias_v) and relative shift operation.
public class RelPositionMultiHeadAttention: Module {
    let dModel: Int
    let nHeads: Int
    let headDim: Int
    let scale: Float

    @ModuleInfo(key: "q_proj") var qProj: Linear
    @ModuleInfo(key: "k_proj") var kProj: Linear
    @ModuleInfo(key: "v_proj") var vProj: Linear
    @ModuleInfo(key: "out_proj") var outProj: Linear
    @ModuleInfo(key: "pos_proj") var posProj: Linear

    var posBiasU: MLXArray
    var posBiasV: MLXArray

    public init(dModel: Int, nHeads: Int, useBias: Bool = true, posBiasU: MLXArray? = nil, posBiasV: MLXArray? = nil) {
        self.dModel = dModel
        self.nHeads = nHeads
        self.headDim = dModel / nHeads
        self.scale = pow(Float(headDim), -0.5)

        self._qProj.wrappedValue = Linear(dModel, dModel, bias: useBias)
        self._kProj.wrappedValue = Linear(dModel, dModel, bias: useBias)
        self._vProj.wrappedValue = Linear(dModel, dModel, bias: useBias)
        self._outProj.wrappedValue = Linear(dModel, dModel, bias: useBias)
        self._posProj.wrappedValue = Linear(dModel, dModel, bias: false)

        self.posBiasU = posBiasU ?? MLXArray.zeros([nHeads, headDim])
        self.posBiasV = posBiasV ?? MLXArray.zeros([nHeads, headDim])
    }

    /// Relative shift operation for relative position matrix.
    ///
    /// Shifts the position matrix to align relative positions correctly.
    private func relShift(_ x: MLXArray) -> MLXArray {
        // x shape: [B, H, L, 2*L-1]
        let (B, H, L) = (x.dim(0), x.dim(1), x.dim(2))
        let posLen = x.dim(3)

        // Zero pad on the left: [B, H, L, 2*L]
        let zeroPad = MLXArray.zeros([B, H, L, 1])
        let xPadded = concatenated([zeroPad, x], axis: 3)

        // Reshape and slice to get correct alignment
        let xReshaped = xPadded.reshaped(B, H, posLen + 1, L)
        let xShifted = xReshaped[0..., 0..., 1..<(posLen + 1), 0...]
        let xFinal = xShifted.reshaped(B, H, L, posLen)

        // Take center L columns
        let startCol = (posLen - L) / 2
        return xFinal[0..., 0..., 0..., startCol..<(startCol + L)]
    }

    public func callAsFunction(_ x: MLXArray, pos: MLXArray, mask: MLXArray? = nil) -> MLXArray {
        let (B, L, _) = (x.dim(0), x.dim(1), x.dim(2))

        var queries = qProj(x).reshaped(B, L, nHeads, headDim).transposed(0, 2, 1, 3)
        var keys = kProj(x).reshaped(B, L, nHeads, headDim).transposed(0, 2, 1, 3)
        var values = vProj(x).reshaped(B, L, nHeads, headDim).transposed(0, 2, 1, 3)
        var posKeys = posProj(pos).reshaped(pos.dim(0), nHeads, headDim).transposed(1, 0, 2)

        // Compute attention with relative position bias
        // Content-based attention: (q + u) @ k.T
        let qWithU = queries + posBiasU.reshaped(1, nHeads, 1, headDim)
        let contentScore = matmul(qWithU, keys.transposed(0, 1, 3, 2))

        // Position-based attention: (q + v) @ pos_k.T
        let qWithV = queries + posBiasV.reshaped(1, nHeads, 1, headDim)
        let posScore = matmul(qWithV, posKeys.transposed(0, 2, 1))
        let posScoreShifted = relShift(posScore)

        // Combined attention scores
        var attnScores = (contentScore + posScoreShifted) * scale

        if let mask = mask {
            attnScores = attnScores + mask
        }

        let attnWeights = softmax(attnScores, axis: -1)
        let output = matmul(attnWeights, values).transposed(0, 2, 1, 3).reshaped(B, L, dModel)

        return outProj(output)
    }
}
