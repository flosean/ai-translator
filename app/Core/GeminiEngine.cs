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

            bool receivedText = false;
            await Sse.StreamAsync(req, payload =>
            {
                try
                {
                    using var doc = JsonDocument.Parse(payload);
                    Sse.ThrowIfApiError(doc.RootElement);
                    if (doc.RootElement.ValueKind != JsonValueKind.Object ||
                        !doc.RootElement.TryGetProperty("candidates", out var candidates) ||
                        candidates.ValueKind != JsonValueKind.Array || candidates.GetArrayLength() == 0)
                        return;

                    if (candidates[0].ValueKind != JsonValueKind.Object ||
                        !candidates[0].TryGetProperty("content", out var content) || content.ValueKind != JsonValueKind.Object ||
                        !content.TryGetProperty("parts", out var parts) || parts.ValueKind != JsonValueKind.Array)
                        return;

                    foreach (var part in parts.EnumerateArray())
                    {
                        if (part.ValueKind != JsonValueKind.Object ||
                            (part.TryGetProperty("thought", out var thought) && thought.ValueKind == JsonValueKind.True)) continue;
                        if (part.TryGetProperty("text", out var text) &&
                            text.ValueKind == JsonValueKind.String)
                        {
                            var s = text.GetString();
                            if (!string.IsNullOrEmpty(s))
                            {
                                receivedText = true;
                                onDelta(s);
                            }
                        }
                    }
                }
                catch (JsonException)
                {
                    // Ignore malformed fragments.
                }
            }, ct).ConfigureAwait(false);
            if (!receivedText) throw new HttpRequestException("Gemini 沒有回傳可顯示的翻譯結果。");
        }
    }
}
