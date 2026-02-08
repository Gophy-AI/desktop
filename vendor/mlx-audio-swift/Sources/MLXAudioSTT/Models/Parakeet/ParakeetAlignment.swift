//
//  ParakeetAlignment.swift
//  MLXAudioSTT
//
//  Alignment utilities for Parakeet models (LCS-based overlap merging, sentence segmentation).
//

import Foundation

// MARK: - Alignment Data Structures

/// Token with timing information.
public struct AlignedToken: Sendable {
    public var token: String
    public var start: Float
    public var end: Float

    public init(token: String, start: Float, end: Float) {
        self.token = token
        self.start = start
        self.end = end
    }
}

/// Sentence with tokens and timing information.
public struct AlignedSentence: Sendable {
    public var tokens: [AlignedToken]
    public var text: String
    public var start: Float
    public var end: Float

    public init(tokens: [AlignedToken], text: String, start: Float, end: Float) {
        self.tokens = tokens
        self.text = text
        self.start = start
        self.end = end
    }
}

/// Result containing aligned sentences.
public struct AlignedResult: Sendable {
    public var sentences: [AlignedSentence]

    public init(sentences: [AlignedSentence]) {
        self.sentences = sentences
    }

    /// Convert to STTOutput format.
    public func toSTTOutput() -> [[String: Any]] {
        return sentences.map { sentence in
            [
                "text": sentence.text,
                "start": sentence.start,
                "end": sentence.end,
                "tokens": sentence.tokens.map { token in
                    [
                        "token": token.token,
                        "start": token.start,
                        "end": token.end
                    ] as [String: Any]
                }
            ] as [String: Any]
        }
    }
}

// MARK: - Longest Common Subsequence

/// Merge overlapping chunks using Longest Common Subsequence (LCS) algorithm.
///
/// - Parameters:
///   - chunk1: First chunk tokens
///   - chunk2: Second chunk tokens
/// - Returns: Merged token sequence
public func mergeLongestCommonSubsequence(_ chunk1: [String], _ chunk2: [String]) -> [String] {
    guard !chunk1.isEmpty && !chunk2.isEmpty else {
        return chunk1 + chunk2
    }

    // Find LCS overlap at the end of chunk1 and beginning of chunk2
    let overlapLen = findOverlapLength(chunk1, chunk2)

    if overlapLen > 0 {
        // Merge with overlap removed
        let mergedChunk1 = Array(chunk1.dropLast(overlapLen))
        return mergedChunk1 + chunk2
    } else {
        // No overlap, concatenate directly
        return chunk1 + chunk2
    }
}

/// Find the length of overlapping subsequence.
private func findOverlapLength(_ seq1: [String], _ seq2: [String]) -> Int {
    let maxOverlap = min(seq1.count, seq2.count)

    for overlap in stride(from: maxOverlap, through: 1, by: -1) {
        let suffix = Array(seq1.suffix(overlap))
        let prefix = Array(seq2.prefix(overlap))

        if suffix == prefix {
            return overlap
        }
    }

    return 0
}

// MARK: - Sentence Segmentation

/// Segment tokens into sentences based on punctuation and timing.
///
/// - Parameters:
///   - tokens: List of aligned tokens
///   - minSentenceLength: Minimum sentence length in tokens (default 5)
/// - Returns: List of aligned sentences
public func segmentIntoSentences(_ tokens: [AlignedToken], minSentenceLength: Int = 5) -> [AlignedSentence] {
    guard !tokens.isEmpty else {
        return []
    }

    var sentences: [AlignedSentence] = []
    var currentTokens: [AlignedToken] = []

    for token in tokens {
        currentTokens.append(token)

        // Check if token ends with sentence-ending punctuation
        if isSentenceEnding(token.token) && currentTokens.count >= minSentenceLength {
            let sentence = createSentence(from: currentTokens)
            sentences.append(sentence)
            currentTokens = []
        }
    }

    // Add remaining tokens as final sentence
    if !currentTokens.isEmpty {
        let sentence = createSentence(from: currentTokens)
        sentences.append(sentence)
    }

    return sentences
}

/// Check if token ends with sentence-ending punctuation.
private func isSentenceEnding(_ token: String) -> Bool {
    let endings: Set<Character> = [".", "!", "?", "\u{3002}", "\u{FF01}", "\u{FF1F}"]
    return endings.contains(where: { token.hasSuffix(String($0)) })
}

/// Create aligned sentence from tokens.
private func createSentence(from tokens: [AlignedToken]) -> AlignedSentence {
    let text = tokens.map { $0.token }.joined(separator: " ")
    let start = tokens.first?.start ?? 0
    let end = tokens.last?.end ?? 0

    return AlignedSentence(tokens: tokens, text: text, start: start, end: end)
}
