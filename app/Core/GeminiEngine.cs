using System;
using System.Net.Http;
using System.Text;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using NextAITranslator.Storage;

namespace NextAITranslator.Core
{
    /// <summary>Google Gemini (generativelanguage v1beta) streaming via SSE.</summary>
    public sealed class GeminiEngine : IEngine
    {
        public async Task TranslateAsync(string systemPrompt, string userPrompt, ProviderConfig cfg,
            Action<string> onDelta, CancellationToken ct)
        {
            var url = $"{cfg.BaseUrl.TrimEnd('/')}/models/{cfg.Model}:streamGenerateContent?alt=sse&key={Uri.EscapeDataString(cfg.ApiKey)}";

            var bodyObj = new
            {
                systemInstruction = new { parts = new[] { new { text = systemPrompt } } },
                contents = new[]
                {
                    new { role = "user", parts = new[] { new { text = userPrompt } } },
                },
            };
            var json = JsonSerializer.Serialize(bodyObj);

            using var req = new HttpRequestMessage(HttpMethod.Post, url)
            {
                Content = new StringContent(json, Encoding.UTF8, "application/json"),
            };

            await Sse.StreamAsync(req, payload =>
            {
                try
                {
                    using var doc = JsonDocument.Parse(payload);
                    if (!doc.RootElement.TryGetProperty("candidates", out var candidates) ||
                        candidates.GetArrayLength() == 0)
                        return;

                    if (!candidates[0].TryGetProperty("content", out var content) ||
                        !content.TryGetProperty("parts", out var parts))
                        return;

                    foreach (var part in parts.EnumerateArray())
                    {
                        if (part.TryGetProperty("text", out var text) &&
                            text.ValueKind == JsonValueKind.String)
                        {
                            var s = text.GetString();
                            if (!string.IsNullOrEmpty(s))
                                onDelta(s);
                        }
                    }
                }
                catch (JsonException)
                {
                    // Ignore malformed fragments.
                }
            }, ct).ConfigureAwait(false);
        }
    }
}
