# NextAI 翻譯

Windows 上的翻譯小工具。把文字貼進去、選個目標語言、按翻譯，結果就即時跑出來，大概就這樣。

本來是用 Tauri + WebView2 + React 做的，後來整個改用 .NET 8 WPF 重寫。現在沒有 Node、沒有 webview，除了 .NET 本身跟 WPF 以外幾乎不依賴別的東西。閒置時 CPU 基本上是 0，記憶體大概落在 70～110 MB。

## 能做什麼

目標語言支援繁中、簡中、英、日、韓、法、德、西，來源語言交給模型自己判斷，不用手動選。

翻譯是走 LLM 的，可以接 Gemini 或 OpenAI，其他 OpenAI 相容的端點也行——填好 base URL 跟模型名稱就能用。輸出用 SSE 串流，所以字是邊收邊顯示的。API Key 填好之後會自動去抓那家供應商有哪些模型給你挑，懶得記模型名稱也沒關係。

語調有默認（自然）、專業、友善、正式、口語幾種，在主視窗直接切換。如果想更細地控制，送給模型的提示詞也能自己改，用 `{target}` 代表目標語言；改壞了按「還原預設」就回來了。

剩下一些雜項：

- 全域熱鍵叫出視窗，預設 `Ctrl+Alt+Z`，可以自己改。也能設成「一叫出來就自動拿剪貼簿的東西去翻」。
- 關視窗只是縮回系統匣，程式還活著；而且同時只會有一個在跑。
- 深色介面。
- 整個介面可以縮放（`Ctrl` 加 `+` / `-` / `0`）；翻譯文字本身的字級另外用 `Ctrl` + 滾輪調，在 4K 螢幕上看比較不吃力。

## 需要什麼

Windows 10 或 11，外加 [.NET 8 Desktop Runtime](https://dotnet.microsoft.com/download/dotnet/8.0)。這是跑現成 exe 時需要的；如果自己 build 成 self-contained 版本就不用另外裝。

## 怎麼用

開起來之後會待在系統匣。按 `Ctrl+Alt+Z` 或雙擊系統匣圖示把視窗叫出來。第一次用先點左下角的「設定」，選供應商、貼上 API Key、從模型下拉挑一個，存檔。接著就是貼文字、選語言跟語調、按翻譯。

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

## 授權

[AGPL-3.0](LICENSE)
