# NextAI 翻譯

Windows 上的翻譯小工具。把文字貼進去、選個目標語言、按翻譯，結果就即時跑出來，大概就這樣。

本來是用 Tauri + WebView2 + React 做的，後來整個改用 .NET 8 WPF 重寫。現在沒有 Node、沒有 webview，除了 .NET 本身跟 WPF 以外幾乎不依賴別的東西。閒置時 CPU 基本上是 0，記憶體大概落在 70～110 MB。

## 能做什麼

目標語言支援繁體中文和 English，直接按按鈕快速切換；來源語言交給模型自己判斷，不用手動選。

翻譯是走 LLM 的，可以接 Gemini 或 OpenAI，其他 OpenAI 相容的端點也行——填好 base URL 跟模型名稱就能用。輸出用 SSE 串流，所以字是邊收邊顯示的。API Key 填好之後會自動去抓那家供應商有哪些模型給你挑，懶得記模型名稱也沒關係。

語調有默認（自然）、專業、友善、正式、口語幾種，在主視窗直接切換。如果想更細地控制，送給模型的提示詞也能自己改，用 `{target}` 代表目標語言；改壞了按「還原預設」就回來了。

剩下一些雜項：

- 全域熱鍵叫出視窗，預設 `Ctrl+Alt+Z`，可以自己改。也能設成「一叫出來就自動拿剪貼簿的東西去翻」。
- 鍵盤就能走完整個流程：`Ctrl+Enter` 直接翻譯，`Esc` 把視窗收回系統匣。
- 輸入框和輸出框的高度比例可以調：按住中間那條控制列上下拖就行，調完會記住。
- 關視窗只是縮回系統匣，程式還活著；而且同時只會有一個在跑。
- 深色介面。
- 整個介面可以縮放（`Ctrl` 加 `+` / `-` / `0`）；翻譯文字本身的字級另外用 `Ctrl` + 滾輪調，在 4K 螢幕上看比較不吃力。

## 需要什麼

Windows 10 或 11，外加 [.NET 8 Desktop Runtime](https://dotnet.microsoft.com/download/dotnet/8.0)。這是跑現成 exe 時需要的；如果自己 build 成 self-contained 版本就不用另外裝。

## 怎麼用

開起來之後會待在系統匣。按 `Ctrl+Alt+Z` 或雙擊系統匣圖示把視窗叫出來。第一次用先點左下角的「設定」，選供應商、貼上 API Key、從模型下拉挑一個，存檔。接著就是貼文字、按「繁體中文」或「English」切換目標語言、選語調、按翻譯。

設定檔放在 `%APPDATA%\NextAITranslator\config.json`，純文字，想直接手動編輯也可以。

## 開發

需要 .NET 8 SDK。

```powershell
# 跑起來（除錯）
dotnet run --project app/NextAITranslator.csproj

# 打包成單一 exe（框架相依，目標機器要先有 .NET 8 Desktop Runtime）
dotnet publish app/NextAITranslator.csproj -c Release -r win-x64 --self-contained false `
  -p:PublishSingleFile=true -o dist-fd
```

版本號是用 MinVer 從 git tag 帶出來的，要發版就在對應的 commit 上打一個 `vX.Y.Z` 的 tag，不用去手改檔案裡的版本。架構跟各檔案的職責寫在 [CLAUDE.md](CLAUDE.md)。

## macOS（Apple Silicon）

`mac/` 是原生 SwiftUI 版本，限定 macOS 14 以上與 Apple Silicon。它保留完整輸入／輸出翻譯介面、Gemini SSE 串流、選單列常駐、`⌥⌘Z` 全域快捷鍵，以及剪貼簿自動翻譯；API Key 存在 macOS Keychain。

需要 Xcode 16 以上。最方便是用 Xcode 開啟 `mac/Package.swift` 後按 Run；也可在終端機執行：

```zsh
cd mac
swift run
```

首次啟動後從選單列的「設定」填入 Gemini API Key，按「儲存 API Key」，模型使用 `gemini-3.5-flash` 或按「讀取模型」後選擇可用模型。模型與其他偏好會自動保存；API Key 則只保存在 macOS Keychain。舊版的 `gemini-2.0-flash` 已被 Google 關閉，App 會自動改用 `gemini-3.5-flash`。

勾選「叫出時自動翻譯剪貼簿」後，按 `⌥⌘Z` 就會讀取剪貼簿並開始翻譯；快捷鍵的字母可在設定中改成另一個單一英文字母。

要建立可直接使用的 `.app`，在專案根目錄執行：

```zsh
mac/package-app.sh
```

成品在 `dist-mac/NextAI 翻譯.app`，拖進「應用程式」資料夾即可使用。

## 授權

[AGPL-3.0](LICENSE)
