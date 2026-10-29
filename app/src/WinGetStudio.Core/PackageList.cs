using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace WinGetStudio.Core;

public sealed record ImportPackage(string Id, string Version, string Source);

// File di export di winget, per l'anteprima dell'import (App.Backup.ps1 della 1.x). Si legge
// solo la forma Sources[] -> Packages[] -> PackageIdentifier: lo schema completo lo valida
// winget all'import.
public sealed class PackageList
{
    // Le proprieta' di un pacchetto che l'import tiene per default: il resto sono argomenti per
    // l'installer (winget 1.29 ci salva --custom/--override e all'import li riapplica).
    private static readonly string[] KnownProperties = ["PackageIdentifier", "Version", "Channel", "Scope"];

    public JsonObject Root { get; }

    // Un pacchetto per riga, nell'ordine del file: il sottoinsieme si sceglie per posizione,
    // perche' lo stesso Id puo' stare in due sorgenti.
    public IReadOnlyList<ImportPackage> Packages { get; }

    // Pacchetti con proprieta' oltre le quattro note: lo si dice senza doverne conoscere i nomi.
    public int StoredArguments { get; }

    private PackageList(JsonObject root, List<ImportPackage> packages, int stored) =>
        (Root, Packages, StoredArguments) = (root, packages, stored);

    // null se il file non c'e', non e' JSON o non ha la forma Sources[] -> Packages[].
    public static PackageList? Load(string path)
    {
        JsonNode? node;
        try { node = JsonNode.Parse(File.ReadAllText(path, Encoding.UTF8)); }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException or JsonException) { return null; }

        if (node is not JsonObject root || root["Sources"] is not JsonArray sources) return null;
        var packages = new List<ImportPackage>();
        var stored = 0;
        foreach (var s in sources)
        {
            if (s?["Packages"] is not JsonArray list) return null;
            var source = Text(s["SourceDetails"]?["Name"]);
            foreach (var p in list.OfType<JsonObject>())
            {
                packages.Add(new ImportPackage(Text(p["PackageIdentifier"]), Text(p["Version"]), source));
                if (p.Any(kv => !KnownProperties.Contains(kv.Key))) stored++;
            }
        }
        return new PackageList(root, packages, stored);
    }

    // Il file ridotto ai pacchetti in posizione keep, come testo JSON. Per default di ogni
    // pacchetto restano solo le proprieta' note: il file puo' venire da chiunque, e gli argomenti
    // salvati arriverebbero all'installer. Una proprieta' assente resta assente (lo schema di
    // winget rifiuta un null). Radice e sorgenti si copiano, il file letto non cambia; una
    // sorgente rimasta vuota si toglie.
    public string Subset(IEnumerable<int> keep, bool keepStoredArguments)
    {
        var wanted = keep.ToHashSet();
        var root = (JsonObject)Root.DeepClone();
        var sources = new JsonArray();
        var i = 0;
        foreach (var s in root["Sources"]!.AsArray())
        {
            var kept = new JsonArray();
            foreach (var p in s!["Packages"]!.AsArray().OfType<JsonObject>())
            {
                if (wanted.Contains(i++))
                    kept.Add(keepStoredArguments
                        ? p.DeepClone()
                        : new JsonObject(p.Where(kv => KnownProperties.Contains(kv.Key)).Select(kv => KeyValuePair.Create(kv.Key, kv.Value?.DeepClone()))));
            }
            if (kept.Count == 0) continue;
            var copy = (JsonObject)s.DeepClone();
            copy["Packages"] = kept;
            sources.Add(copy);
        }
        root["Sources"] = sources;
        return root.ToJsonString(new JsonSerializerOptions { WriteIndented = true });
    }

    // Il file ridotto in directory (default %TEMP%) col prefisso che TempFiles spazza al prossimo
    // avvio; UTF-8 senza BOM, come lo scrive winget.
    public string WriteSubset(IEnumerable<int> keep, bool keepStoredArguments, string? directory = null)
    {
        var path = Path.Combine(directory ?? Path.GetTempPath(), $"{TempFiles.Prefix}import_{Guid.NewGuid():N}.json");
        File.WriteAllText(path, Subset(keep, keepStoredArguments), new UTF8Encoding(false));
        return path;
    }

    private static string Text(JsonNode? node) =>
        node is JsonValue v && v.TryGetValue<string>(out var s) ? s : node?.ToJsonString() ?? "";
}
