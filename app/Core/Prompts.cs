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

        /// <summary>Tone key -> extra instruction appended to the prompt. Empty means "as natural".</summary>
        private static readonly Dictionary<string, string> ToneInstructions = new()
        {
            ["default"] = "",
            ["professional"] = "Use a professional, precise, and polished tone.",
            ["friendly"] = "Use a friendly, warm, and approachable tone.",
            ["formal"] = "Use a formal and respectful tone.",
            ["casual"] = "Use a casual, conversational, and relaxed tone.",
        };

        public static string LangName(string code) =>
            LangNames.TryGetValue(code, out var n) ? n : code;

        public static (string system, string user) Translate(string targetCode, string text, string template, string toneKey)
        {
            var system = template.Replace("{target}", LangName(targetCode));

            if (ToneInstructions.TryGetValue(toneKey ?? "default", out var tone) && tone.Length > 0)
                system += " " + tone;

            return (system, text);
        }
    }
}
