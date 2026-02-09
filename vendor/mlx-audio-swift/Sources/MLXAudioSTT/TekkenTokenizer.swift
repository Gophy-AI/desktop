import Foundation
import Tokenizers

/// Mistral Tekken tokenizer implementation that reads tekken.json (Mistral's tiktoken-style BPE format).
///
/// The Mistral Tekkenizer uses a split ID space:
///   - IDs 0 ..< numSpecialTokens (1000): special/control tokens (BOS, EOS, [STREAMING_PAD], etc.)
///   - IDs numSpecialTokens ..< vocabSize: regular BPE vocabulary (offset by +numSpecialTokens from tekken.json ranks)
///
/// This matches the Python `mistral_common.tokens.tokenizers.tekken.Tekkenizer` convention.
public final class TekkenTokenizer: Tokenizer, @unchecked Sendable {

    // MARK: - Codable Structures

    private struct TekkenJSON: Codable {
        let config: Config
        let vocab: [VocabEntry]

        struct Config: Codable {
            let pattern: String
            let numVocabTokens: Int
            let defaultVocabSize: Int
            let defaultNumSpecialTokens: Int
            let version: String

            enum CodingKeys: String, CodingKey {
                case pattern
                case numVocabTokens = "num_vocab_tokens"
                case defaultVocabSize = "default_vocab_size"
                case defaultNumSpecialTokens = "default_num_special_tokens"
                case version
            }
        }

        struct VocabEntry: Codable {
            let rank: Int
            let tokenBytes: String
            let tokenStr: String?

            enum CodingKeys: String, CodingKey {
                case rank
                case tokenBytes = "token_bytes"
                case tokenStr = "token_str"
            }
        }
    }

    // MARK: - Mistral Special Tokens

    /// Hardcoded special tokens matching Mistral's Tekkenizer convention.
    /// These occupy IDs 0..<numSpecialTokens in the model's vocabulary.
    private static let knownSpecialTokens: [(rank: Int, name: String)] = [
        (0, "<unk>"),
        (1, "<s>"),
        (2, "</s>"),
        (3, "[INST]"),
        (4, "[/INST]"),
        (5, "[AVAILABLE_TOOLS]"),
        (6, "[/AVAILABLE_TOOLS]"),
        (7, "[TOOL_RESULTS]"),
        (8, "[/TOOL_RESULTS]"),
        (9, "[TOOL_CALLS]"),
        (10, "[IMG]"),
        (11, "<pad>"),
        (12, "[IMG_BREAK]"),
        (13, "[IMG_END]"),
        (14, "[PREFIX]"),
        (15, "[MIDDLE]"),
        (16, "[SUFFIX]"),
        (17, "[SYSTEM_PROMPT]"),
        (18, "[/SYSTEM_PROMPT]"),
        (19, "[TOOL_CONTENT]"),
        (20, "[BBOX]"),
        (21, "[/BBOX]"),
        (22, "[STEP]"),
        (23, "[/STEP]"),
        (24, "[AUDIO]"),
        (25, "[BEGIN_AUDIO]"),
        (26, "[OUTPUT_AUDIO]"),
        (27, "[REF]"),
        (28, "[/REF]"),
        (29, "[REASONING]"),
        (30, "[VERIFICATION]"),
        (31, "[SCORE]"),
        (32, "[STREAMING_PAD]"),
        (33, "[STREAMING_WORD]"),
        (34, "[REPEAT_AUDIO_TEXT]"),
    ]

    // MARK: - Properties

    /// Maps byte sequences to Mistral-convention token IDs (regular tokens offset by numSpecialTokens).
    private let encoder: [Data: Int]
    /// Maps Mistral-convention token IDs to byte sequences.
    private let decoder: [Int: Data]
    /// Set of special token IDs (0..<numSpecialTokens).
    private let specialTokenIds: Set<Int>
    /// Maps special token name strings to their IDs.
    private let specialTokenStrings: [String: Int]
    /// The number of reserved special token slots (typically 1000).
    private let numSpecialTokens: Int
    private let regex: NSRegularExpression

    public let bosToken: String?
    public let bosTokenId: Int?
    public let eosToken: String?
    public let eosTokenId: Int?
    public let unknownToken: String?
    public let unknownTokenId: Int?

    // MARK: - Init

