using System.Collections.Generic;

namespace NextAITranslator.Core
{
    /// <summary>Builds the translation prompt. Source language is auto-detected by the model.</summary>
    public static class Prompts
    {
        private static readonly Dictionary<string, string> LangNames = new()
        {
            ["zh-Hant"] = "Traditional Chinese",
            ["en"] = "English",
        };

        /// <summary>Tone key -> extra instruction appended to the prompt. Empty means "as natural".</summary>
        private static readonly Dictionary<string, string> ToneInstructions = new()
        {
            ["default"] = "",
            ["professional"] = "Regardless of the source's tone, use a professional, precise, and polished tone.",
            ["friendly"] = "Regardless of the source's tone, use a friendly, warm, and approachable tone.",
            ["formal"] = "Regardless of the source's tone, use a formal and respectful tone.",
            ["casual"] = "Regardless of the source's tone, use a casual, conversational, and relaxed tone.",
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
