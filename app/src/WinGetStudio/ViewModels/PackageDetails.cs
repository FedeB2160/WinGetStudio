namespace WinGetStudio.ViewModels;

// Una riga dei dettagli. Label "": una riga su tutte e due le colonne (testo senza etichetta).
public sealed record DetailsRow(string Label, string Value);

// Una lettura di winget (list --details, show): la sua prima riga e le righe sotto.
public sealed record DetailsPart(string Heading, IReadOnlyList<DetailsRow> Rows);

// Dettagli di winget come tabella (ADR 0021): letti per POSIZIONE, mai per nome dell'etichetta,
// che winget traduce. Etichetta e valore si dividono al primo ": "; le righe rientrate continuano
// il valore sopra (Tag, gruppi dell'installer).
public sealed record PackageDetails(string Name, IReadOnlyList<DetailsPart> Parts)
{
    // null se nessuna riga ha la forma "etichetta: valore": chi chiama mostra il testo com'e'.
    public static PackageDetails? Parse(string name, string text)
    {
        var parts = new List<DetailsPart>();
        // CleanText toglie le righe vuote: una riga vuota separa due letture.
        foreach (var block in text.Replace("\r\n", "\n").Split("\n\n", StringSplitOptions.RemoveEmptyEntries))
        {
            var lines = block.Split('\n');
            var rows = new List<(string Label, List<string> Value)>();
            // La prima riga e' sempre il titolo: un nome di pacchetto puo' contenere ": ".
            foreach (var line in lines.Skip(1).Where(l => l.Trim().Length > 0))
            {
                if (line.StartsWith(' '))
                {
                    var more = line.StartsWith("  ") ? line[2..] : line[1..];
                    if (rows.Count == 0) rows.Add(("", [more]));
                    else rows[^1].Value.Add(more);
                }
                else if (line.IndexOf(": ", StringComparison.Ordinal) is > 0 and var at) rows.Add((line[..at], [line[(at + 2)..]]));
                else if (line.EndsWith(':') && line.Length > 1) rows.Add((line[..^1], []));
                else rows.Add(("", [line]));
            }
            parts.Add(new DetailsPart(lines[0], [.. rows.Select(r => new DetailsRow(r.Label, string.Join("\n", r.Value)))]));
        }
        return parts.Any(p => p.Rows.Any(r => r.Label.Length > 0)) ? new PackageDetails(name, parts) : null;
    }
}
