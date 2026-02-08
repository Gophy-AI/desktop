//
//  Wav2VecFeatureExtractor.swift
//  MLXAudioSTT
//
// Created by act agent on 08/02/2026.
//

import Foundation
import MLX
import MLXNN

public class Wav2Vec2FeatureExtractor {
    public let featureSize: Int
    public let samplingRate: Int
    public let paddingValue: Float

    public init(
        featureSize: Int = 1,
        samplingRate: Int = 16000,
        paddingValue: Float = 0.0
    ) {
        self.featureSize = featureSize
        self.samplingRate = samplingRate
        self.paddingValue = paddingValue
    }

    public func normalize(_ audio: MLXArray) -> MLXArray {
        let mean = audio.mean()
        let variance = pow(audio - mean, 2).mean()
        let std = sqrt(variance + 1e-7)
        return (audio - mean) / std
    }

    public func callAsFunction(_ audio: MLXArray, returnAttentionMask: Bool = true) -> (inputValues: MLXArray, attentionMask: MLXArray?) {
        let normalized = normalize(audio)

        if returnAttentionMask {
            let attentionMask = MLXArray.ones(like: normalized)
            return (normalized, attentionMask)
        } else {
            return (normalized, nil)
        }
    }
}