    public init(url: URL) throws {
        let data = try Data(contentsOf: url)
        let tekkenJSON = try JSONDecoder().decode(TekkenJSON.self, from: data)

        let numSpecial = tekkenJSON.config.defaultNumSpecialTokens
        self.numSpecialTokens = numSpecial

        var encoder: [Data: Int] = [:]
        var decoder: [Int: Data] = [:]
        var specialTokenIds: Set<Int> = []
        var specialTokenStrings: [String: Int] = [:]

        // 1. Register known special tokens (IDs 0..<numSpecialTokens)
        for (rank, name) in Self.knownSpecialTokens where rank < numSpecial {
            specialTokenIds.insert(rank)
            specialTokenStrings[name] = rank
            if let nameData = name.data(using: .utf8) {
                decoder[rank] = nameData
            }
        }

        // 2. Build encoder/decoder for regular vocabulary with +numSpecialTokens offset.
        //    tekken.json ranks are 0-based raw BPE ranks; Mistral convention shifts them
        //    so regular tokens start at ID numSpecialTokens.
        let innerVocabSize = tekkenJSON.config.defaultVocabSize - numSpecial
        for entry in tekkenJSON.vocab {
            guard entry.rank < innerVocabSize else { continue }
            guard let tokenData = Data(base64Encoded: entry.tokenBytes) else {
                throw TokenizerError.malformedVocab
            }
            let offsetId = entry.rank + numSpecial
            encoder[tokenData] = offsetId
            decoder[offsetId] = tokenData
        }

        self.encoder = encoder
        self.decoder = decoder
        self.specialTokenIds = specialTokenIds
        self.specialTokenStrings = specialTokenStrings

        // Compile regex pattern for pre-tokenization
        self.regex = try NSRegularExpression(
            pattern: tekkenJSON.config.pattern,
            options: []
        )

        // BOS/EOS/UNK from the known special tokens
        self.bosTokenId = 1
        self.bosToken = "<s>"
        self.eosTokenId = 2
        self.eosToken = "</s>"
        self.unknownTokenId = 0
        self.unknownToken = "<unk>"
    }

    // MARK: - Tokenizer Protocol (Required Methods)

    public func tokenize(text: String) -> [String] {
        let ids = encode(text: text, addSpecialTokens: false)
        return ids.compactMap { id in
            guard let data = decoder[id] else { return nil }
            return String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
        }
    }

    public func encode(text: String) -> [Int] {
        return encode(text: text, addSpecialTokens: true)
    }

    public func encode(text: String, addSpecialTokens: Bool) -> [Int] {
        let segments = splitTextWithSpecialTokens(text: text)

        var result: [Int] = []

        for segment in segments {
            if segment.isSpecial {
                if let id = specialTokenStrings[segment.text] {
                    result.append(id)
                }
            } else {
                result.append(contentsOf: encodeBPE(text: segment.text))
            }
        }

        return result
    }

    public func decode(tokens: [Int], skipSpecialTokens: Bool) -> String {
        var allBytes = Data()

        for id in tokens {
            if skipSpecialTokens && specialTokenIds.contains(id) {
                continue
            }

            if let data = decoder[id] {
                allBytes.append(data)
            }
        }

        return String(data: allBytes, encoding: .utf8) ?? String(decoding: allBytes, as: UTF8.self)
    }

    public func convertTokenToId(_ token: String) -> Int? {
        if let specialId = specialTokenStrings[token] {
            return specialId
        }
        guard let data = token.data(using: .utf8) else { return nil }
        return encoder[data]
    }

    public func convertIdToToken(_ id: Int) -> String? {
        guard let data = decoder[id] else { return nil }
        return String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
    }

    // MARK: - Chat Template Methods (Required - Throw Not Supported)

    public func applyChatTemplate(messages: [Message]) throws -> [Int] {
        throw TokenizerError.missingChatTemplate
    }

    public func applyChatTemplate(messages: [Message], tools: [ToolSpec]?) throws -> [Int] {
        throw TokenizerError.missingChatTemplate
    }

    public func applyChatTemplate(
        messages: [Message],
        tools: [ToolSpec]?,
        additionalContext: [String: any Sendable]?
    ) throws -> [Int] {
        throw TokenizerError.missingChatTemplate
    }

