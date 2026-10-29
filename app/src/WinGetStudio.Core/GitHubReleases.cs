using System.Net.Http.Headers;
using System.Text.Json;

namespace WinGetStudio.Core;

// Ultima release di un repo GitHub, con l'asset scelto per NOME (ADR 0013). Url vuoto se la
// release non ha quell'asset: il controllo manuale sa dire perche' non propone nulla. Sha256
// dal "digest" che GitHub pubblica per asset, o null.
public sealed record Release(string Tag, string Version, string Name, string? Url, long Size, string? Sha256);

public static class GitHubReleases
{
    // Un client per tutta l'app. User-Agent obbligatorio: senza, l'API risponde 403.
    public static readonly HttpClient Http = CreateClient();

    private static HttpClient CreateClient()
    {
        var c = new HttpClient { Timeout = TimeSpan.FromMinutes(10) };
        c.DefaultRequestHeaders.UserAgent.Add(new ProductInfoHeaderValue("WinGetStudio", null));
        return c;
    }

    // null se non c'e' rete o non ci sono release: un aggiornamento non trovato non e' un guasto.
    // Una chiamata anonima (60 l'ora per IP).
    public static async Task<Release?> GetLatestAsync(string repo, string assetName, HttpClient? http = null)
    {
        try
        {
            using var request = new HttpRequestMessage(HttpMethod.Get, $"https://api.github.com/repos/{repo}/releases/latest");
            request.Headers.Accept.ParseAdd("application/vnd.github+json");
            using var cts = new CancellationTokenSource(TimeSpan.FromSeconds(15));
            using var response = await (http ?? Http).SendAsync(request, cts.Token);
            if (!response.IsSuccessStatusCode) return null;
            return Parse(await response.Content.ReadAsStringAsync(cts.Token), assetName);
        }
        catch (Exception e) when (e is HttpRequestException or TaskCanceledException or JsonException or InvalidOperationException) { return null; }
    }

    public static Release? Parse(string json, string assetName)
    {
        using var doc = JsonDocument.Parse(json);
        var root = doc.RootElement;
        if (root.ValueKind != JsonValueKind.Object || !root.TryGetProperty("tag_name", out var t) || t.GetString() is not { Length: > 0 } tag) return null;
        JsonElement? asset = null;
        if (root.TryGetProperty("assets", out var assets) && assets.ValueKind == JsonValueKind.Array)
            foreach (var a in assets.EnumerateArray())
                if (a.TryGetProperty("name", out var n) && n.GetString() == assetName) { asset = a; break; }
        string? Str(string name) => asset is { } a && a.TryGetProperty(name, out var v) && v.ValueKind == JsonValueKind.String ? v.GetString() : null;
        var digest = Str("digest");
        return new Release(tag, tag.TrimStart('v', 'V'), assetName, Str("browser_download_url"),
            asset is { } x && x.TryGetProperty("size", out var s) && s.TryGetInt64(out var size) ? size : 0,
            digest is not null && digest.StartsWith("sha256:", StringComparison.OrdinalIgnoreCase) ? digest[7..].ToUpperInvariant() : null);
    }

    // Per componenti numeriche, non per stringa: "1.10.0" > "1.9.0". Un tag non numerico
    // ("nightly") non propone nulla.
    public static bool IsNewer(string latest, string current) =>
        System.Version.TryParse(latest.TrimStart('v', 'V'), out var l) && System.Version.TryParse(current.TrimStart('v', 'V'), out var c) && l > c;

    // Scarica in dest, che non deve esistere.
    public static async Task DownloadAsync(string url, string dest, HttpClient? http = null)
    {
        using var response = await (http ?? Http).GetAsync(url, HttpCompletionOption.ResponseHeadersRead);
        response.EnsureSuccessStatusCode();
        await using var file = new FileStream(dest, FileMode.CreateNew, FileAccess.Write);
        await response.Content.CopyToAsync(file);
    }
}
