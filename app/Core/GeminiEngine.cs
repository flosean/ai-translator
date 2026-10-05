using System;
using System.IO;
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
            bool completed = false;
            await Sse.StreamAsync(req, payload =>
            {
                try
                {
                    using var doc = JsonDocument.Parse(payload);
                    var root = doc.RootElement;
                    if (root.ValueKind != JsonValueKind.Object)
                        throw new InvalidDataException("Gemini 傳回非預期的串流格式。");
                    if (root.TryGetProperty("error", out var error))
                    {
                        var message = error.ValueKind == JsonValueKind.Object && error.TryGetProperty("message", out var detail)
                            ? detail.ToString() : error.ToString();
                        throw new HttpRequestException("Gemini 服務錯誤：" + message);
                    }
                    if (root.TryGetProperty("promptFeedback", out var feedback) &&
                        feedback.ValueKind == JsonValueKind.Object &&
                        feedback.TryGetProperty("blockReason", out var blocked) &&
                        blocked.ValueKind == JsonValueKind.String &&
                        blocked.GetString() is { Length: > 0 } reason && reason != "BLOCK_REASON_UNSPECIFIED")
                        throw new InvalidDataException("Gemini 已阻擋此翻譯請求：" + reason);
                    if (!root.TryGetProperty("candidates", out var candidates)) return true;
                    if (candidates.ValueKind != JsonValueKind.Array)
                        throw new InvalidDataException("Gemini 傳回非預期的 candidates 格式。");
                    if (candidates.GetArrayLength() == 0) return true;

                    var candidate = candidates[0];
                    if (candidate.ValueKind != JsonValueKind.Object)
                        throw new InvalidDataException("Gemini 傳回非預期的 candidate 格式。");
                    if (candidate.TryGetProperty("finishReason", out var finish) && finish.ValueKind == JsonValueKind.String)
                    {
                        var finishReason = finish.GetString();
                        completed = finishReason == "STOP";
                        if (!completed && !string.IsNullOrEmpty(finishReason) && finishReason != "FINISH_REASON_UNSPECIFIED")
                            throw new InvalidDataException("Gemini 未能完成翻譯：" + finishReason);
                    }
                    if (!candidate.TryGetProperty("content", out var content)) return !completed;
                    if (content.ValueKind != JsonValueKind.Object || !content.TryGetProperty("parts", out var parts) ||
                        parts.ValueKind != JsonValueKind.Array)
                        throw new InvalidDataException("Gemini 傳回非預期的文字內容格式。");

                    foreach (var part in parts.EnumerateArray())
                    {
                        if (part.ValueKind != JsonValueKind.Object)
                            throw new InvalidDataException("Gemini 傳回非預期的文字片段格式。");
                        if (part.TryGetProperty("thought", out var thought) && thought.ValueKind == JsonValueKind.True)
                            continue;
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
                    return !completed;
                }
                catch (JsonException ex)
                {
                    throw new InvalidDataException("Gemini 傳回無法解析的串流資料，請重試。", ex);
                }
            }, ct).ConfigureAwait(false);
            if (!receivedText)
                throw new InvalidDataException("Gemini 未傳回翻譯文字，請檢查模型設定後重試。");
            if (!completed)
                throw new InvalidDataException("Gemini 翻譯串流在完成前中斷，請重試。");
        }
    }
}
