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

    public static OperationStatus Classify(int code) =>
        code == 0 ? OperationStatus.Ok
        : Benign.Contains(unchecked((uint)code)) ? OperationStatus.Warning
        : OperationStatus.Error;
}
