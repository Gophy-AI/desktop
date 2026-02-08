//
//  ParakeetDecoders.swift
//  MLXAudioSTT
//
//  Decoder heads for Parakeet models (LSTM, RNNT, TDT, CTC).
//

import Foundation
import MLX
import MLXNN

// MARK: - LSTM

/// Multi-layer LSTM with manual cell implementation.
public class LSTM: Module {
    let inputSize: Int
    let hiddenSize: Int
    let numLayers: Int

    var cells: [LSTMCell]

    public init(inputSize: Int, hiddenSize: Int, numLayers: Int) {
        self.inputSize = inputSize
        self.hiddenSize = hiddenSize
        self.numLayers = numLayers
        self.cells = (0..<numLayers).map { i in
            LSTMCell(inputSize: i == 0 ? inputSize : hiddenSize, hiddenSize: hiddenSize)
        }
    }

    public func callAsFunction(_ x: MLXArray, state: LSTMState? = nil) -> (MLXArray, LSTMState) {
        let (B, L, _) = (x.dim(0), x.dim(1), x.dim(2))
        var hiddens: [MLXArray] = state?.hiddens ?? (0..<numLayers).map { _ in MLXArray.zeros([B, hiddenSize]) }
        var cells: [MLXArray] = state?.cells ?? (0..<numLayers).map { _ in MLXArray.zeros([B, hiddenSize]) }

        var outputs: [MLXArray] = []

        for t in 0..<L {
            var input = x[0..., t, 0...]

            for (layerIdx, cell) in self.cells.enumerated() {
                let (newHidden, newCell) = cell(input, h: hiddens[layerIdx], c: cells[layerIdx])
                hiddens[layerIdx] = newHidden
                cells[layerIdx] = newCell
                input = newHidden
            }

            outputs.append(input.expandedDimensions(axis: 1))
        }

        let output = concatenated(outputs, axis: 1)
        return (output, LSTMState(hiddens: hiddens, cells: cells))
    }
}

/// LSTM cell with manual gate computation.
public class LSTMCell: Module {
    @ModuleInfo(key: "input_gate") var inputGate: Linear
    @ModuleInfo(key: "forget_gate") var forgetGate: Linear
    @ModuleInfo(key: "cell_gate") var cellGate: Linear
    @ModuleInfo(key: "output_gate") var outputGate: Linear

    public init(inputSize: Int, hiddenSize: Int) {
        self._inputGate.wrappedValue = Linear(inputSize + hiddenSize, hiddenSize)
        self._forgetGate.wrappedValue = Linear(inputSize + hiddenSize, hiddenSize)
        self._cellGate.wrappedValue = Linear(inputSize + hiddenSize, hiddenSize)
        self._outputGate.wrappedValue = Linear(inputSize + hiddenSize, hiddenSize)
    }

    public func callAsFunction(_ x: MLXArray, h: MLXArray, c: MLXArray) -> (MLXArray, MLXArray) {
        let combined = concatenated([x, h], axis: -1)

        let i = sigmoid(inputGate(combined))
        let f = sigmoid(forgetGate(combined))
        let g = tanh(cellGate(combined))
        let o = sigmoid(outputGate(combined))

        let newCell = f * c + i * g
        let newHidden = o * tanh(newCell)

        return (newHidden, newCell)
    }
}

/// LSTM state container.
public struct LSTMState {
    var hiddens: [MLXArray]
    var cells: [MLXArray]
}

// MARK: - Prediction Network

/// Prediction network for RNNT/TDT (embedding + LSTM + linear).
public class PredictNetwork: Module {
    @ModuleInfo(key: "embedding") var embedding: Embedding
    @ModuleInfo(key: "lstm") var lstm: LSTM
    @ModuleInfo(key: "linear") var linear: Linear

    public init(args: PredictNetworkArgs) {
        self._embedding.wrappedValue = Embedding(embeddingCount: args.vocabSize, dimensions: args.embedDim)
        self._lstm.wrappedValue = LSTM(inputSize: args.embedDim, hiddenSize: args.hiddenDim, numLayers: args.numLayers)
        self._linear.wrappedValue = Linear(args.hiddenDim, args.hiddenDim)
    }

    public func callAsFunction(_ x: MLXArray, state: LSTMState? = nil) -> (MLXArray, LSTMState) {
        var result = embedding(x)
        let (lstmOut, newState) = lstm(result, state: state)
        result = linear(lstmOut)
        return (result, newState)
    }
}

// MARK: - Joint Network

/// Joint network for RNNT/TDT (combines encoder and predictor outputs).
public class JointNetwork: Module {
    @ModuleInfo(key: "enc_proj") var encProj: Linear
    @ModuleInfo(key: "pred_proj") var predProj: Linear
    @ModuleInfo(key: "output") var output: Linear
    let activation: String

    public init(args: JointNetworkArgs) {
        self._encProj.wrappedValue = Linear(args.encHidden, args.jointHidden)
        self._predProj.wrappedValue = Linear(args.predHidden, args.jointHidden)
        self._output.wrappedValue = Linear(args.jointHidden, args.vocabSize)
        self.activation = args.activation
    }

    public func callAsFunction(_ encOut: MLXArray, predOut: MLXArray) -> MLXArray {
        let encProjected = encProj(encOut)
        let predProjected = predProj(predOut)

        var combined = encProjected + predProjected

        if activation == "relu" {
            combined = relu(combined)
        } else if activation == "tanh" {
            combined = tanh(combined)
        }

        return output(combined)
    }
}

// MARK: - CTC Decoder

/// CTC decoder head (Conv1d + log_softmax).
public class ConvASRDecoder: Module {
    @ModuleInfo(key: "decoder") var decoder: Conv1d

    public init(args: ConvASRDecoderArgs) {
        self._decoder.wrappedValue = Conv1d(
            inputChannels: args.featIn,
            outputChannels: args.numClasses,
            kernelSize: 1
        )
    }

    public func callAsFunction(_ x: MLXArray) -> MLXArray {
        let logits = decoder(x)
        return logSoftmax(logits, axis: -1)
    }
}
