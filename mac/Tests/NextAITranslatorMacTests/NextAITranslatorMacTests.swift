import SwiftUI
import XCTest
@testable import NextAITranslatorMac

@MainActor
final class NextAITranslatorMacTests: XCTestCase {
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
        XCTAssertEqual(try GeminiService.textDeltas(from: payload), ["你好"])
    }

    func testGeminiIgnoresThoughtsAndNonTextPartsAndExtraCandidates() throws {
        let payload = #"{"candidates":[{"content":{"parts":[{"text":"thinking","thought":true},{"inlineData":{}},{"text":"result"}]}},{"content":{"parts":[{"text":"other"}]}}]}"#
        XCTAssertEqual(try GeminiService.textDeltas(from: payload), ["result"])
        XCTAssertThrowsError(try GeminiService.textDeltas(from: #"{"error":{"message":"quota exceeded"}}"#))
        XCTAssertEqual(try GeminiService.textDeltas(from: #"{"candidates":[{"finishReason":"SAFETY"}]}"#), [])
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

    func testTranslationPanesResizeWithDivider() throws {
        let suite = "NextAITranslatorMacTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults, apiKey: "")
        let translator = TranslatorViewModel(settings: settings)
        let host = NSHostingView(rootView: TranslatorView(settings: settings, translator: translator))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 660),
                              styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.close() }
        host.layoutSubtreeIfNeeded()

        func findSplit(in view: NSView) -> NSSplitView? {
            if let split = view as? NSSplitView { return split }
            return view.subviews.lazy.compactMap { findSplit(in: $0) }.first
        }
        let split = try XCTUnwrap(findSplit(in: host))
        XCTAssertFalse(split.isVertical)
        XCTAssertEqual(split.arrangedSubviews.count, 2)
        split.setPosition(220, ofDividerAt: 0)
        host.layoutSubtreeIfNeeded()
        let before = split.arrangedSubviews.map { $0.frame.height }
        split.setPosition(320, ofDividerAt: 0)
        host.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(split.arrangedSubviews[0].frame.height, before[0] + 50)
        XCTAssertLessThan(split.arrangedSubviews[1].frame.height, before[1] - 50)
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
