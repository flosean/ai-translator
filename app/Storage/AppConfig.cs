using System.Collections.Generic;
using System.IO;
using System.Text.Encodings.Web;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace NextAITranslator.Storage
{
    /// <summary>
    /// Per-provider settings (API key / base URL / model).
    /// </summary>
    public class ProviderConfig
    {
        public string ApiKey { get; set; } = "";
        public string BaseUrl { get; set; } = "";
        public string Model { get; set; } = "";
    }

    /// <summary>
    /// Plain-text JSON config stored under %APPDATA%\NextAITranslator\config.json.
    /// </summary>
    public class AppConfig
    {
        public string Provider { get; set; } = "gemini";
        public Dictionary<string, ProviderConfig> Providers { get; set; } = new();
        public string Hotkey { get; set; } = "Ctrl+Alt+Z";
        public bool AutoTranslate { get; set; } = false;
        public string LastTargetLang { get; set; } = "zh-Hant";

        /// <summary>UI zoom factor (1.0 = 100%). Clamped to [1.0, 2.0] on load.</summary>
        public double UiScale { get; set; } = 1.0;

        /// <summary>Font size (px) for the input/output translation text. Clamped to [12, 40] on load.</summary>
        public double ContentFontSize { get; set; } = 16.0;

        /// <summary>The default system prompt. Use {target} as a placeholder for the target language name.</summary>
        public const string DefaultPromptTemplate =
            "You are a professional translation engine. Translate the user's text into {target}. " +
            "Only output the translated text — no explanations, no notes, no commentary, " +
            "no original text, and no surrounding quotation marks. " +
            "Preserve the original meaning and formatting (line breaks, lists) as closely as possible.";

        /// <summary>Editable system prompt template. {target} is replaced with the target language.</summary>
        public string PromptTemplate { get; set; } = DefaultPromptTemplate;

        /// <summary>Output tone key: default / professional / friendly / formal / casual.</summary>
        public string Tone { get; set; } = "default";

        // ---- persistence ----

        private static readonly string Dir = Path.Combine(
            System.Environment.GetFolderPath(System.Environment.SpecialFolder.ApplicationData),
            "NextAITranslator");

        public static readonly string ConfigPath = Path.Combine(Dir, "config.json");

        private static readonly JsonSerializerOptions JsonOpts = new()
        {
            WriteIndented = true,
            DefaultIgnoreCondition = JsonIgnoreCondition.Never,
            // Keep '+', CJK, etc. literal so the file stays human-readable for manual edits.
            Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping,
        };

        public static AppConfig Load()
        {
            AppConfig cfg;
            try
            {
                if (File.Exists(ConfigPath))
                {
                    var json = File.ReadAllText(ConfigPath);
                    cfg = JsonSerializer.Deserialize<AppConfig>(json, JsonOpts) ?? new AppConfig();
                }
                else
                {
                    cfg = new AppConfig();
                }
            }
            catch
            {
                // Corrupt/unreadable config should never crash the app; fall back to defaults.
                cfg = new AppConfig();
            }

            cfg.EnsureDefaults();
            return cfg;
        }

        public void Save()
        {
            Directory.CreateDirectory(Dir);
            var json = JsonSerializer.Serialize(this, JsonOpts);
            File.WriteAllText(ConfigPath, json);
        }

        /// <summary>Make sure the providers we ship always have an entry with sane defaults.</summary>
        public void EnsureDefaults()
        {
            if (!Providers.TryGetValue("openai", out var openai))
            {
                openai = new ProviderConfig();
                Providers["openai"] = openai;
            }
            if (string.IsNullOrWhiteSpace(openai.BaseUrl)) openai.BaseUrl = "https://api.openai.com/v1";
            if (string.IsNullOrWhiteSpace(openai.Model)) openai.Model = "gpt-4o-mini";

            if (!Providers.TryGetValue("gemini", out var gemini))
            {
                gemini = new ProviderConfig();
                Providers["gemini"] = gemini;
            }
            if (string.IsNullOrWhiteSpace(gemini.BaseUrl)) gemini.BaseUrl = "https://generativelanguage.googleapis.com/v1beta";
            if (string.IsNullOrWhiteSpace(gemini.Model)) gemini.Model = "gemini-2.0-flash";

            if (string.IsNullOrWhiteSpace(Provider)) Provider = "gemini";
            if (string.IsNullOrWhiteSpace(Hotkey)) Hotkey = "Ctrl+Alt+Z";

            if (double.IsNaN(UiScale) || UiScale < 1.0) UiScale = 1.0;
            if (UiScale > 2.0) UiScale = 2.0;

            if (double.IsNaN(ContentFontSize) || ContentFontSize < 12.0) ContentFontSize = 16.0;
            if (ContentFontSize > 40.0) ContentFontSize = 40.0;

            if (string.IsNullOrWhiteSpace(PromptTemplate)) PromptTemplate = DefaultPromptTemplate;
            if (string.IsNullOrWhiteSpace(Tone)) Tone = "default";
        }

        public ProviderConfig CurrentProvider()
        {
            EnsureDefaults();
            return Providers.TryGetValue(Provider, out var p) ? p : Providers["gemini"];
        }
    }
}
