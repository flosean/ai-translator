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

            bool receivedText = false;
            await Sse.StreamAsync(req, payload =>
            {
                if (payload == "[DONE]") return;

                try
                {
                    using var doc = JsonDocument.Parse(payload);
                    Sse.ThrowIfApiError(doc.RootElement);
                    if (doc.RootElement.ValueKind != JsonValueKind.Object ||
                        !doc.RootElement.TryGetProperty("choices", out var choices) ||
                        choices.ValueKind != JsonValueKind.Array || choices.GetArrayLength() == 0) return;

                    if (choices[0].ValueKind != JsonValueKind.Object ||
                        !choices[0].TryGetProperty("delta", out var delta) || delta.ValueKind != JsonValueKind.Object) return;
                    if (delta.TryGetProperty("content", out var content) &&
                        content.ValueKind == JsonValueKind.String)
                    {
                        var s = content.GetString();
                        if (!string.IsNullOrEmpty(s))
                        {
                            receivedText = true;
                            onDelta(s);
                        }
                    }
                }
                catch (JsonException)
                {
                    // Ignore keep-alive / malformed fragments.
                }
            }, ct).ConfigureAwait(false);
            if (!receivedText) throw new HttpRequestException("模型沒有回傳可顯示的翻譯結果。");
        }
    }
}
