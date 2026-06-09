using System;
using System.IO;
using System.Net.Http;
using System.Threading;
using System.Threading.Tasks;

namespace NextAITranslator.Core
{
    /// <summary>Shared HttpClient + minimal Server-Sent-Events reader for streaming LLM responses.</summary>
    public static class Sse
    {
        public static readonly HttpClient Client = new()
        {
            // Covers connect + response headers (ResponseHeadersRead); the streamed body is not bounded by this.
            Timeout = TimeSpan.FromSeconds(100),
        };

        /// <summary>
        /// Send the request and invoke <paramref name="onData"/> for every "data:" payload line.
        /// Throws <see cref="HttpRequestException"/> with the response body on a non-success status.
        /// </summary>
        public static async Task StreamAsync(HttpRequestMessage req, Action<string> onData, CancellationToken ct)
        {
            using var resp = await Client.SendAsync(req, HttpCompletionOption.ResponseHeadersRead, ct)
                                         .ConfigureAwait(false);

            if (!resp.IsSuccessStatusCode)
            {
                var err = await resp.Content.ReadAsStringAsync(ct).ConfigureAwait(false);
                throw new HttpRequestException($"HTTP {(int)resp.StatusCode} {resp.StatusCode}: {Truncate(err, 500)}");
            }

            await using var stream = await resp.Content.ReadAsStreamAsync(ct).ConfigureAwait(false);
            using var reader = new StreamReader(stream);

            string? line;
            while ((line = await reader.ReadLineAsync(ct).ConfigureAwait(false)) != null)
            {
                if (line.Length == 0) continue;
                if (line.StartsWith("data:", StringComparison.Ordinal))
                {
                    var payload = line.Substring(5).Trim();
                    if (payload.Length > 0)
                        onData(payload);
                }
            }
        }

        private static string Truncate(string s, int max) =>
            string.IsNullOrEmpty(s) || s.Length <= max ? s : s.Substring(0, max) + "…";
    }
}
