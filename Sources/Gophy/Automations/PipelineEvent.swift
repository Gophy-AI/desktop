import Foundation
import MLXLMCommon

/// Events emitted by the ToolCallingPipeline during orchestration.
public enum PipelineEvent: Sendable {
    /// A streamed text token from the model.
    case text(String)

    /// A tool call was detected and is about to be executed.
    case toolCallStarted(ToolCall)

    /// A tool call completed with a result.
    case toolCallCompleted(name: String, result: String)

    /// A tool call execution encountered an error.
    case error(String)

    /// The pipeline finished processing.
    case done
}

extension PipelineEvent: CustomStringConvertible {
    public var description: String {
        switch self {
        case .text(let t): return "text(\(t))"
        case .toolCallStarted(let tc): return "toolCallStarted(\(tc.function.name))"
        case .toolCallCompleted(let name, let result): return "toolCallCompleted(\(name), \(result))"
        case .error(let e): return "error(\(e))"
        case .done: return "done"
        }
    }
}
