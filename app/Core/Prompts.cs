using System.Collections.Generic;

namespace NextAITranslator.Core
{
    /// <summary>Builds the translation prompt. Source language is auto-detected by the model.</summary>
    public static class Prompts
    {
        private static readonly Dictionary<string, string> LangNames = new()
        {
            ["zh-Hant"] = "Traditional Chinese",
            ["zh-Hans"] = "Simplified Chinese",
            ["en"] = "English",
            ["ja"] = "Japanese",
            ["ko"] = "Korean",
            ["fr"] = "French",
            ["de"] = "German",
            ["es"] = "Spanish",
        };

        public static string LangName(string code) =>
            LangNames.TryGetValue(code, out var n) ? n : code;

        public static (string system, string user) Translate(string targetCode, string text)
        {
            var target = LangName(targetCode);
            var system =
                $"You are a professional translation engine. Translate the user's text into {target}. " +
                "Only output the translated text — no explanations, no notes, no commentary, " +
                "no original text, and no surrounding quotation marks. Preserve the original meaning, " +
                "tone, and formatting (line breaks, lists) as closely as possible.";
            return (system, text);
        }
    }
}
