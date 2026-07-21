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

    func testMainAndSettingsViewsRenderAtMinimumSizes() {
        let suite = "NextAITranslatorMacTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(40, forKey: "contentFontSize")
        let settings = AppSettings(defaults: defaults)
        let translator = TranslatorViewModel(settings: settings)
        settings.models = [settings.model, "gemini-2.5-flash"]
        translator.source = String(repeating: "這是一段需要翻譯的長文字。", count: 12)
        translator.output = String(repeating: "This is a long translated result. ", count: 12)
        translator.error = "這是一段用來確認底部錯誤訊息不會擠壓複製按鈕的長錯誤訊息。"

        XCTAssertNotNil(render(TranslatorView(settings: settings, translator: translator), width: 620, height: 660))
        XCTAssertNotNil(render(SettingsView(settings: settings), width: 560, height: 620))
    }

    func testTranslateWithoutAPIKeyShowsImmediateError() {
        let defaults = UserDefaults(suiteName: "NextAITranslatorMacTests.\(UUID().uuidString)")!
        let settings = AppSettings(defaults: defaults)
        settings.apiKey = ""
        let translator = TranslatorViewModel(settings: settings)
        translator.source = "Hello"

        translator.translate()

        XCTAssertEqual(translator.error, "請先在設定中儲存 Gemini API Key。")
        XCTAssertFalse(translator.isTranslating)
    }

    func testShutDownDefaultModelMigratesToCurrentModel() {
        let suite = "NextAITranslatorMacTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("gemini-2.0-flash", forKey: "model")

        XCTAssertEqual(AppSettings(defaults: defaults).model, "gemini-3.5-flash")
    }

    private func render<V: View>(_ view: V, width: CGFloat, height: CGFloat) -> CGImage? {
        let renderer = ImageRenderer(content: view.frame(width: width, height: height))
        renderer.proposedSize = ProposedViewSize(width: width, height: height)
        return renderer.cgImage
    }
}
