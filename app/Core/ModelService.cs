using System;
using System.Collections.Generic;
using System.Net.Http;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using NextAITranslator.Storage;

namespace NextAITranslator.Core
{
    /// <summary>Lists the models a provider exposes, so the user can pick instead of typing.</summary>
    public static class ModelService
    {
        public static Task<List<string>> ListAsync(string provider, ProviderConfig cfg, CancellationToken ct)
            => provider == "gemini" ? ListGeminiAsync(cfg, ct) : ListOpenAiAsync(cfg, ct);

        private static async Task<List<string>> ListOpenAiAsync(ProviderConfig cfg, CancellationToken ct)
        {
            var url = cfg.BaseUrl.TrimEnd('/') + "/models";
            using var req = new HttpRequestMessage(HttpMethod.Get, url);
            req.Headers.TryAddWithoutValidation("Authorization", "Bearer " + cfg.ApiKey);

            using var resp = await Sse.Client.SendAsync(req, ct).ConfigureAwait(false);
            var json = await resp.Content.ReadAsStringAsync(ct).ConfigureAwait(false);
            if (!resp.IsSuccessStatusCode)
                throw new HttpRequestException($"HTTP {(int)resp.StatusCode}: {Trunc(json)}");

            var result = new List<string>();
            using var doc = JsonDocument.Parse(json);
            if (doc.RootElement.TryGetProperty("data", out var data) && data.ValueKind == JsonValueKind.Array)
            {
                foreach (var m in data.EnumerateArray())
                    if (m.TryGetProperty("id", out var id) && id.ValueKind == JsonValueKind.String)
                        result.Add(id.GetString()!);
            }
            result.Sort(StringComparer.OrdinalIgnoreCase);
            return result;
        }

        private static async Task<List<string>> ListGeminiAsync(ProviderConfig cfg, CancellationToken ct)
        {
            var url = $"{cfg.BaseUrl.TrimEnd('/')}/models?key={Uri.EscapeDataString(cfg.ApiKey)}&pageSize=200";
            using var resp = await Sse.Client.GetAsync(url, ct).ConfigureAwait(false);
            var json = await resp.Content.ReadAsStringAsync(ct).ConfigureAwait(false);
            if (!resp.IsSuccessStatusCode)
                throw new HttpRequestException($"HTTP {(int)resp.StatusCode}: {Trunc(json)}");

            var result = new List<string>();
            using var doc = JsonDocument.Parse(json);
            if (doc.RootElement.TryGetProperty("models", out var models) && models.ValueKind == JsonValueKind.Array)
            {
                foreach (var m in models.EnumerateArray())
                {
                    // Keep only models that can actually generate content.
                    if (!Supports(m, "generateContent")) continue;
                    if (m.TryGetProperty("name", out var name) && name.ValueKind == JsonValueKind.String)
                    {
                        var n = name.GetString()!;
                        if (n.StartsWith("models/", StringComparison.Ordinal))
                            n = n.Substring("models/".Length);
                        result.Add(n);
                    }
                }
            }
            result.Sort(StringComparer.OrdinalIgnoreCase);
            return result;
        }

        private static bool Supports(JsonElement model, string method)
        {
            if (!model.TryGetProperty("supportedGenerationMethods", out var methods) ||
                methods.ValueKind != JsonValueKind.Array)
                return true; // unknown -> don't exclude
            foreach (var m in methods.EnumerateArray())
                if (m.ValueKind == JsonValueKind.String && m.GetString() == method)
                    return true;
            return false;
        }

        private static string Trunc(string s) =>
            string.IsNullOrEmpty(s) || s.Length <= 300 ? s : s.Substring(0, 300) + "…";
    }
}
