namespace WinGetStudio.Core;

// Riga di un elenco di pacchetti. Available solo negli aggiornamenti; Source vuota per le righe
// ARP (programmi non installati con winget).
public sealed record PackageRow(string Name, string Id, string Version, string Available = "", string Source = "");

// Una lettura torna l'esito insieme ai dati (ADR 0005): un errore di winget non e' una lista
// vuota. Rows e' vuota quando Success e' falso.
public sealed record ReadResult<T>(bool Success, IReadOnlyList<T> Rows, int ExitCode, string Output);

// Il motore winget visto dall'app (ADR 0025): la CLI ora, la COM API dalla fase 4.
public interface IWinGetBackend
{
    Task<ReadResult<PackageRow>> SearchAsync(string query, bool includeStore, int count = 25);
    Task<ReadResult<PackageRow>> GetInstalledAsync();
    Task<ReadResult<PackageRow>> GetUpgradesAsync(bool includeUnknown);
    Task<ReadResult<string>> GetPinsAsync();
    Task<string> GetDetailsAsync(string id, string? source, bool installed);
}
