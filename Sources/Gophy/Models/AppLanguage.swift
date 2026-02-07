import Foundation

public enum AppLanguage: String, Codable, Sendable, CaseIterable {
    case auto
    case english
    case russian
    case spanish

    public var isoCode: String? {
        switch self {
        case .auto: return nil
        case .english: return "en"
        case .russian: return "ru"
        case .spanish: return "es"
        }
    }

    public var displayName: String {
        switch self {
        case .auto: return "Auto-detect"
        case .english: return "English"
        case .russian: return "Russian"
        case .spanish: return "Spanish"
        }
    }
}
