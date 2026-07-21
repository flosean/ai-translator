import AppKit
import Security
import SwiftUI

@main
struct NextAITranslatorMacApp: App {
    @StateObject private var settings: AppSettings
    @StateObject private var translator: TranslatorViewModel
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        let settings = AppSettings()
        _settings = StateObject(wrappedValue: settings)
        _translator = StateObject(wrappedValue: TranslatorViewModel(settings: settings))
    }

    var body: some Scene {
        WindowGroup("NextAI 翻譯") {
            TranslatorView(settings: settings, translator: translator)
                .onReceive(NotificationCenter.default.publisher(for: .showTranslator)) { _ in showTranslator() }
        }
        .defaultSize(width: 680, height: 740)
        .windowResizability(.contentMinSize)
        .commands { CommandGroup(replacing: .newItem) {} }

        Settings {
            SettingsView(settings: settings)
        }

        MenuBarExtra("NextAI 翻譯", systemImage: "character.bubble") {
            Button("顯示翻譯器") { showTranslator() }
            SettingsLink { Text("設定⋯") }
            Divider()
            Button("結束") { NSApp.terminate(nil) }
        }
    }

    private func showTranslator() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first(where: { $0.canBecomeMain })?.makeKeyAndOrderFront(nil)
        if settings.autoTranslateClipboard, let text = NSPasteboard.general.string(forType: .string), !text.isEmpty {
            translator.source = text
            translator.translate()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        HotkeyManager.shared.register(key: UserDefaults.standard.string(forKey: "hotkeyKey") ?? "z")
        NotificationCenter.default.addObserver(forName: .hotkeyChanged, object: nil, queue: .main) { notification in
            HotkeyManager.shared.register(key: notification.object as? String ?? "z")
        }
    }
}

@MainActor
final class AppSettings: ObservableObject {
    static let defaultPrompt = "You are a professional translation engine. Translate the user's text into {target}. Only output the translated text — no explanations, no notes, no commentary, and no surrounding quotation marks. Preserve the original formatting (line breaks, lists). Match the tone and register of the source. Keep brand names and technical terms in their original form unless a widely accepted translation exists. If the text is already in {target}, output it unchanged."

    @Published var apiKey: String
    @Published var model: String { didSet { save("model", model) } }
    @Published var target: String { didSet { save("target", target) } }
    @Published var tone: Tone { didSet { save("tone", tone.rawValue) } }
    @Published var autoTranslateClipboard: Bool { didSet { save("autoTranslateClipboard", autoTranslateClipboard) } }
    @Published var contentFontSize: Double { didSet { save("contentFontSize", contentFontSize) } }
    @Published var promptTemplate: String { didSet { save("promptTemplate", promptTemplate) } }
    @Published var hotkeyKey: String { didSet { save("hotkeyKey", hotkeyKey); NotificationCenter.default.post(name: .hotkeyChanged, object: hotkeyKey) } }
    @Published var models: [String] = []
    @Published var modelError = ""

    init(defaults: UserDefaults = .standard) {
        apiKey = KeychainStore.load()
        let storedModel = defaults.string(forKey: "model")
        model = storedModel == "gemini-2.0-flash" ? "gemini-3.5-flash" : (storedModel ?? "gemini-3.5-flash")
        target = defaults.string(forKey: "target") == "en" ? "en" : "zh-Hant"
        tone = Tone(rawValue: defaults.string(forKey: "tone") ?? "default") ?? .default
        autoTranslateClipboard = defaults.object(forKey: "autoTranslateClipboard") as? Bool ?? false
        contentFontSize = min(max(defaults.object(forKey: "contentFontSize") as? Double ?? 16, 12), 40)
        promptTemplate = defaults.string(forKey: "promptTemplate") ?? Self.defaultPrompt
        hotkeyKey = defaults.string(forKey: "hotkeyKey") ?? "z"
    }

