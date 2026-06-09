using System;
using System.Net.Http;
using System.Text;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using NextAITranslator.Storage;

namespace NextAITranslator.Core
{
    /// <summary>
    /// OpenAI Chat Completions protocol — also covers Groq, DeepSeek, Kimi, Cerebras,
    /// Azure-style and any other "OpenAI-compatible" endpoint via base URL + model.
    /// </summary>
    public sealed class OpenAICompatibleEngine : IEngine
    {
        public async Task TranslateAsync(string systemPrompt, string userPrompt, ProviderConfig cfg,
            Action<string> onDelta, CancellationToken ct)
        {
            var url = cfg.BaseUrl.TrimEnd('/') + "/chat/completions";

            var bodyObj = new
            {
                model = cfg.Model,
                stream = true,
                messages = new object[]
                {
                    new { role = "system", content = systemPrompt },
                    new { role = "user", content = userPrompt },
                },
            };
            var json = JsonSerializer.Serialize(bodyObj);

            using var req = new HttpRequestMessage(HttpMethod.Post, url)
            {
                Content = new StringContent(json, Encoding.UTF8, "application/json"),
            };
            req.Headers.TryAddWithoutValidation("Authorization", "Bearer " + cfg.ApiKey);

            await Sse.StreamAsync(req, payload =>
            {
                if (payload == "[DONE]") return;

                try
                {
                    using var doc = JsonDocument.Parse(payload);
                    var choices = doc.RootElement.GetProperty("choices");
                    if (choices.GetArrayLength() == 0) return;

                    var delta = choices[0].GetProperty("delta");
                    if (delta.TryGetProperty("content", out var content) &&
                        content.ValueKind == JsonValueKind.String)
                    {
                        var s = content.GetString();
                        if (!string.IsNullOrEmpty(s))
                            onDelta(s);
                    }
                }
                catch (JsonException)
                {
                    // Ignore keep-alive / malformed fragments.
                }
            }, ct).ConfigureAwait(false);
        }
    }
}
