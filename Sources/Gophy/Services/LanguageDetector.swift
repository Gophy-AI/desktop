import Foundation
import NaturalLanguage

public final class LanguageDetector: Sendable {
    private let minimumTextLength: Int

    public init(minimumTextLength: Int = 10) {
        self.minimumTextLength = minimumTextLength
    }

    public func detect(text: String) -> AppLanguage? {
        guard text.count >= minimumTextLength else {
            return nil
        }

        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)

        guard let dominant = recognizer.dominantLanguage else {
            return nil
        }

        return mapNLLanguage(dominant)
    }

    public func detectWithConfidence(text: String, maxHypotheses: Int = 5) -> [(AppLanguage, Double)] {
        guard text.count >= minimumTextLength else {
            return []
        }

        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)

        let hypotheses = recognizer.languageHypotheses(withMaximum: maxHypotheses)

        return hypotheses.compactMap { (language, confidence) in
            guard let appLanguage = mapNLLanguage(language) else {
                return nil
            }
            return (appLanguage, confidence)
        }
        .sorted { $0.1 > $1.1 }
    }

    private func mapNLLanguage(_ language: NLLanguage) -> AppLanguage? {
        switch language {
        case .english: return .english
        case .russian: return .russian
        case .spanish: return .spanish
        default: return nil
        }
    }
}
