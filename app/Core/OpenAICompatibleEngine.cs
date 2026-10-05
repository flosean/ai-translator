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
            bool completed = false;
            await Sse.StreamAsync(req, payload =>
            {
                if (payload.Trim() == "[DONE]")
                {
                    completed = true;
                    return false;
                }

                try
                {
                    using var doc = JsonDocument.Parse(payload);
                    var root = doc.RootElement;
                    if (root.ValueKind != JsonValueKind.Object)
                        throw new InvalidDataException("翻譯服務傳回非預期的串流格式。");
                    if (root.TryGetProperty("error", out var error))
                    {
                        var message = error.ValueKind == JsonValueKind.Object && error.TryGetProperty("message", out var detail)
                            ? detail.ToString() : error.ToString();
                        throw new HttpRequestException("翻譯服務錯誤：" + message);
                    }
                    if (!root.TryGetProperty("choices", out var choices) || choices.ValueKind != JsonValueKind.Array)
                        throw new InvalidDataException("翻譯服務傳回的串流缺少 choices。");
                    if (choices.GetArrayLength() == 0) return true; // Usage-only chunk.

                    var choice = choices[0];
                    if (choice.ValueKind != JsonValueKind.Object)
                        throw new InvalidDataException("翻譯服務傳回非預期的 choices 格式。");
                    if (choice.TryGetProperty("finish_reason", out var finish) && finish.ValueKind == JsonValueKind.String)
                    {
                        completed = finish.GetString() == "stop";
                        if (finish.GetString() == "length")
                            throw new InvalidDataException("翻譯達到模型輸出長度上限，請縮短原文後重試。");
                        if (finish.GetString() == "content_filter")
                            throw new InvalidDataException("翻譯遭服務供應商的內容篩選阻擋。");
                    }

                    bool hasDelta = choice.TryGetProperty("delta", out var delta);
                    if (completed && (!hasDelta || delta.ValueKind == JsonValueKind.Null)) return false;
                    if (!hasDelta || delta.ValueKind != JsonValueKind.Object)
                        throw new InvalidDataException("翻譯服務傳回的串流缺少 delta。");
                    if (delta.TryGetProperty("refusal", out var refusal) && refusal.ValueKind == JsonValueKind.String &&
                        !string.IsNullOrEmpty(refusal.GetString()))
                        throw new InvalidDataException("翻譯服務拒絕此請求：" + refusal.GetString());
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
                    return !completed;
                }
                catch (JsonException ex)
                {
                    throw new InvalidDataException("翻譯服務傳回無法解析的串流資料，請重試。", ex);
                }
            }, ct).ConfigureAwait(false);
            if (!receivedText)
                throw new InvalidDataException("翻譯服務未傳回文字，請檢查模型設定後重試。");
            if (!completed)
                throw new InvalidDataException("翻譯串流在完成前中斷，請重試。");
        }
    }
}
