import Foundation

enum GeminiService {
    static func translate(
        text: String,
        target: String,
        tone: Tone,
        model: String,
        apiKey: String,
        promptTemplate: String,
        onDelta: @escaping @Sendable (String) -> Void
    ) async throws {
        guard !apiKey.isEmpty else { throw GeminiError.message("請先在設定中填入 Gemini API Key。") }

        let systemPrompt = promptTemplate.replacingOccurrences(of: "{target}", with: target)
            + (tone.instruction.isEmpty ? "" : " " + tone.instruction)
        let body = GenerateRequest(
            systemInstruction: SystemInstruction(parts: [Part(text: systemPrompt)]),
            contents: [Content(role: "user", parts: [Part(text: text)])]
        )
        var request = URLRequest(url: try endpoint(model: model, apiKey: apiKey, suffix: ":streamGenerateContent?alt=sse"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw GeminiError.message("無法取得 Gemini 回應。") }
        guard (200..<300).contains(http.statusCode) else {
            var message = "HTTP \(http.statusCode)"
            for try await line in bytes.lines where !line.isEmpty {
                message += ": " + line.prefix(300)
                break
            }
            throw GeminiError.message(message)
        }

        var parser = SSEParser()
        var receivedText = false
        for try await line in bytes.lines {
            for payload in parser.consume(line) {
                if let message = errorMessage(from: payload) { throw GeminiError.message(message) }
                receivedText = emitText(from: payload, onDelta: onDelta) || receivedText
            }
        }
        for payload in parser.finish() {
            if let message = errorMessage(from: payload) { throw GeminiError.message(message) }
            receivedText = emitText(from: payload, onDelta: onDelta) || receivedText
        }
        guard receivedText else { throw GeminiError.message("Gemini 沒有回傳可顯示的翻譯結果。") }
    }

    static func listModels(apiKey: String) async throws -> [String] {
        guard !apiKey.isEmpty else { throw GeminiError.message("請先填入 API Key。") }
        let request = URLRequest(url: try endpoint(model: "", apiKey: apiKey, suffix: "?pageSize=200", path: "models"))
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw GeminiError.message("無法取得模型清單。")
        }
        let responseBody = try JSONDecoder().decode(ModelList.self, from: data)
        return responseBody.models.compactMap { model in
            guard model.supportedGenerationMethods?.contains("generateContent") != false else { return nil }
            return model.name.replacingOccurrences(of: "models/", with: "")
        }.sorted()
    }

    private static func endpoint(model: String, apiKey: String, suffix: String, path: String? = nil) throws -> URL {
        let resource = path ?? "models/\(model)"
        guard var components = URLComponents(string: "https://generativelanguage.googleapis.com/v1beta/\(resource)\(suffix)") else {
            throw GeminiError.message("Gemini 網址無效。")
        }
        components.queryItems = (components.queryItems ?? []) + [URLQueryItem(name: "key", value: apiKey)]
        guard let url = components.url else { throw GeminiError.message("Gemini 網址無效。") }
        return url
    }

    private static func emitText(from payload: String, onDelta: @escaping @Sendable (String) -> Void) -> Bool {
        guard let data = payload.data(using: .utf8),
              let response = try? JSONDecoder().decode(GenerateResponse.self, from: data) else { return false }
        var emitted = false
        for candidate in response.candidates ?? [] {
            for part in candidate.content?.parts ?? [] where !part.text.isEmpty {
                onDelta(part.text)
                emitted = true
            }
        }
        return emitted
    }

    private static func errorMessage(from payload: String) -> String? {
        guard let data = payload.data(using: .utf8),
              let response = try? JSONDecoder().decode(ErrorResponse.self, from: data),
              let error = response.error else { return nil }
        return "Gemini API 錯誤：\(error.message)"
    }
}

struct SSEParser: Sendable {
    private var dataLines: [String] = []

    mutating func consume(_ line: String) -> [String] {
        if line.isEmpty { return flush() }
        if line.hasPrefix("data:") {
            let previous = flush()
            dataLines.append(line.dropFirst(5).trimmingCharacters(in: .whitespaces))
            return previous
        }
        return []
    }

    mutating func finish() -> [String] { flush() }

    private mutating func flush() -> [String] {
        defer { dataLines.removeAll() }
        return dataLines.isEmpty ? [] : [dataLines.joined(separator: "\n")]
    }
}

enum GeminiError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self { case let .message(text): return text }
    }
}

private struct GenerateRequest: Encodable {
    let systemInstruction: SystemInstruction
    let contents: [Content]
}

private struct Content: Codable {
    let role: String
    let parts: [Part]
}

private struct SystemInstruction: Encodable { let parts: [Part] }
private struct Part: Codable { let text: String }
private struct GenerateResponse: Decodable { let candidates: [Candidate]? }
private struct Candidate: Decodable { let content: ResponseContent? }
private struct ResponseContent: Decodable { let parts: [Part] }
private struct ErrorResponse: Decodable { let error: APIError? }
private struct APIError: Decodable { let message: String }
private struct ModelList: Decodable { let models: [GeminiModel] }
private struct GeminiModel: Decodable {
    let name: String
    let supportedGenerationMethods: [String]?
}
