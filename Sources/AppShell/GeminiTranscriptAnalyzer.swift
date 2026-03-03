import Foundation

struct GeminiTranscriptAnalyzer {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func analyze(
        transcript: String,
        recordingTitle: String?,
        apiKey: String,
        systemPrompt: String
    ) async throws -> AITranscriptReport {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AIAnalysisError.missingAPIKey
        }

        let escapedKey = apiKey.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? apiKey
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=\(escapedKey)") else {
            throw AIAnalysisError.invalidRequest
        }

        let trimmedTitle = recordingTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let userContent: String
        if trimmedTitle.isEmpty {
            userContent = "Transcript:\n\(transcript)"
        } else {
            userContent = "Current recording title: \(trimmedTitle)\n\nTranscript:\n\(transcript)"
        }

        let payload = GeminiGenerateContentRequest(
            systemInstruction: .init(parts: [.init(text: systemPrompt)]),
            contents: [
                .init(parts: [.init(text: userContent)])
            ],
            generationConfig: .init(
                temperature: 0.2,
                responseMimeType: "application/json"
            )
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AIAnalysisError.invalidResponse
        }

        guard (200 ... 299).contains(http.statusCode) else {
            if let apiError = try? JSONDecoder().decode(GeminiAPIErrorResponse.self, from: data) {
                throw AIAnalysisError.api(apiError.error.message)
            }
            throw AIAnalysisError.api("Request failed with status \(http.statusCode)")
        }

        let decoded = try JSONDecoder().decode(GeminiGenerateContentResponse.self, from: data)
        guard let content = decoded.candidates.first?.content.parts.first?.text,
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

private struct GeminiGenerateContentRequest: Encodable {
    let systemInstruction: SystemInstruction
    let contents: [Content]
    let generationConfig: GenerationConfig

    struct SystemInstruction: Encodable {
        let parts: [Part]
    }

    struct Content: Encodable {
        let parts: [Part]
    }

    struct Part: Encodable {
        let text: String
    }

    struct GenerationConfig: Encodable {
        let temperature: Double
        let responseMimeType: String

        enum CodingKeys: String, CodingKey {
            case temperature
            case responseMimeType = "responseMimeType"
        }
    }

    enum CodingKeys: String, CodingKey {
        case systemInstruction = "system_instruction"
        case contents
        case generationConfig = "generationConfig"
    }
}

private struct GeminiGenerateContentResponse: Decodable {
    let candidates: [Candidate]

    struct Candidate: Decodable {
        let content: Content
    }

    struct Content: Decodable {
        let parts: [Part]
    }

    struct Part: Decodable {
        let text: String?
    }
}

private struct GeminiAPIErrorResponse: Decodable {
    let error: GeminiAPIError

    struct GeminiAPIError: Decodable {
        let message: String
    }
}
