# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

**NextAI 翻譯** — a minimal, fast, native Windows translation app. Open a window, paste
text, pick a target language, translate. That is the whole scope, on purpose.

It is a from-scratch **.NET 8 WPF** rewrite that replaced an earlier Tauri/WebView2 +
React app (deleted). The whole project lives in `app/`. There is no Node, no webview,
and essentially no NuGet dependencies — only the .NET BCL + WPF.

## Commands

Run from the repo root:

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

## Versioning

The exe/assembly version is **derived from git tags by MinVer** (build-time only,
`PrivateAssets=all` — not shipped in the exe). There is no `<Version>` in the `.csproj`.

- Tags are `v`-prefixed (`MinVerTagPrefix=v`), e.g. `v1.0.0`. `v1.0.0` is the baseline.
- To cut a release: `git tag vX.Y.Z` on the commit you want, then `git push origin vX.Y.Z`.
  The next build of that commit reports `X.Y.Z`.
- Between tags, builds get an auto-incremented pre-release (e.g. `1.0.1-alpha.0.4+<sha>`),
  so never hand-edit the version — move the tag instead.

## Architecture (`app/`)

- `App.xaml.cs` — startup: single-instance mutex, `--silently`, loads config, creates the
  main window + global hotkey + tray, global exception handler.
- `MainWindow.*` — the single translate window (input / language + tone dropdowns /
  clear / settings + model label / output / copy / translate). Streamed tokens are
  coalesced and flushed to the UI in batches (`OnDelta`/`FlushPending`). Two independent
  size systems: Ctrl+/-/0 scales the whole UI (1.0–2.0), Ctrl+wheel over the text boxes
  sets the translation content font size (12–40 px).
- `SettingsWindow.*` — provider, API key, base URL, model (editable ComboBox auto-filled
  from the provider's `/models` endpoint), hotkey, UI scale, content font size, prompt
  template editor (with reset-to-default), auto-translate toggle. Edits use working
  copies so Cancel never mutates the live config; the scale/font dropdowns only persist
  if touched, so a wheel-set custom font size isn't clobbered on Save.
- `Core/` — `IEngine` + `OpenAICompatibleEngine` (OpenAI and all compatible providers) +
  `GeminiEngine`; `Sse` (shared HttpClient + SSE reader); `Prompts` (builds the system
  prompt from the editable template — `{target}` is replaced with the target language,
  source language auto-detected by the model — then appends the tone instruction;
  non-default tones override the source's tone); `TranslateService`; `ModelService`.
- `Interop/` — `HotKeyManager` (Win32 RegisterHotKey + `Ctrl+Alt+Z`-style parsing),
  `DarkTitleBar` (dark OS title bar via DwmSetWindowAttribute).
- `Storage/AppConfig.cs` — plain-text JSON at `%APPDATA%\NextAITranslator\config.json`.
  Holds per-provider settings, hotkey, prompt template (`DefaultPromptTemplate` is the
  canonical default), tone, UI scale, content font size; `EnsureDefaults()` clamps and
  back-fills everything on load so a hand-edited config never crashes the app.
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
- User-visible feature changes should also be reflected in `README.md` and
  `dist-fd/使用說明.txt` (the usage notes shipped beside the exe), both in Traditional
  Chinese.
