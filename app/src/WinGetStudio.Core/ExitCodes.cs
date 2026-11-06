namespace WinGetStudio.Core;

public enum OperationStatus { Ok, Warning, Error }

// Esito dagli exit code di winget: una sola tabella per CLI e, dalla fase 4, COM (ADR 0025).
public static class ExitCodes
{
    // APPINSTALLER_CLI_ERROR_NO_APPLICATIONS_FOUND: per la ricerca e' "nessuna corrispondenza".
    public const int NoApplicationsFound = unchecked((int)0x8A150014);

    // Nomi verificati con "winget error <codice>" (1.29.380). Fino alla 1.12.0 la lista era
    // sfasata di uno: 0x8A150108 (CONTACT_SUPPORT), 0x8A15010A (REBOOT_REQUIRED_FOR_INSTALL,
    // installazione NON riuscita) e 0x8A15010C (CANCELLED_BY_USER) sono errori veri.
    private static readonly HashSet<uint> Benign =
    [
        0x8A150109, // INSTALL_REBOOT_REQUIRED_TO_FINISH
        0x8A15010B, // INSTALL_REBOOT_INITIATED
        0x8A15010D, // INSTALL_ALREADY_INSTALLED
        3010,       // ERROR_SUCCESS_REBOOT_REQUIRED
        1641,       // ERROR_SUCCESS_REBOOT_INITIATED
    ];

    // Da amministratore winget rifiuta i pacchetti per utente: si ripete senza elevazione (ADR 0018).
    public const int AdminContextProhibited = unchecked((int)0x8A15007D);

    // Fallimenti che l'elevazione puo' risolvere: Retry as administrator (ADR 0024). ERROR_CANCELLED
    // e' l'UAC rifiutato: la riga resta ripetibile.
    private static readonly HashSet<uint> NeedAdmin =
    [
        0x8A150030, // EXEC_UNINSTALL_COMMAND_FAILED: la disinstallazione per-machine silenziosa senza UAC
        0x8A150019, // COMMAND_REQUIRES_ADMIN
        1223,       // ERROR_CANCELLED
    ];

    public static bool ElevationCanFix(int? code) => code is int c && NeedAdmin.Contains(unchecked((uint)c));

    // Il motivo dei codici che si sanno spiegare, e cosa fare dove e' chiaro: tooltip dell'esito,
    // log, dialoghi di export e import. Testi da "winget error <codice>" su 1.29.380.
    private static readonly Dictionary<uint, string> Hints = new()
    {
        [0x8A150019] = "Needs administrator rights",                                        // COMMAND_REQUIRES_ADMIN
        [0x8A150030] = "The uninstaller failed, often for lack of administrator rights",    // EXEC_UNINSTALL_COMMAND_FAILED
        [1223] = "Canceled at the administrator prompt",                                   // ERROR_CANCELLED
        [0x8A15007D] = "winget refuses this as administrator for a per-user package",       // operazione vietata da amministratore
        [0x8A150101] = "The application is running: close it and try again",               // INSTALL_PACKAGE_IN_USE
        [0x8A150102] = "Another installation is in progress: try again later",             // INSTALL_INSTALL_IN_PROGRESS
        [0x8A150103] = "Files are in use: close the application and try again",             // INSTALL_FILE_IN_USE
        [0x8A150105] = "The disk is full: free some space and try again",                   // INSTALL_DISK_FULL
        [0x8A150107] = "No internet connection: connect and try again",                     // INSTALL_NO_NETWORK
        [0x8A15010A] = "Restart Windows and try again",                                     // INSTALL_REBOOT_REQUIRED_FOR_INSTALL
        [0x8A150109] = "Restart Windows to finish",                                         // INSTALL_REBOOT_REQUIRED_TO_FINISH
        [3010] = "Restart Windows to finish",                                               // ERROR_SUCCESS_REBOOT_REQUIRED
        [0x8A15010D] = "Already installed",                                                 // INSTALL_ALREADY_INSTALLED
        [0x8A150011] = "The download does not match its manifest: try again later",         // INSTALLER_HASH_MISMATCH
        [0x8A15002B] = "No applicable update found",                                        // UPDATE_NOT_APPLICABLE
        [0x8A150034] = "Some packages could not be installed",                              // pacchetti importati non installati
        [0x8A150035] = "Some packages were not found in any source",                        // pacchetti richiesti non trovati
        [0x8A150045] = "A source could not be opened: check the internet connection",       // origine non apribile
        [0x8A15004B] = "Some sources could not be opened: check the internet connection",   // una o piu' origini non apribili
    };

    public static string? Hint(int code) => Hints.GetValueOrDefault(unchecked((uint)code));

    public static OperationStatus Classify(int code) =>
        code == 0 ? OperationStatus.Ok
        : Benign.Contains(unchecked((uint)code)) ? OperationStatus.Warning
        : OperationStatus.Error;
}
