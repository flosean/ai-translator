import AppKit
import ServiceManagement
import SwiftUI

@main
struct NextAITranslatorMacApp: App {
    @Environment(\.openWindow) private var openWindow
    @StateObject private var settings: AppSettings
    @StateObject private var translator: TranslatorViewModel
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        let settings = AppSettings()
        _settings = StateObject(wrappedValue: settings)
        _translator = StateObject(wrappedValue: TranslatorViewModel(settings: settings))
    }

    var body: some Scene {
        Window("NextAI 翻譯", id: "translator") {
            TranslatorView(settings: settings, translator: translator)
                .onAppear {
                    appDelegate.showTranslator = showTranslator
                    HotkeyManager.shared.register(key: settings.hotkeyKey)
                }
        }
        .defaultSize(width: 660, height: 680)
        .windowStyle(.hiddenTitleBar)
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
        openWindow(id: "translator")
        if settings.autoTranslateClipboard, let text = NSPasteboard.general.string(forType: .string), !text.isEmpty {
            translator.source = text
            translator.translate()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var showTranslator: (() -> Void)?

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showTranslator?()
        return true
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NotificationCenter.default.addObserver(forName: .showTranslator, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.showTranslator?() }
        }
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
    private let apiKeyFile: URL
    private let defaults: UserDefaults
    private var modelTask: Task<Void, Never>?

    init(defaults: UserDefaults = .standard, apiKey: String? = nil, apiKeyFile: URL = APIKeyStore.fileURL) {
        self.defaults = defaults
        self.apiKeyFile = apiKeyFile
        self.apiKey = apiKey ?? APIKeyStore.load(from: apiKeyFile)
        let storedModel = defaults.string(forKey: "model")
        model = storedModel == "gemini-2.0-flash" ? "gemini-3.5-flash" : (storedModel ?? "gemini-3.5-flash")
        target = defaults.string(forKey: "target") == "en" ? "en" : "zh-Hant"
        tone = Tone(rawValue: defaults.string(forKey: "tone") ?? "default") ?? .default
        autoTranslateClipboard = defaults.object(forKey: "autoTranslateClipboard") as? Bool ?? false
        let fontSize = defaults.object(forKey: "contentFontSize") as? Double ?? 16
        contentFontSize = fontSize.isFinite ? min(max(fontSize, 12), 40) : 16
        promptTemplate = defaults.string(forKey: "promptTemplate") ?? Self.defaultPrompt
        let storedKey = defaults.string(forKey: "hotkeyKey")?.lowercased() ?? "z"
        hotkeyKey = storedKey.count == 1 && storedKey.allSatisfy({ $0.isASCII && $0.isLetter }) ? storedKey : "z"
    }

    func saveAPIKey() throws {
        apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        try APIKeyStore.save(apiKey, to: apiKeyFile)
    }
    func loadModels() {
        modelTask?.cancel()
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        models = []
        modelError = ""
        modelTask = Task {
            do {
                let result = try await GeminiService.listModels(apiKey: key)
                guard !Task.isCancelled, key == apiKey.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
                models = result
                if !model.isEmpty && !models.contains(model) { models.insert(model, at: 0) }
                modelError = result.isEmpty ? "沒有可用的 Gemini 模型。" : ""
            } catch {
                guard !Task.isCancelled, key == apiKey.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
                modelError = error.localizedDescription
            }
        }
    }

    private func save(_ key: String, _ value: Any) { defaults.set(value, forKey: key) }
}

enum Tone: String, CaseIterable, Identifiable, Sendable {
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
    typealias Translation = @Sendable (String, String, Tone, String, String, String,
        @escaping @MainActor @Sendable (String) -> Void) async throws -> Void
    @Published var source = ""
    @Published var output = ""
    @Published var error = ""
    @Published var isTranslating = false
    private let settings: AppSettings
    private var task: Task<Void, Never>?
    private var generation = 0
    private let translateText: Translation

    init(settings: AppSettings, translate: @escaping Translation = GeminiService.translate) {
        self.settings = settings
        translateText = translate
    }
    deinit { task?.cancel() }

    func translate() {
        let text = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        cancelTranslation()
        let apiKey = settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else {
            error = "請先在設定中儲存 Gemini API Key。"
            return
        }
        output = ""
        error = ""
        isTranslating = true
        let generation = generation
        let target = settings.target == "zh-Hant" ? "Traditional Chinese" : "English"
        let tone = settings.tone
        let model = settings.model.trimmingCharacters(in: .whitespacesAndNewlines)
        let template = settings.promptTemplate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? AppSettings.defaultPrompt : settings.promptTemplate
        let translateText = translateText
        task = Task { [weak self] in
            defer {
                if self?.generation == generation { self?.isTranslating = false }
            }
            do {
                try await translateText(text, target, tone, model, apiKey, template) { [weak self] delta in
                    guard self?.generation == generation else { return }
                    self?.output += delta
                }
            } catch {
                guard !Task.isCancelled, self?.generation == generation else { return }
                self?.error = error.localizedDescription
            }
        }
    }

