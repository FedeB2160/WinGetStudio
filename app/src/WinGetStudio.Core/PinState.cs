namespace WinGetStudio.Core;

// Pin dei pacchetti (ADR 0007). winget e' la fonte di verita': dopo un pin o unpin si
// rileggono, cosi' compare anche un pin aggiunto da riga di comando.
public sealed class PinState
{
    private HashSet<string> _ids = new(StringComparer.OrdinalIgnoreCase);

    // La lista nuova se la lettura e' riuscita, altrimenti resta l'ultima buona: mostrare le
    // righe "senza pin" sarebbe un'affermazione che winget non ha fatto.
    public void Apply(ReadResult<string> read)
    {
        if (read.Success) _ids = new HashSet<string>(read.Rows, StringComparer.OrdinalIgnoreCase);
    }

    public bool IsPinned(string id) => _ids.Contains(id);

    // Solo le righe che cambiano stato: ripinnare un pinnato fa uscire winget con un errore.
    public IReadOnlyList<PackageRow> Changing(IEnumerable<PackageRow> rows, bool pin) =>
        rows.Where(r => IsPinned(r.Id) != pin).ToList();

    // I pinnati restano fuori dalla coda di aggiornamento qualunque sia il tipo di pin, anche
    // uno Pinning messo da riga di comando. message: la riga per il log, null se nessuno.
    public IReadOnlyList<PackageRow> ExcludePinned(IEnumerable<PackageRow> rows, out string? message)
    {
        var all = rows.ToList();
        var kept = all.Where(r => !IsPinned(r.Id)).ToList();
        var n = all.Count - kept.Count;
        message = n == 0 ? null
            : $"Skipping {n} pinned package{(n == 1 ? "" : "s")}: remove the pin to update {(n == 1 ? "it" : "them")}.";
        return kept;
    }
}
