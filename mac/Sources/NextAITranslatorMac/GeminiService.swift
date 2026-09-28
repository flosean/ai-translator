import Foundation

enum GeminiService {
    static func translate(
        text: String,
        target: String,
        tone: Tone,
        model: String,
        apiKey: String,
        promptTemplate: String,
        onDelta: @escaping @MainActor @Sendable (String) -> Void
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
                for delta in try textDeltas(from: payload) {
                    try Task.checkCancellation()
                    await onDelta(delta)
                    receivedText = true
                }
            }
        }
        for payload in parser.finish() {
            for delta in try textDeltas(from: payload) {
                try Task.checkCancellation()
                await onDelta(delta)
                receivedText = true
            }
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
        let model = model.hasPrefix("models/") ? String(model.dropFirst(7)) : model
        guard path != nil || !model.isEmpty else { throw GeminiError.message("請先選擇 Gemini 模型。") }
        let escapedModel = model.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-_."))) ?? ""
        let resource = path ?? "models/\(escapedModel)"
        guard var components = URLComponents(string: "https://generativelanguage.googleapis.com/v1beta/\(resource)\(suffix)") else {
            throw GeminiError.message("Gemini 網址無效。")
        }
        components.queryItems = (components.queryItems ?? []) + [URLQueryItem(name: "key", value: apiKey)]
        guard let url = components.url else { throw GeminiError.message("Gemini 網址無效。") }
        return url
    }

    static func textDeltas(from payload: String) throws -> [String] {
        guard let data = payload.data(using: .utf8),
              let response = try? JSONDecoder().decode(GenerateResponse.self, from: data) else { return [] }
        if let error = response.error {
            throw GeminiError.message("Gemini API 錯誤：\(error.message)")
        }
        return (response.candidates?.first?.content?.parts ?? []).compactMap { part in
            guard part.thought != true, let text = part.text, !text.isEmpty else { return nil }
            return text
        }
    }
}

struct SSEParser: Sendable {
    private var dataLines: [String] = []

    mutating func consume(_ line: String) -> [String] {
        if line.isEmpty { return flush() }
        if line.hasPrefix("data:") {
            // Also accept complete JSON events from providers that omit blank separators.
            let buffered = dataLines.joined(separator: "\n")
            let complete = buffered == "[DONE]" || buffered.data(using: .utf8).flatMap {
                try? JSONSerialization.jsonObject(with: $0)
            } != nil
            let previous = complete ? flush() : []
            var value = String(line.dropFirst(5))
            if value.hasPrefix(" ") { value.removeFirst() }
            dataLines.append(value)
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
private struct GenerateResponse: Decodable {
    let candidates: [Candidate]?
    let error: APIError?
}
private struct Candidate: Decodable { let content: ResponseContent? }
private struct ResponseContent: Decodable { let parts: [ResponsePart]? }
private struct ResponsePart: Decodable {
    let text: String?
    let thought: Bool?
}
private struct APIError: Decodable { let message: String }
private struct ModelList: Decodable { let models: [GeminiModel] }
private struct GeminiModel: Decodable {
    let name: String
    let supportedGenerationMethods: [String]?
}
