# NextAI 翻譯

極簡、快速、低資源占用的 Windows 原生翻譯小工具。

打開視窗 → 貼上文字 → 選語言 → 翻譯。就這麼單純，沒有多餘的花俏功能。

採用 **.NET 8 WPF** 從零打造，取代了先前的 Tauri + WebView2 + React 版本。不含 Node、不含 webview，幾乎零第三方相依——只用 .NET 內建函式庫與 WPF。閒置 CPU 趨近於 0、記憶體約 70–110 MB。

---

## 功能

- **純貼上翻譯**：單一視窗，貼上文字、選目標語言、即時串流顯示結果。
- **多語言**：繁體中文、簡體中文、English、日本語、한국어、Français、Deutsch、Español（自動偵測來源語言）。
- **多 LLM 供應商**：Gemini 與 OpenAI（以及任何 OpenAI 相容端點），SSE 串流輸出。
- **自動列出模型**：填入 API Key 後自動抓取該供應商可用的模型清單供選擇。
- **語調**：默認（自然）/ 專業 / 友善 / 正式 / 口語，主視窗直接切換。
- **可編輯提示詞**：檢視與自訂送給模型的系統提示（以 `{target}` 代表目標語言），可一鍵還原預設。
- **全域熱鍵**：可自訂組合（預設 `Ctrl+Alt+Z`）叫出視窗；可選「自動貼上剪貼簿並翻譯」。
- **系統匣常駐**：關閉視窗只隱藏，仍在系統匣；單一實例。
- **深色主題**＋自訂 App 圖標。
- **介面縮放**（100–200%，`Ctrl` `+`/`-`/`0`）與**獨立的翻譯字級**（在文字框上 `Ctrl`＋滾輪），適合 4K 螢幕。

---

## 系統需求

- Windows 10/11
- [.NET 8 Desktop Runtime](https://dotnet.microsoft.com/download/dotnet/8.0)（執行交付的 exe 需要；自行建置 self-contained 版則免）

## 使用

1. 執行 `NextAITranslator.exe`（常駐系統匣）。
2. 按 `Ctrl+Alt+Z` 或雙擊系統匣圖示叫出視窗。
3. 點左下角「設定」→ 選供應商 → 貼上 API Key → 從模型下拉選一個 → 儲存。
4. 貼上文字 → 選語言/語調 → 按「翻譯」。

設定檔（純文字）位於 `%APPDATA%\NextAITranslator\config.json`。

---

## 開發

需求：.NET 8 SDK。

```powershell
# 執行（除錯）
dotnet run --project app/NextAITranslator.csproj

# 打包單一 exe（框架相依，需目標機器已裝 .NET 8 Desktop Runtime）
dotnet publish app/NextAITranslator.csproj -c Release -r win-x64 --self-contained false `
  -p:PublishSingleFile=true -o dist-fd
```

專案結構與架構說明見 [CLAUDE.md](CLAUDE.md)。

## 授權

[AGPL-3.0](LICENSE)
