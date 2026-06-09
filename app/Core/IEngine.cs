using System;
using System.Threading;
using System.Threading.Tasks;
using NextAITranslator.Storage;

namespace NextAITranslator.Core
{
    /// <summary>A streaming chat/translation engine for one provider family.</summary>
    public interface IEngine
    {
        /// <summary>
        /// Stream a completion for the given system + user prompt, calling
        /// <paramref name="onDelta"/> for each text fragment as it arrives.
        /// </summary>
        Task TranslateAsync(
            string systemPrompt,
            string userPrompt,
            ProviderConfig cfg,
            Action<string> onDelta,
            CancellationToken ct);
    }
}
