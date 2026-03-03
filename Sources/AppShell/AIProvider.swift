import Foundation

enum AIProvider: String, CaseIterable, Identifiable, Codable, Sendable {
    case openAI = "openai"
    case gemini = "gemini"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .openAI:
            return "OpenAI"
        case .gemini:
            return "Gemini"
        }
    }

    var apiKeyPlaceholder: String {
        switch self {
        case .openAI:
            return "sk-..."
        case .gemini:
            return "AIza..."
        }
    }
}
