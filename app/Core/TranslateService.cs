using System;
using System.Threading;
using System.Threading.Tasks;
using NextAITranslator.Storage;

namespace NextAITranslator.Core
{
    /// <summary>Picks the engine for the active provider, builds the prompt, and streams the result.</summary>
    public static class TranslateService
    {
        private static readonly IEngine OpenAI = new OpenAICompatibleEngine();
        private static readonly IEngine Gemini = new GeminiEngine();

        public static Task TranslateAsync(AppConfig cfg, string targetCode, string text,
            Action<string> onDelta, CancellationToken ct)
        {
            var (system, user) = Prompts.Translate(targetCode, text, cfg.PromptTemplate, cfg.Tone);
            var provider = cfg.CurrentProvider();
            IEngine engine = cfg.Provider == "gemini" ? Gemini : OpenAI;
            return engine.TranslateAsync(system, user, provider, onDelta, ct);
        }
    }
}