    private func cancelTranslation() {
        generation += 1
        task?.cancel()
        task = nil
        isTranslating = false
    }

    func clear() { cancelTranslation(); source = ""; output = ""; error = "" }
    func copy() { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(output, forType: .string) }
}

struct TranslatorView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var translator: TranslatorViewModel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Label("自動偵測", systemImage: "globe")
                    .foregroundStyle(.secondary)
                Image(systemName: "arrow.right").foregroundStyle(.tertiary)
                Picker("目標語言", selection: $settings.target) {
                    Text("繁體中文").tag("zh-Hant")
                    Text("English").tag("en")
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .controlSize(.regular)
                .frame(width: 190)
                Spacer(minLength: 8)
                Menu {
                    ForEach(Tone.allCases) { tone in
                        Button { settings.tone = tone } label: {
                            if settings.tone == tone {
                                Label(tone.title, systemImage: "checkmark")
                            } else {
                                Text(tone.title)
                            }
                        }
                    }
                } label: {
                    Label(settings.tone.title, systemImage: "slider.horizontal.3")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .padding(.horizontal, 10).frame(height: 28)
                .modifier(TranslationGlass())
                .help("翻譯語調")
                .accessibilityLabel("翻譯語調：\(settings.tone.title)")
            }
            .font(.system(size: 13, weight: .medium))

            ResizableTranslationPanes {
                VStack(spacing: 6) {
                    HStack(spacing: 10) {
                        Text("原文").fontWeight(.medium)
                        Spacer()
                        if !translator.source.isEmpty {
                            Text("\(translator.source.count) 字").monospacedDigit()
                        }
                        Button("清除內容", systemImage: "xmark", action: translator.clear)
                            .labelStyle(.iconOnly).buttonStyle(.plain)
                            .frame(width: 24, height: 24)
                            .contentShape(Circle())
                            .help("清除內容")
                    }
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                    InputTextView(
                        text: $translator.source,
                        fontSize: settings.contentFontSize,
                        placeholder: "輸入或貼上想翻譯的內容…"
                    )
                    .frame(minHeight: 80, maxHeight: .infinity)
                    .accessibilityLabel("原文")
                }
                .padding(10)
                .background(paneColor, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.primary.opacity(0.05)))
            } output: {
                VStack(spacing: 6) {
                    HStack {
                        Text("譯文").fontWeight(.medium)
                        Text(settings.target == "zh-Hant" ? "繁體中文" : "English")
                            .foregroundStyle(.tertiary)
                        Spacer()
                        Button("複製結果", systemImage: "doc.on.doc", action: translator.copy)
                            .labelStyle(.iconOnly)
                            .translationButtonStyle()
                            .buttonBorderShape(.capsule)
                            .disabled(translator.output.isEmpty)
                            .help("複製結果")
                    }
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                    if translator.output.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "character.bubble").font(.system(size: 28, weight: .light))
                                .foregroundStyle(.tertiary)
                            Text(translator.isTranslating ? "正在等待譯文…" : "翻譯結果會顯示在這裡")
                                .font(.system(size: 13)).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollView {
                            Text(translator.output)
                                .font(.system(size: settings.contentFontSize))
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                                .textSelection(.enabled)
                        }
                        .accessibilityLabel("翻譯結果")
                    }
                }
                .padding(10)
                .background(paneColor, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.primary.opacity(0.05)))
            }

            if !translator.error.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text(translator.error).lineLimit(3).textSelection(.enabled)
                        .help(translator.error)
                }
                .font(.system(size: 12))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                .accessibilityLabel("翻譯錯誤：\(translator.error)")
            }

            HStack(spacing: 10) {
                SettingsLink { Image(systemName: "gearshape").frame(width: 20, height: 20) }
                    .translationButtonStyle()
                    .buttonBorderShape(.circle)
                    .help("設定")
                    .accessibilityLabel("設定")
                if translator.isTranslating {
                    ProgressView().controlSize(.small)
                    Text("正在翻譯…").font(.system(size: 12)).foregroundStyle(.secondary)
                } else {
                    Text(settings.model).font(.system(size: 11)).foregroundStyle(.tertiary)
                        .lineLimit(1).truncationMode(.middle)
                }
                Spacer(minLength: 8)
                Text("⌘ ↩").font(.system(size: 12)).foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
                Button(action: translator.translate) {
                    Label("翻譯", systemImage: "arrow.up")
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 10).padding(.vertical, 3)
                }
                .translationButtonStyle(prominent: true)
                .buttonBorderShape(.capsule)
                .controlSize(.regular)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(translator.source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || translator.isTranslating)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(minWidth: 560, minHeight: 520)
        .modifier(TranslationWindowBackground())
        .onExitCommand { NSApp.keyWindow?.orderOut(nil) }
    }

    private var paneColor: Color {
        Color(nsColor: .textBackgroundColor).opacity(colorScheme == .dark ? 0.45 : 0.72)
    }
}

