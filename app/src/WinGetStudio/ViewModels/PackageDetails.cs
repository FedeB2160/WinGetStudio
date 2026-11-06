using WinGetStudio.Core;

namespace WinGetStudio.ViewModels;

// Una riga dei dettagli. Label "": una riga su tutte e due le colonne (testo senza etichetta).
// Nested: una riga di un gruppo (l'installer, la documentazione), rientrata sotto il suo titolo.
public sealed record DetailsRow(string Label, string Value, bool Nested = false);

// Una lettura di winget col nome che le da' l'app ("Catalog (winget)", "Installed").
public sealed record DetailsPart(string Title, IReadOnlyList<DetailsRow> Rows);

// Dettagli di winget come tabella (ADR 0021): letti per POSIZIONE, mai per nome dell'etichetta,
// che winget traduce. Etichetta e valore si dividono al primo ": "; le righe rientrate continuano
// il valore sopra, o ne fanno un gruppo se sono a loro volta coppie.
public sealed record PackageDetails(string Name, string Id, IReadOnlyList<DetailsPart> Parts)
{
    // null se nessuna riga ha la forma "etichetta: valore": chi chiama mostra il testo com'e'.
    public static PackageDetails? Parse(string name, string id, DetailsReads reads, string? source)
    {
        // Prima il catalogo (cos'e' il pacchetto), poi l'installato (dove e come).
        var parts = new[] { ($"Catalog ({source})", reads.Catalog), ("Installed", reads.Installed) }
            .Where(p => p.Item2.Length > 0)
            .Select(p => new DetailsPart(p.Item1, Rows(p.Item2)))
            .Where(p => p.Rows.Count > 0)
            .ToList();
        return parts.Any(p => p.Rows.Any(r => r.Label.Length > 0)) ? new PackageDetails(name, id, parts) : null;
    }

    private static List<DetailsRow> Rows(string text)
    {
        var lines = text.Replace("\r\n", "\n").Split('\n').Where(l => l.Trim().Length > 0).ToList();
        // La prima riga e' il titolo di winget ("Trovato 7-Zip [7zip.7zip]"): nome e Id stanno gia'
        // nel titolo del dialogo, e un nome di pacchetto puo' contenere ": ". Da sola e' un messaggio.
        if (lines.Count > 1) lines.RemoveAt(0);
        var rows = new List<(string Label, string Value, List<string> More)>();
        foreach (var line in lines)
        {
            if (line.StartsWith(' ') && rows.Count > 0) rows[^1].More.Add(line.StartsWith("  ") ? line[2..] : line[1..]);
            else if (line.StartsWith(' ')) rows.Add(("", line.Trim(), []));
            else if (line.IndexOf(": ", StringComparison.Ordinal) is > 0 and var at) rows.Add((line[..at], line[(at + 2)..], []));
            else if (line.EndsWith(':') && line.Length > 1) rows.Add((line[..^1], "", []));
            else rows.Add(("", line, []));
        }
        var result = new List<DetailsRow>();
        foreach (var (label, value, more) in rows)
        {
            if (more.Count == 0) result.Add(new(label, value));
            // Un gruppo di coppie (l'installer): il titolo, poi le sue righe.
            else if (value.Length == 0 && more.All(m => m.IndexOf(": ", StringComparison.Ordinal) > 0))
            {
                result.Add(new(label, ""));
                foreach (var m in more)
                {
                    var at = m.IndexOf(": ", StringComparison.Ordinal);
                    result.Add(new(m[..at], m[(at + 2)..], Nested: true));
                }
            }
            // Parole senza spazi una per riga (i tag): in fila, con le virgole.
            else if (value.Length == 0 && more.All(m => !m.Contains(' '))) result.Add(new(label, string.Join(", ", more)));
            else result.Add(new(label, string.Join("\n", value.Length > 0 ? [value, .. more] : more)));
        }
        return result;
    }
}
