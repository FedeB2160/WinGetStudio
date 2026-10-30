using WinGetStudio.Core;

namespace WinGetStudio.ViewModels;

// Cio' che Settings chiede al mondo fuori dalla finestra: GitHub, la copia in esecuzione, winget
// stesso. Dietro un'interfaccia perche' i test non vadano in rete ne' sostituiscano un exe.
public interface IUpdateHost
{
    InstallChannel Channel { get; }

    // L'exe pubblicato in esecuzione, o null in una build di sviluppo; e l'avvio con Windows.
    string? ExePath { get; }
    bool StartsWithWindows { get; set; }
    string AppVersion { get; }
    Task<Release?> GetLatestReleaseAsync(string repo, string assetName);

    // Scarica e verifica (hash e firmatario): il file torna aperto in sola lettura.
    Task<DownloadResult> DownloadAsync(Release release);

    // installed: avvia il setup; altrimenti sostituisce l'exe e avvia il nuovo. null se riuscito.
    string? Apply(VerifiedFile file, bool installed);

    Task<string?> GetWinGetVersionAsync();
    bool StoreUpdatesWinGet();
    string? FindWinGet();

    // register: prima la registrazione dell'App Installer di Windows. null se riuscito.
    Task<string?> InstallWinGetAsync(bool register, Action<string> log);

    // Rilancia l'app con runas (ADR 0024). false se l'UAC e' stato rifiutato.
    bool RestartElevated();

    // Da elevata: rilancia l'app senza diritti, con un'attivita' pianificata (ADR 0018).
    Task RestartUnelevatedAsync();
}