    public func applyChatTemplate(
        messages: [Message],
        chatTemplate: ChatTemplateArgument
    ) throws -> [Int] {
        throw TokenizerError.missingChatTemplate
    }

    public func applyChatTemplate(
        messages: [Message],
        chatTemplate: String
    ) throws -> [Int] {
        throw TokenizerError.missingChatTemplate
    }

    public func applyChatTemplate(
        messages: [Message],
        chatTemplate: ChatTemplateArgument?,
        addGenerationPrompt: Bool,
        truncation: Bool,
        maxLength: Int?,
        tools: [ToolSpec]?
    ) throws -> [Int] {
        throw TokenizerError.missingChatTemplate
    }

    public func applyChatTemplate(
        messages: [Message],
        chatTemplate: ChatTemplateArgument?,
        addGenerationPrompt: Bool,
        truncation: Bool,
        maxLength: Int?,
        tools: [ToolSpec]?,
        additionalContext: [String: any Sendable]?
    ) throws -> [Int] {
        throw TokenizerError.missingChatTemplate
    }

    // MARK: - Private Helper Methods

    private struct TextSegment {
        let text: String
        let isSpecial: Bool
    }

    private func splitTextWithSpecialTokens(text: String) -> [TextSegment] {
        var segments: [TextSegment] = []
        var currentIndex = text.startIndex

        let sortedSpecialTokens = specialTokenStrings.keys.sorted { $0.count > $1.count }

        while currentIndex < text.endIndex {
            var foundSpecialToken = false

            for specialToken in sortedSpecialTokens {
                let endIndex = text.index(
                    currentIndex,
                    offsetBy: specialToken.count,
                    limitedBy: text.endIndex
                ) ?? text.endIndex

                if endIndex <= text.endIndex {
                    let substring = String(text[currentIndex..<endIndex])
                    if substring == specialToken {
                        segments.append(TextSegment(text: specialToken, isSpecial: true))
                        currentIndex = endIndex
                        foundSpecialToken = true
                        break
                    }
                }
            }

            if !foundSpecialToken {
                var nextSpecialIndex = text.endIndex
                var foundNextSpecial = false

                for specialToken in sortedSpecialTokens {
                    if let range = text.range(
                        of: specialToken,
                        range: currentIndex..<text.endIndex
                    ) {
                        if range.lowerBound < nextSpecialIndex {
                            nextSpecialIndex = range.lowerBound
                            foundNextSpecial = true
                        }
                    }
                }

                let endIndex = foundNextSpecial ? nextSpecialIndex : text.endIndex
                let regularText = String(text[currentIndex..<endIndex])

                if !regularText.isEmpty {
                    segments.append(TextSegment(text: regularText, isSpecial: false))
                }

                currentIndex = endIndex
            }
        }

        return segments
    }

    private func encodeBPE(text: String) -> [Int] {
        var result: [Int] = []

        let nsText = text as NSString
        let matches = regex.matches(
            in: text,
            options: [],
            range: NSRange(location: 0, length: nsText.length)
        )

        for match in matches {
            let piece = nsText.substring(with: match.range)
            guard let pieceData = piece.data(using: .utf8) else { continue }

            if let tokenId = encoder[pieceData] {
                result.append(tokenId)
                continue
            }

            let tokens = applyBPE(to: pieceData)
            result.append(contentsOf: tokens)
        }

        return result
    }

    private func applyBPE(to data: Data) -> [Int] {
        if let tokenId = encoder[data] {
            return [tokenId]
        }

        var parts: [Data] = data.map { Data([$0]) }

        while parts.count > 1 {
            var bestPair: (index: Int, rank: Int)?

            for i in 0..<(parts.count - 1) {
                var merged = Data()
                merged.append(parts[i])
                merged.append(parts[i + 1])

                if let rank = encoder[merged] {
                    if bestPair == nil || rank < bestPair!.rank {
                        bestPair = (index: i, rank: rank)
                    }
                }
            }

            guard let pair = bestPair else {
                break
            }

            var newParts: [Data] = []
            var i = 0
            while i < parts.count {
                if i == pair.index {
                    var merged = Data()
                    merged.append(parts[i])
                    merged.append(parts[i + 1])
                    newParts.append(merged)
                    i += 2
                } else {
                    newParts.append(parts[i])
                    i += 1
                }
            }

            parts = newParts
        }

        return parts.compactMap { encoder[$0] }
    }
}