    func saveAPIKey() throws { try KeychainStore.save(apiKey) }
    func loadModels() {
        Task {
            do {
                models = try await GeminiService.listModels(apiKey: apiKey)
                if !model.isEmpty && !models.contains(model) { models.insert(model, at: 0) }
                modelError = models.isEmpty ? "沒有可用的 Gemini 模型。" : ""
            } catch { modelError = error.localizedDescription }
        }
    }

    private func save(_ key: String, _ value: Any) { UserDefaults.standard.set(value, forKey: key) }
}

enum Tone: String, CaseIterable, Identifiable {
    case `default`, professional, friendly, formal, casual
    var id: String { rawValue }
    var title: String {
        switch self { case .default: "自然"; case .professional: "專業"; case .friendly: "友善"; case .formal: "正式"; case .casual: "口語" }
    }
    var instruction: String {
        switch self {
        case .default: ""
        case .professional: "Regardless of the source's tone, use a professional, precise, and polished tone."
        case .friendly: "Regardless of the source's tone, use a friendly, warm, and approachable tone."
        case .formal: "Regardless of the source's tone, use a formal and respectful tone."
        case .casual: "Regardless of the source's tone, use a casual, conversational, and relaxed tone."
        }
    }
}

@MainActor
final class TranslatorViewModel: ObservableObject {
    @Published var source = ""
    @Published var output = ""
    @Published var error = ""
    @Published var isTranslating = false
    private let settings: AppSettings
    private var task: Task<Void, Never>?

    init(settings: AppSettings) { self.settings = settings }
    deinit { task?.cancel() }

    func translate() {
        let text = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        guard !settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            error = "請先在設定中儲存 Gemini API Key。"
            return
        }
        task?.cancel()
        output = ""
        error = ""
        isTranslating = true
        let settings = settings
        task = Task { [weak self] in
            defer { self?.isTranslating = false }
            do {
                try await GeminiService.translate(text: text, target: settings.target == "zh-Hant" ? "Traditional Chinese" : "English", tone: settings.tone, model: settings.model, apiKey: settings.apiKey, promptTemplate: settings.promptTemplate) { [weak self] delta in
                    Task { @MainActor in self?.output += delta }
                }
            } catch is CancellationError {
            } catch { self?.error = error.localizedDescription }
        }
    }

    func clear() { task?.cancel(); source = ""; output = ""; error = "" }
    func copy() { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(output, forType: .string) }
}

struct TranslatorView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var translator: TranslatorViewModel

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("NextAI 翻譯").font(.title2.bold())
                Spacer()
                SettingsLink { Image(systemName: "gearshape") }
            }
            InputTextView(
                text: $translator.source,
                fontSize: settings.contentFontSize,
                placeholder: "輸入或貼上想翻譯的內容"
            )
                .padding(6)
                .frame(minHeight: 180, maxHeight: .infinity)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
                .accessibilityLabel("原文")

            HStack {
                Button("繁體中文") { settings.target = "zh-Hant" }.buttonStyle(.bordered).tint(settings.target == "zh-Hant" ? .accentColor : .gray)
                Button("English") { settings.target = "en" }.buttonStyle(.bordered).tint(settings.target == "en" ? .accentColor : .gray)
                Picker("語調", selection: $settings.tone) { ForEach(Tone.allCases) { Text($0.title).tag($0) } }.frame(width: 130)
                Spacer()
                Button("清除", action: translator.clear)
                Button(translator.isTranslating ? "翻譯中…" : "翻譯") { translator.translate() }
                    .keyboardShortcut(.return, modifiers: .command).disabled(translator.source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || translator.isTranslating)
            }

            ScrollView {
                Text(translator.output.isEmpty ? "翻譯結果會顯示在這裡" : translator.output)
                    .font(.system(size: settings.contentFontSize))
                    .foregroundStyle(translator.output.isEmpty ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .topLeading).textSelection(.enabled).padding(12)
            }
            .frame(minHeight: 180, maxHeight: .infinity)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
            .accessibilityLabel("翻譯結果")
            HStack {
                if translator.isTranslating {
                    ProgressView().controlSize(.small)
                    Text("正在翻譯…").foregroundStyle(.secondary)
                }
                if !translator.error.isEmpty {
                    Text(translator.error).foregroundStyle(.red).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                }
                Spacer(minLength: 0)
                Button("複製結果", action: translator.copy).disabled(translator.output.isEmpty)
            }
        }
        .padding(20)
        .frame(minWidth: 620, minHeight: 660)
        .onExitCommand { NSApp.keyWindow?.orderOut(nil) }
    }
}

