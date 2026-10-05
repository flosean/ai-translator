using System;
using System.IO;
using System.Net.Http;
using System.Text;
using System.Threading;
using System.Threading.Tasks;

namespace NextAITranslator.Core;

/// <summary>Shared HttpClient + Server-Sent-Events reader for streaming LLM responses.</summary>
public static class Sse
{
    public static readonly HttpClient Client = new()
    {
        // Covers connect + response headers; body reads have a separate idle timeout.
        Timeout = TimeSpan.FromSeconds(100),
    };

    /// <summary>
    /// Invoke onData once per complete SSE event. Returning false ends the response immediately.
    /// </summary>
    public static Task StreamAsync(HttpRequestMessage req, Func<string, bool> onData, CancellationToken ct) =>
        StreamAsync(req, onData, ct, TimeSpan.FromSeconds(100));

    internal static async Task StreamAsync(HttpRequestMessage req, Func<string, bool> onData,
        CancellationToken ct, TimeSpan idleTimeout)
    {
        using var resp = await Client.SendAsync(req, HttpCompletionOption.ResponseHeadersRead, ct)
                                     .ConfigureAwait(false);
        using var readCts = CancellationTokenSource.CreateLinkedTokenSource(ct);
        try
        {
            readCts.CancelAfter(idleTimeout);
            if (!resp.IsSuccessStatusCode)
            {
                var err = await resp.Content.ReadAsStringAsync(readCts.Token).ConfigureAwait(false);
                throw new HttpRequestException($"HTTP {(int)resp.StatusCode} {resp.StatusCode}: {Truncate(err, 500)}");
            }

            await using var stream = await resp.Content.ReadAsStreamAsync(readCts.Token).ConfigureAwait(false);
            using var reader = new StreamReader(stream);
            var data = new StringBuilder();
            bool hasData = false;
            while (true)
            {
                readCts.CancelAfter(idleTimeout);
                var line = await reader.ReadLineAsync(readCts.Token).ConfigureAwait(false);
                readCts.CancelAfter(Timeout.InfiniteTimeSpan);
                // An event is dispatched only at its blank-line delimiter, per the SSE protocol.
                if (line == null)
                {
                    if (hasData)
                        throw new InvalidDataException("串流在事件尚未完整接收時中斷，請重試。");
                    return;
                }
                if (line.Length == 0)
                {
                    if (hasData && !onData(data.ToString())) return;
                    data.Clear();
                    hasData = false;
                }
                else if (line == "data" || line.StartsWith("data:", StringComparison.Ordinal))
                {
                    var payload = line.Length == 4 ? "" : line.Substring(5);
                    // SSE removes one optional space, preserving the rest of the payload.
                    if (payload.StartsWith(' ')) payload = payload.Substring(1);
                    if (hasData) data.Append('\n');
                    data.Append(payload);
                    hasData = true;
                }
                // Comments and non-data fields (event, id, retry) carry no JSON payload.
            }
        }
        catch (OperationCanceledException) when (!ct.IsCancellationRequested && readCts.IsCancellationRequested)
        {
            throw new TimeoutException("等待翻譯串流回應逾時，請檢查網路後重試。");
        }
    }

    private static string Truncate(string s, int max) =>
        string.IsNullOrEmpty(s) || s.Length <= max ? s : s.Substring(0, max) + "…";
}
