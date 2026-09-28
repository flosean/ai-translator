# NextAI 翻譯

Windows 與 macOS 上的原生翻譯小工具。把文字貼進去、選個目標語言、按翻譯，結果就即時跑出來。以下先介紹 Windows 版，macOS 的安裝與操作請見下方專節。

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

輸入與翻譯結果的高度可透過中間控制列下方的水平分隔線調整：按住分隔線上下拖曳即可，兩區各保留最小可閱讀高度。

安裝後，開啟 App「設定」→「操作」，勾選「登入時自動啟動」，之後登入 Mac 就會啟動翻譯器；取消勾選即可關閉。若顯示需要允許，按「開啟登入項目設定」到 macOS 系統設定中允許。此選項以系統的登入項目狀態為準，從系統設定修改後，回到 App 也會更新。請從已打包的 `.app` 設定此功能；使用現有成品不需要 Xcode。

關閉翻譯視窗後，仍可從選單列、Dock 或全域快捷鍵重新開啟。清除或開始新翻譯會取消舊請求，較晚抵達的舊結果不會混入新譯文；快捷鍵被其他程式占用時，設定頁會顯示提示。

## 穩定性修正

- 兩版均支援多行 SSE 回應，忽略 Gemini 思考與非文字片段；API 錯誤或沒有譯文時顯示錯誤訊息。
- macOS 更新鑰匙圈金鑰時直接修改既有項目，避免先刪除後儲存失敗而遺失金鑰。
- Windows 可復原設定檔中的空值及不存在的供應商，儲存時以完整新檔取代舊檔；預設 Gemini 模型及舊的 `gemini-2.0-flash` 設定改用 `gemini-3.5-flash`。
- Windows 修正串流錯誤後殘留文字、Esc 隱藏時未記住視窗大小，以及登入啟動登錄位置不存在時無法啟用的問題。

`dist-mac/` 與 `.exe` 是本機打包成品，不納入 Git；從 GitHub 取得原始碼後需自行打包，或使用另外提供的成品。

## 授權

[AGPL-3.0](LICENSE)
