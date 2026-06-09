# CLAUDE.md

Guidance for Claude Code when working in this repository.

## What this is

**NextAI 翻譯** — a minimal, fast, native Windows translation app. Open a window, paste
text, pick a target language, translate. That is the whole scope, on purpose.

It is a from-scratch **.NET 8 WPF** rewrite that replaced an earlier Tauri/WebView2 +
React app (deleted). The whole project lives in `app/`. There is no Node, no webview,
and essentially no NuGet dependencies — only the .NET BCL + WPF.

## Commands

Run from `app/`:

- `dotnet build app/NextAITranslator.csproj -c Debug` — build.
- `dotnet run --project app/NextAITranslator.csproj` — run (window shows). Pass
  `--silently` to start hidden in the tray.
- Publish the delivered single-file exe (framework-dependent; needs .NET 8 Desktop
  Runtime on the target machine):
  ```
  dotnet publish app/NextAITranslator.csproj -c Release -r win-x64 --self-contained false `
    -p:PublishSingleFile=true -o dist-fd
  ```
  The deliverable is `dist-fd/NextAITranslator.exe` (~0.2 MB).

There is no test project; verification is done with throwaway console harnesses against a
local `HttpListener` serving canned SSE/JSON (see git history), then removed.

## Architecture (`app/`)

- `App.xaml.cs` — startup: single-instance mutex, `--silently`, loads config, creates the
  main window + global hotkey + tray, global exception handler.
- `MainWindow.*` — the single translate window (input / language dropdown / clear /
  settings / output / copy / translate). Streamed tokens are coalesced and flushed to the
  UI in batches (`OnDelta`/`FlushPending`). Ctrl+/-/0 adjusts UI scale live.
- `SettingsWindow.*` — provider, API key, base URL, model (editable ComboBox auto-filled
  from the provider's `/models` endpoint), hotkey, UI scale, auto-translate toggle. Edits
  use working copies so Cancel never mutates the live config.
- `Core/` — `IEngine` + `OpenAICompatibleEngine` (OpenAI and all compatible providers) +
  `GeminiEngine`; `Sse` (shared HttpClient + SSE reader); `Prompts` (translation prompt,
  source language auto-detected by the model); `TranslateService`; `ModelService`.
- `Interop/` — `HotKeyManager` (Win32 RegisterHotKey + `Ctrl+Alt+Z`-style parsing),
  `DarkTitleBar` (dark OS title bar via DwmSetWindowAttribute).
- `Storage/AppConfig.cs` — plain-text JSON at `%APPDATA%\NextAITranslator\config.json`.
- `Tray/TrayManager.cs` — NotifyIcon, context menu, double-click to open.
- `Theme.xaml` — dark theme (merged in `App.xaml`). `Assets/app.ico` — app icon.

## Adding an LLM provider

Most providers are OpenAI-compatible: they need no new code, just a base URL + model
(point `OpenAICompatibleEngine` at them). Only genuinely different APIs (like Gemini) get
their own `IEngine`. If you add one, also handle it in `TranslateService` and
`ModelService`, and add it to the provider ComboBox in `SettingsWindow.xaml`.

## Conventions

- 4-space indent, file-scoped namespaces, nullable enabled.
- UI text is Traditional Chinese.
- Beware WinForms/WPF type clashes (`Application`, `Clipboard`, `MessageBox`,
  `KeyEventArgs`) — qualify with `System.Windows.*` when ambiguous.
- Never bind `CornerRadius` (or other struct properties) to a mismatched resource type —
  it throws at XAML load (crash code `0xE0434352`).
