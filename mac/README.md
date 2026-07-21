# NextAI 翻譯 for macOS

原生 SwiftUI 版，限定 Apple Silicon 與 macOS 14 以上。沒有第三方套件。

## 執行

用 Xcode 開啟 `Package.swift` 後按 Run，或：

```zsh
swift run
```

從選單列「NextAI 翻譯」開啟設定，填入 Gemini API Key 後按「儲存 API Key」。模型預設為 `gemini-3.5-flash`，也可按「讀取模型」後選擇帳號可用的模型。Key 只會放進 macOS Keychain，模型、提示詞與介面偏好則放在 `UserDefaults`。舊版的 `gemini-2.0-flash` 已被 Google 關閉，App 會自動遷移成 `gemini-3.5-flash`。

預設全域快捷鍵是 `⌥⌘Z`，可在設定頁改成 `⌥⌘` 加任一英文字母。勾選「叫出時自動翻譯剪貼簿」後，按快捷鍵會帶入剪貼簿文字並直接翻譯。
