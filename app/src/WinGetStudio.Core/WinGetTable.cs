using System.Text.RegularExpressions;

namespace WinGetStudio.Core;

// Lettura dell'output tabellare di winget (ADR 0006).
public static partial class WinGetTable
{
    // winget stampa TABELLE A LARGHEZZA FISSA localizzate. I nomi contengono spazi, quindi si
    // parsa per posizione delle colonne, ricavata dagli offset della riga di header.
    //
    // Ritorna, per ogni riga di dati, i campi nell'ordine delle colonne: il significato lo sa
    // il chiamante, perche' cambia col comando (la 4a colonna e' Disponibile in upgrade,
    // Corrispondenza in search, Origine in list). Le prime tre (Nome, Id, Versione) sono le
    // stesse ovunque; il numero di colonne varia anche a parita' di comando.
    //
    // maxColumns serve quando un'INTESTAZIONE contiene spazi: "Tipo di pin" verrebbe letta come
    // tre colonne, i cui finti offset cadono nel testo delle righe, e ogni riga sarebbe scartata
    // come disallineata.
    public static IReadOnlyList<string[]> Parse(string raw, int maxColumns = 0)
    {
        var lines = Lines(raw);
        var results = new List<string[]>();
        List<int>? cols = null;   // offset di inizio colonna della tabella in corso

        for (var i = 0; i < lines.Length; i++)
        {
            var line = lines[i];
            if (string.IsNullOrWhiteSpace(line)) continue;

            // INDIPENDENTE DALLA LINGUA: gli header sono tradotti, il separatore e' sempre di
            // trattini. Header = riga prima del separatore. MULTI-TABELLA: dopo gli upgrade
            // normali winget ne stampa una seconda (targeting esplicito) con larghezze proprie,
            // quindi si ri-ancora a ogni separatore.
            if (IsSeparator(line))
            {
                cols = null;
                var header = i > 0 ? lines[i - 1] : "";
                var starts = new List<int>();
                for (var c = 0; c < header.Length; c++)
                    if (header[c] != ' ' && (c == 0 || header[c - 1] == ' ')) starts.Add(c);
                // Soglia a TRE: "winget list --source winget" stampa solo Nome|Id|Versione.
                if (starts.Count >= 3)
                    // Un offset in piu' del necessario: fa da fine dell'ultimo campo richiesto.
                    cols = maxColumns > 0 && starts.Count > maxColumns + 1 ? starts.GetRange(0, maxColumns + 1) : starts;
                continue;
            }

            if (cols is null) continue;
            // Riga di header (la prossima e' il separatore): non e' un dato.
            if (i + 1 < lines.Length && IsSeparator(lines[i + 1])) continue;

            // Riepiloghi e prosa localizzata ("4 aggiornamenti disponibili."): una riga dati
            // rispetta la griglia, cioe' ogni inizio colonna e' preceduto da uno spazio. Non si
            // contano i token separati da 2+ spazi: nella seconda tabella le colonne distano uno.
            var aligned = true;
            for (var k = 1; k < cols.Count; k++)
            {
                var o = cols[k];
                if (o > 0 && o <= line.Length && line[o - 1] != ' ') { aligned = false; break; }
            }
            if (!aligned) continue;

            var fields = new string[cols.Count];
            for (var k = 0; k < cols.Count; k++)
                fields[k] = Field(line, cols[k], k + 1 < cols.Count ? cols[k + 1] : -1);

            // Id vuoto: non e' una riga di dati.
            if (string.IsNullOrWhiteSpace(fields[1])) continue;
            results.Add(fields);
        }
        return results;
    }

    // Ultime righe significative, per log e messaggi: quando un installer fallisce winget stampa
    // il percorso del suo log DOPO il messaggio, quindi l'ultima riga da sola non basta.
    public static IReadOnlyList<string> OutputTail(string text, int count = 2) =>
        Lines(text).Select(l => l.Trim()).Where(l => l.Length > 0).TakeLast(count).ToList();

    // Testo dei dettagli (ADR 0021): via le righe di solo spinner, l'indentazione resta perche'
    // show la usa per i gruppi.
    public static string CleanText(string text) =>
        string.Join("\r\n", Lines(text).Select(l => l.TrimEnd()).Where(l => l.Length > 0 && !Spinner().IsMatch(l)));

    // Righe con il solo ultimo segmento \r: i winget prima della 1.29 ridisegnano l'avanzamento.
    private static string[] Lines(string raw) =>
        raw.Split('\n').Select(l => l.TrimEnd('\r')).Select(l => l[(l.LastIndexOf('\r') + 1)..]).ToArray();

    private static bool IsSeparator(string line)
    {
        var t = line.Trim();
        return t.Length >= 3 && t.All(c => c == '-');
    }

    // Sottostringa [start, end) che tollera righe corte; end < 0 vuol dire fino a fine riga.
    private static string Field(string line, int start, int end)
    {
        if (start >= line.Length) return "";
        if (end < 0 || end > line.Length) end = line.Length;
        return end <= start ? "" : line[start..end].Trim();
    }

    [GeneratedRegex(@"^\s*[-\\|/]\s*$")]
    private static partial Regex Spinner();
}