private struct TranslationWindowBackground: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @ViewBuilder func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(Color(nsColor: .windowBackgroundColor))
        } else if #available(macOS 15, *) {
            content.containerBackground(.thinMaterial, for: .window)
        } else {
            content.background(.regularMaterial)
        }
    }
}

private struct TranslationGlass: ViewModifier {
    @ViewBuilder func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content.glassEffect(.regular.interactive(), in: Capsule())
        } else {
            content.background(.regularMaterial, in: Capsule())
        }
    }
}

private extension View {
    @ViewBuilder func translationButtonStyle(prominent: Bool = false) -> some View {
        if #available(macOS 26, *) {
            if prominent { buttonStyle(.glassProminent).tint(.accentColor) }
            else { buttonStyle(.glass) }
        } else {
            if prominent { buttonStyle(.borderedProminent) }
            else { buttonStyle(.bordered) }
        }
    }
}

struct ResizableTranslationPanes<Input: View, Output: View>: View {
    @ViewBuilder var input: Input
    @ViewBuilder var output: Output
    @State private var ratio = 0.5
    @State private var dragStartHeight: CGFloat?

    static func inputHeight(available: CGFloat, ratio: Double) -> CGFloat {
        min(max(available * ratio, 150), max(150, available - 120))
    }

    var body: some View {
        GeometryReader { geometry in
            let available = max(0, geometry.size.height - 16)
            let height = Self.inputHeight(available: available, ratio: ratio)
            VStack(spacing: 0) {
                input.frame(height: height)
                ZStack {
                    Color.clear
                    Capsule().fill(.tertiary).frame(width: 36, height: 4)
                }
                .frame(height: 16)
                .contentShape(Rectangle())
                .help("上下拖曳以調整原文與翻譯結果的比例")
                .accessibilityLabel("調整上下區塊比例")
                .accessibilityAdjustableAction { direction in
                    let change = direction == .increment ? 0.05 : -0.05
                    ratio = Self.inputHeight(available: available, ratio: ratio + change) / max(available, 1)
                }
                .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("translationPanes"))
                    .onChanged { value in
                        if dragStartHeight == nil { dragStartHeight = height }
                        ratio = Self.inputHeight(available: available,
                            ratio: ((dragStartHeight ?? height) + value.translation.height) / max(available, 1)) / max(available, 1)
                    }
                    .onEnded { _ in dragStartHeight = nil })
                output.frame(height: max(0, available - height))
            }
            .coordinateSpace(name: "translationPanes")
        }
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
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true

        let textView = PlaceholderTextView()
        textView.delegate = context.coordinator
        textView.placeholder = placeholder
        textView.font = .systemFont(ofSize: fontSize)
        textView.drawsBackground = false
        textView.textColor = .labelColor
        textView.insertionPointColor = .labelColor
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainerInset = NSSize(width: 0, height: 2)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.string = text
        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
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
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var settings: AppSettings
    @ObservedObject private var hotkey = HotkeyManager.shared
    @State private var saveMessage = ""
    @State private var loginItemStatus = SMAppService.mainApp.status
    @State private var loginItemError = ""

    var body: some View {
        ScrollView {
            Form {
                Section("Gemini") {
                    LabeledContent("API Key") {
                        HStack(spacing: 8) {
                            SecureField("API Key", text: $settings.apiKey).labelsHidden()
                            Button("儲存") {
                                do { try settings.saveAPIKey(); saveMessage = "已儲存到本機設定檔" }
                                catch { saveMessage = error.localizedDescription }
                            }
                            .translationButtonStyle(prominent: true)
                            .accessibilityLabel("儲存 API Key")
                        }
                    }
                    .accessibilityElement(children: .contain)
                    if !saveMessage.isEmpty { Text(saveMessage).font(.caption).foregroundStyle(.secondary) }
                    LabeledContent("模型") {
                        HStack(spacing: 8) {
                            TextField("模型", text: $settings.model).labelsHidden()
                            Button("讀取模型", action: settings.loadModels).translationButtonStyle()
                        }
                    }
                    .accessibilityElement(children: .contain)
                    if !settings.models.isEmpty {
                        Picker("可用模型", selection: $settings.model) {
                            ForEach(settings.models, id: \.self) { Text($0).tag($0) }
                        }
                    }
                    if !settings.modelError.isEmpty { Text(settings.modelError).foregroundStyle(.red) }
                }
                Section("操作") {
                    Toggle("登入時自動啟動", isOn: Binding(
                        get: { loginItemStatus == .enabled || loginItemStatus == .requiresApproval },
                        set: setLaunchAtLogin
                    ))
                    if loginItemStatus == .requiresApproval {
                        Text("請在系統設定的登入項目中允許 NextAI 翻譯。")
                            .font(.caption).foregroundStyle(.secondary)
                        Button("開啟登入項目設定") { SMAppService.openSystemSettingsLoginItems() }
                    }
                    if !loginItemError.isEmpty { Text(loginItemError).foregroundStyle(.red) }
                    LabeledContent("全域快捷鍵") {
                        HStack(spacing: 6) {
                            Text("⌥⌘")
                            TextField("快捷鍵字母", text: Binding(get: { settings.hotkeyKey }, set: {
                                settings.hotkeyKey = String($0.lowercased().filter { $0.isASCII && $0.isLetter }.prefix(1))
                            }))
                            .labelsHidden().frame(width: 40)
                            Text("單一英文字母").font(.caption).foregroundStyle(.secondary)
                            Spacer(minLength: 0)
                        }
                    }
                    if !hotkey.error.isEmpty { Text(hotkey.error).foregroundStyle(.red) }
                    Toggle("叫出時自動翻譯剪貼簿", isOn: $settings.autoTranslateClipboard)
                    LabeledContent("內容字級") {
                        HStack(spacing: 8) {
                            Slider(value: $settings.contentFontSize, in: 12...40, step: 1)
                                .accessibilityLabel("內容字級")
                            Text("\(Int(settings.contentFontSize))").monospacedDigit().frame(width: 24)
                        }
                    }
                }
                Section("提示詞") {
                    HStack {
                        Text("使用 {target} 代表目標語言。")
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("還原預設") { settings.promptTemplate = AppSettings.defaultPrompt }
                    }
                    TextEditor(text: $settings.promptTemplate)
                        .font(.system(size: 12))
                        .scrollContentBackground(.hidden)
                        .padding(4).frame(height: 120)
                        .background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.secondary.opacity(0.2)))
                        .accessibilityLabel("提示詞範本")
                }
            }
            .formStyle(.columns)
            .textFieldStyle(.roundedBorder)
            .toggleStyle(.checkbox)
            .controlSize(.small)
            .padding(14)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HStack {
                Spacer()
                Button("完成") { dismiss() }
                    .translationButtonStyle(prominent: true)
                    .keyboardShortcut(.cancelAction)
                    .help("關閉設定（Esc）")
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(.regularMaterial)
            .overlay(alignment: .top) { Divider() }
        }
        .frame(width: 560, height: 440)
        .modifier(TranslationWindowBackground())
        .onAppear { loginItemStatus = SMAppService.mainApp.status }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            loginItemStatus = SMAppService.mainApp.status
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        loginItemError = ""
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            loginItemError = "無法變更自動啟動設定：\(error.localizedDescription)"
        }
        loginItemStatus = SMAppService.mainApp.status
    }
}

enum APIKeyStore {
    static let fileURL = URL.applicationSupportDirectory
        .appendingPathComponent("NextAITranslator", isDirectory: true)
        .appendingPathComponent("credentials.json")

    static func load(from url: URL) -> String {
        guard let data = try? Data(contentsOf: url),
              let values = try? JSONDecoder().decode([String: String].self, from: data) else { return "" }
        return values["apiKey"] ?? ""
    }

    static func save(_ value: String, to url: URL) throws {
        let manager = FileManager.default
        if value.isEmpty {
            if manager.fileExists(atPath: url.path) { try manager.removeItem(at: url) }
            return
        }
        let directory = url.deletingLastPathComponent()
        try manager.createDirectory(at: directory, withIntermediateDirectories: true,
                                    attributes: [.posixPermissions: 0o700])
        try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        let data = try JSONEncoder().encode(["apiKey": value])
        try data.write(to: url, options: .atomic)
        try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
