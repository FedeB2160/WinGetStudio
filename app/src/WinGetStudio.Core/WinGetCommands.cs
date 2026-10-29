using System.Text.RegularExpressions;

namespace WinGetStudio.Core;

// Ambito dell'installazione: Auto lascia scegliere a winget. I nomi sono i valori salvati
// nella preferenza InstallScope della 1.x.
public enum InstallScope { Auto, User, Machine }

// Righe di comando delle operazioni, come lista di argomenti (ADR 0025). Match esatto
// sull'Id ovunque; --disable-interactivity perche' senza console un prompt di winget
// aspetterebbe per sempre.
public static partial class WinGetCommands
{
    public static string[] Upgrade(PackageRow row) =>
        ["upgrade", "--id", Id(row), "--include-unknown", "-e", "--silent", "--disable-interactivity",
         "--accept-source-agreements", "--accept-package-agreements"];

    // --source della riga: senza, winget cerca l'Id in TUTTE le sorgenti, Store compreso, che
    // passa dalla rete. Vuota quando la ricerca non l'ha stampata.
    public static string[] Install(PackageRow row, InstallScope scope) =>
    [
        "install", "--id", Id(row), "-e",
        .. string.IsNullOrEmpty(row.Source) ? Array.Empty<string>() : ["--source", row.Source],
        "--silent", "--disable-interactivity", "--accept-source-agreements", "--accept-package-agreements",
        .. scope switch { InstallScope.User => ["--scope", "user"], InstallScope.Machine => ["--scope", "machine"], _ => Array.Empty<string>() },
    ];

    // Vale anche per i programmi non installati con winget: Id "ARP\Machine\X64\Nome" con spazi.
    public static string[] Uninstall(PackageRow row) =>
        ["uninstall", "--id", Id(row), "-e", "--silent", "--disable-interactivity", "--accept-source-agreements"];

    // --blocking (ADR 0007): un pin Pinning winget lo rispetta solo con upgrade --all, e su
    // upgrade --id, cioe' come aggiorna questa app, lo ignora.
    public static string[] PinAdd(PackageRow row) =>
        ["pin", "add", "--blocking", "--id", Id(row), "-e", "--accept-source-agreements"];

    public static string[] PinRemove(PackageRow row) =>
        ["pin", "remove", "--id", Id(row), "-e", "--accept-source-agreements"];

    // Niente --include-versions: fissare le versioni rende l'import fragile (una versione non
    // piu' pubblicata lo fa fallire). L'import prende l'ultima disponibile.
    public static string[] Export(string file) => ["export", "-o", file, "--accept-source-agreements"];

    // --ignore-unavailable: senza, un solo pacchetto non piu' pubblicato fa fallire tutto.
    public static string[] Import(string file) =>
        ["import", "-i", file, "--ignore-unavailable", "--accept-source-agreements", "--accept-package-agreements", "--disable-interactivity"];

    // Pacchetti installati che nessuna sorgente conosce: winget li elenca a parte e non li
    // scrive nel file. Non e' un errore, ma l'utente deve saperlo.
    public static int ExportSkippedCount(string output) =>
        output.Split('\n').Count(l => NotInAnySource().IsMatch(l));

    private static string Id(PackageRow row)
    {
        WinGetCli.ValidateId(row.Id);
        return row.Id;
    }

    [GeneratedRegex("available from any source|disponibile in alcuna origine")]
    private static partial Regex NotInAnySource();
}
