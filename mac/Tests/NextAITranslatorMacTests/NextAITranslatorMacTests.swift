import SwiftUI
import XCTest
@testable import NextAITranslatorMac

@MainActor
final class NextAITranslatorMacTests: XCTestCase {
    func testAPIKeyFilePersistencePermissionsAndDeletion() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let file = directory.appendingPathComponent("credentials.json")
        let suite = "NextAITranslatorMacTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer {
            try? FileManager.default.removeItem(at: directory)
            defaults.removePersistentDomain(forName: suite)
        }
        XCTAssertEqual(APIKeyStore.load(from: file), "")
        let settings = AppSettings(defaults: defaults, apiKey: "  test-key\n", apiKeyFile: file)
        try settings.saveAPIKey()
        XCTAssertEqual(AppSettings(defaults: defaults, apiKeyFile: file).apiKey, "test-key")
        for (url, mode) in [(directory, 0o700), (file, 0o600)] {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, mode)
        }
        settings.apiKey = "replacement"
        try settings.saveAPIKey()
        XCTAssertEqual(APIKeyStore.load(from: file), "replacement")
        settings.apiKey = " "
        try settings.saveAPIKey()
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        try settings.saveAPIKey()
        XCTAssertEqual(APIKeyStore.load(from: file), "")
    }

    func testSSEParserWaitsForBlankLine() {
        var parser = SSEParser()
        XCTAssertEqual(parser.consume("data: {\"a\":1}"), [])
        XCTAssertEqual(parser.consume(""), ["{\"a\":1}"])
    }

    func testSSEParserFlushesPreviousGeminiEventWithoutBlankLine() {
        var parser = SSEParser()
        XCTAssertEqual(parser.consume("data: {\"a\":1}"), [])
        XCTAssertEqual(parser.consume("data: {\"b\":2}"), ["{\"a\":1}"])
        XCTAssertEqual(parser.finish(), ["{\"b\":2}"])
    }

    func testSSEParserPreservesMultilineJSON() throws {
        var parser = SSEParser()
        XCTAssertEqual(parser.consume("data: {\"candidates\":"), [])
        XCTAssertEqual(parser.consume("data: [{\"content\":{\"parts\":[{\"text\":\"你好\"}]}}]}"), [])
        let payload = try XCTUnwrap(parser.consume("").first)
        XCTAssertEqual(try GeminiService.streamEvent(from: payload).deltas, ["你好"])
    }

    func testGeminiIgnoresThoughtsAndNonTextPartsAndExtraCandidates() throws {
        let payload = #"{"candidates":[{"content":{"parts":[{"text":"thinking","thought":true},{"inlineData":{}},{"text":"result"}]}},{"content":{"parts":[{"text":"other"}]}}]}"#
        XCTAssertEqual(try GeminiService.streamEvent(from: payload).deltas, ["result"])
        XCTAssertThrowsError(try GeminiService.streamEvent(from: #"{"error":{"message":"quota exceeded"}}"#))
        XCTAssertThrowsError(try GeminiService.streamEvent(from: #"{"candidates":[{"finishReason":"SAFETY"}]}"#))
    }

    func testGeminiStreamAcceptsOnlyCompletedTextResponses() async {
        let text = #"{"candidates":[{"content":{"parts":[{"text":"譯文"}]}}]}"#
        let stop = #"{"candidates":[{"finishReason":"STOP"}]}"#
        for separator in ["\n\n", "\n"] {
            let result = await runStream("data: \(text)\(separator)data: \(stop)")
            XCTAssertEqual(result.text, "譯文")
            XCTAssertNil(result.error)
        }
        let result = await runStream("data: {\"candidates\":\n" +
            "data: [{\"content\":{\"parts\":[{\"text\":\"譯文\"}]},\"finishReason\":\"STOP\"}]}\n\n")
        XCTAssertEqual(result.text, "譯文")
        XCTAssertNil(result.error)
    }

    func testGeminiStreamRejectsTruncationMalformedEventsAndAbnormalStops() async {
        let text = "data: {\"candidates\":[{\"content\":{\"parts\":[{\"text\":\"半段翻譯\"}]}}]}\n\n"
        let cases = [
            ("", "串流未完整結束"),
            ("data: {\"candidates\":[", "資料格式錯誤"),
            ("data: {broken}\n\ndata: {\"candidates\":[{\"finishReason\":\"STOP\"}]}\n\n", "資料格式錯誤"),
            ("data: {\"candidates\":[{\"finishReason\":\"MAX_TOKENS\"}]}\n\n", "輸出長度上限"),
            ("data: {\"candidates\":[{\"finishReason\":\"SAFETY\"}]}\n\n", "提前結束"),
            ("data: {\"error\":{\"message\":\"test quota error\"}}\n\n", "test quota error")
        ]
        for (tail, expectedError) in cases {
            let result = await runStream(text + tail)
            XCTAssertEqual(result.text, "半段翻譯")
            XCTAssertTrue(result.error?.contains(expectedError) == true, "Unexpected error: \(result.error ?? "none")")
        }
        let empty = await runStream("data: {\"candidates\":[{\"finishReason\":\"STOP\"}]}\n\n")
        XCTAssertTrue(empty.error?.contains("沒有回傳") == true)
    }

    private func runStream(_ body: String) async -> (text: String, error: String?) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CannedGeminiProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: URL(string: "https://gemini.invalid/test")!)
        request.setValue(Data(body.utf8).base64EncodedString(), forHTTPHeaderField: "X-Test-Stream")
        let output = StreamOutput()
        do {
            try await GeminiService.stream(request, session: session) { output.text += $0 }
            return (output.text, nil)
        } catch {
            return (output.text, error.localizedDescription)
        }
    }

    func testSettingsPersistToTheirOwnStoreAndClampInvalidValues() {
        let suite = "NextAITranslatorMacTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Double.nan, forKey: "contentFontSize")
        defaults.set("中文", forKey: "hotkeyKey")
        let settings = AppSettings(defaults: defaults, apiKey: "")
        XCTAssertEqual(settings.contentFontSize, 16)
        XCTAssertEqual(settings.hotkeyKey, "z")
        settings.model = "test-model"
        settings.contentFontSize = 24
        settings.target = "en"
        let restored = AppSettings(defaults: defaults, apiKey: "")
        XCTAssertEqual(restored.model, "test-model")
        XCTAssertEqual(restored.contentFontSize, 24)
        XCTAssertEqual(restored.target, "en")
    }

    func testClearAndReplacementIgnoreLateTranslationCallbacks() async throws {
        let suite = "NextAITranslatorMacTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults, apiKey: "test-key")
        let stream = ControlledTranslation()
        let translator = TranslatorViewModel(settings: settings, translate: { text, _, _, _, _, _, delta in
            try await stream.run(text, delta: delta)
        })
        for text in ["first", "second"] {
            translator.source = text
            translator.translate()
            for _ in 0..<100 where stream.callbacks[text] == nil { try await Task.sleep(for: .milliseconds(10)) }
            XCTAssertNotNil(stream.callbacks[text])
        }
        stream.callbacks["first"]?("stale")
        stream.callbacks["second"]?("current")
        stream.finish("first", error: URLError(.cancelled))
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(translator.output, "current")
        XCTAssertEqual(translator.error, "")
        XCTAssertTrue(translator.isTranslating)

        translator.clear()
        XCTAssertFalse(translator.isTranslating)
        stream.callbacks["second"]?("late")
        stream.finish("second", error: URLError(.cancelled))
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(translator.source, "")
        XCTAssertEqual(translator.output, "")
        XCTAssertEqual(translator.error, "")
        XCTAssertFalse(translator.isTranslating)
    }

    func testMainAndSettingsViewsRenderAtMinimumSizes() {
        let suite = "NextAITranslatorMacTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(40, forKey: "contentFontSize")
        let settings = AppSettings(defaults: defaults, apiKey: "")
        let translator = TranslatorViewModel(settings: settings)
        settings.models = [settings.model, "gemini-2.5-flash"]
        translator.source = String(repeating: "這是一段需要翻譯的長文字。", count: 12)
        translator.output = String(repeating: "This is a long translated result. ", count: 12)
        translator.error = "這是一段用來確認底部錯誤訊息不會擠壓複製按鈕的長錯誤訊息。"

        XCTAssertNotNil(render(TranslatorView(settings: settings, translator: translator), width: 620, height: 660))
        XCTAssertNotNil(render(SettingsView(settings: settings), width: 560, height: 620))
    }

    func testTranslateWithoutAPIKeyShowsImmediateError() {
        let suite = "NextAITranslatorMacTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults, apiKey: "")
        settings.apiKey = ""
        let translator = TranslatorViewModel(settings: settings)
        translator.source = "Hello"

        translator.translate()

        XCTAssertEqual(translator.error, "請先在設定中儲存 Gemini API Key。")
        XCTAssertFalse(translator.isTranslating)
    }

    func testTranslationPanesResizeWithDivider() {
        typealias Panes = ResizableTranslationPanes<EmptyView, EmptyView>
        let available: CGFloat = 500
        XCTAssertEqual(Panes.inputHeight(available: available, ratio: 0.5), 250)
        XCTAssertEqual(Panes.inputHeight(available: available, ratio: 0.7), 350)
        XCTAssertEqual(Panes.inputHeight(available: available, ratio: -1), 130)
        XCTAssertEqual(Panes.inputHeight(available: available, ratio: 2), 420)
        XCTAssertEqual(Panes.inputHeight(available: 300, ratio: 0.7), 210)
    }

    func testShutDownDefaultModelMigratesToCurrentModel() {
        let suite = "NextAITranslatorMacTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("gemini-2.0-flash", forKey: "model")

        XCTAssertEqual(AppSettings(defaults: defaults, apiKey: "").model, "gemini-3.5-flash")
    }

    private func render<V: View>(_ view: V, width: CGFloat, height: CGFloat) -> CGImage? {
        let renderer = ImageRenderer(content: view.frame(width: width, height: height))
        renderer.proposedSize = ProposedViewSize(width: width, height: height)
        return renderer.cgImage
    }
}

@MainActor
private final class ControlledTranslation {
    var callbacks: [String: @MainActor @Sendable (String) -> Void] = [:]
    private var continuations: [String: CheckedContinuation<Void, Error>] = [:]

    func run(_ text: String, delta: @escaping @MainActor @Sendable (String) -> Void) async throws {
        try await withCheckedThrowingContinuation { continuation in
            callbacks[text] = delta
            continuations[text] = continuation
        }
    }

    func finish(_ text: String, error: Error) {
        continuations.removeValue(forKey: text)?.resume(throwing: error)
    }
}

@MainActor
private final class StreamOutput { var text = "" }

private final class CannedGeminiProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let fixture = request.value(forHTTPHeaderField: "X-Test-Stream"),
              let data = Data(base64Encoded: fixture),
              let url = request.url,
              let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil,
                  headerFields: ["Content-Type": "text/event-stream"]) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