struct InputTextView: NSViewRepresentable {
    @Binding var text: String
    let fontSize: Double
    let placeholder: String

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true

        let textView = PlaceholderTextView()
        textView.delegate = context.coordinator
        textView.placeholder = placeholder
        textView.font = .systemFont(ofSize: fontSize)
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.string = text
        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? PlaceholderTextView else { return }
        if textView.string != text { textView.string = text }
        textView.font = .systemFont(ofSize: fontSize)
        textView.placeholder = placeholder
        textView.needsDisplay = true
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: InputTextView
        init(parent: InputTextView) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            parent.text = (notification.object as? NSTextView)?.string ?? ""
        }
    }
}

final class PlaceholderTextView: NSTextView {
    var placeholder = ""

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, !placeholder.isEmpty else { return }
        let x = textContainerInset.width + (textContainer?.lineFragmentPadding ?? 0)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font ?? .systemFont(ofSize: NSFont.systemFontSize),
            .foregroundColor: NSColor.placeholderTextColor
        ]
        placeholder.draw(at: NSPoint(x: x, y: textContainerInset.height), withAttributes: attributes)
    }

    override func didChangeText() {
        super.didChangeText()
        needsDisplay = true
    }
}

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @State private var saveMessage = ""

    var body: some View {
        Form {
            Section("Gemini") {
                SecureField("API Key", text: $settings.apiKey)
                HStack { Button("儲存 API Key") { do { try settings.saveAPIKey(); saveMessage = "已儲存到 Keychain" } catch { saveMessage = error.localizedDescription } }; Text(saveMessage).foregroundStyle(.secondary) }
                TextField("模型", text: $settings.model)
                HStack {
                    Button("讀取模型", action: settings.loadModels)
                    if !settings.models.isEmpty {
                        Picker("可用模型", selection: $settings.model) {
                            ForEach(settings.models, id: \.self) { Text($0).tag($0) }
                        }
                        .labelsHidden()
                        .frame(maxWidth: .infinity)
                    }
                }
                if !settings.modelError.isEmpty { Text(settings.modelError).foregroundStyle(.red) }
            }
            Section("操作") {
                TextField("全域快捷鍵（⌥⌘ + 單一字母）", text: Binding(get: { settings.hotkeyKey }, set: { settings.hotkeyKey = String($0.lowercased().filter(\.isLetter).prefix(1)) }))
                Toggle("叫出時自動翻譯剪貼簿", isOn: $settings.autoTranslateClipboard)
                HStack { Text("內容字級"); Slider(value: $settings.contentFontSize, in: 12...40, step: 1); Text("\(Int(settings.contentFontSize))") }
            }
            Section("提示詞") {
                Text("使用 {target} 代表目標語言。")
                TextEditor(text: $settings.promptTemplate).frame(minHeight: 140)
                Button("還原預設") { settings.promptTemplate = AppSettings.defaultPrompt }
            }
        }
        .formStyle(.grouped).padding().frame(minWidth: 560, idealWidth: 620, minHeight: 620)
    }
}

enum KeychainStore {
    private static let service = "com.flosean.NextAITranslator"
    private static let account = "gemini-api-key"

    static func load() -> String {
        let query: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account, kSecReturnData: true]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    static func save(_ value: String) throws {
        let query: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account]
        SecItemDelete(query as CFDictionary)
        guard !value.isEmpty else { return }
        var item = query
        item[kSecValueData] = Data(value.utf8)
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else { throw GeminiError.message("無法儲存 API Key（\(status)）。") }
    }
}
