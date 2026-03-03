import Foundation

struct AITranscriptReport: Codable, Equatable, Sendable {
    let title: String?
    let summary: String
    let actionItems: [String]
    let score: Int?
    let strengths: [String]
    let improvements: [String]

    enum CodingKeys: String, CodingKey {
        case title
        case summary
        case actionItems
        case score
        case strengths
        case improvements
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedTitle = try container.decodeIfPresent(String.self, forKey: .title)?.trimmingCharacters(in: .whitespacesAndNewlines)
        title = decodedTitle?.isEmpty == true ? nil : decodedTitle
        let decodedSummary = try container.decodeIfPresent(String.self, forKey: .summary) ?? ""
        summary = decodedSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "No summary provided."
            : decodedSummary
        actionItems = try container.decodeIfPresent([String].self, forKey: .actionItems) ?? []
        score = try container.decodeIfPresent(Int.self, forKey: .score)
        strengths = try container.decodeIfPresent([String].self, forKey: .strengths) ?? []
        improvements = try container.decodeIfPresent([String].self, forKey: .improvements) ?? []
    }
}

struct OpenAITranscriptAnalyzer {
    private let session: URLSession

    static let defaultSystemPrompt = """
    You are an assistant that analyzes transcript text from voice notes, conversations, meetings, and calls.
    Return strict JSON with this exact schema:
    {
      \"title\": string,
      \"summary\": string,
      \"actionItems\": string[],
      \"score\": integer,
      \"strengths\": string[],
      \"improvements\": string[]
    }
    Rules:
    - title is optional; include it only when you want the app to rename the recording
    - summary is required and must stay under 120 words
    - actionItems is optional, max 6 items
    - score is optional, integer 0-10 for overall call quality
    - strengths is optional, max 4 items
    - improvements is optional, max 4 items
    - Omit optional fields if the transcript does not support them
    - Do not include markdown fences
    """

    init(session: URLSession = .shared) {
        self.session = session
    }

    func analyze(
        transcript: String,
        recordingTitle: String?,
        apiKey: String,
        systemPrompt: String = OpenAITranscriptAnalyzer.defaultSystemPrompt
    ) async throws -> AITranscriptReport {
        guard let url = URL(string: "https://api.openai.com/v1/chat/completions") else {
            throw AIAnalysisError.invalidRequest
        }

        let trimmedTitle = recordingTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let userContent: String
        if trimmedTitle.isEmpty {
            userContent = "Transcript:\n\(transcript)"
        } else {
            userContent = "Current recording title: \(trimmedTitle)\n\nTranscript:\n\(transcript)"
        }

        let payload = ChatCompletionsRequest(
            model: "gpt-4.1-mini",
            messages: [
                .init(role: "system", content: systemPrompt),
                .init(role: "user", content: userContent)
            ],
            temperature: 0.2,
            responseFormat: .init(type: "json_object")
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AIAnalysisError.invalidResponse
        }

        guard (200 ... 299).contains(http.statusCode) else {
            if let apiError = try? JSONDecoder().decode(OpenAIAPIErrorResponse.self, from: data) {
                throw AIAnalysisError.api(apiError.error.message)
            }
            throw AIAnalysisError.api("Request failed with status \(http.statusCode)")
        }

        let decoded = try JSONDecoder().decode(ChatCompletionsResponse.self, from: data)
        guard let content = decoded.choices.first?.message.content,
              let jsonData = content.data(using: .utf8)
        else {
            throw AIAnalysisError.invalidResponse
        }

        do {
            return try JSONDecoder().decode(AITranscriptReport.self, from: jsonData)
        } catch {
            throw AIAnalysisError.invalidResponse
        }
    }
}

enum AIAnalysisError: LocalizedError {
    case missingAPIKey
    case invalidRequest
    case invalidResponse
    case api(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "API key is missing for the selected AI provider. Add it from settings."
        case .invalidRequest:
            return "Could not build AI request."
        case .invalidResponse:
            return "AI returned an unexpected response."
        case let .api(message):
            return message
        }
    }
}

private struct ChatCompletionsRequest: Encodable {
    let model: String
    let messages: [Message]
    let temperature: Double
    let responseFormat: ResponseFormat

    struct Message: Encodable {
        let role: String
        let content: String
    }

    struct ResponseFormat: Encodable {
        let type: String

        enum CodingKeys: String, CodingKey {
            case type
        }
    }

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case temperature
        case responseFormat = "response_format"
    }
}

private struct ChatCompletionsResponse: Decodable {
    let choices: [Choice]

    struct Choice: Decodable {
        let message: Message
    }

    struct Message: Decodable {
        let content: String
    }
}

private struct OpenAIAPIErrorResponse: Decodable {
    let error: OpenAIAPIError

    struct OpenAIAPIError: Decodable {
        let message: String
    }
}
