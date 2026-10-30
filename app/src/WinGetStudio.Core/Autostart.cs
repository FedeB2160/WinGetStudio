using Microsoft.Win32;

namespace WinGetStudio.Core;

// Avvio con Windows: la voce WinGetStudio in HKCU\...\Run. Nessuna preferenza a parte: la voce e'
// lo stato, quindi un utente che la toglie da Gestione attivita' la vede spenta anche qui.
public static class Autostart
{
    public const string RunKey = @"Software\Microsoft\Windows\CurrentVersion\Run";
    public const string ValueName = "WinGetStudio";

    // Accesa solo se la voce avvia QUESTO exe: quella di un'altra copia vale come spenta.
    public static bool IsOn(string exePath, string key = RunKey)
    {
        try
        {
            using var k = Registry.CurrentUser.OpenSubKey(key);
            return k?.GetValue(ValueName) is string v && string.Equals(v.Trim('"'), exePath, StringComparison.OrdinalIgnoreCase);
        }
        catch (Exception e) when (e is System.Security.SecurityException or IOException or UnauthorizedAccessException) { return false; }
    }

    // Tra virgolette: un percorso con spazi (Program Files) altrimenti si spezza.
    public static void Set(bool on, string exePath, string key = RunKey)
    {
        using var k = Registry.CurrentUser.CreateSubKey(key);
        if (on) k.SetValue(ValueName, $"\"{exePath}\"", RegistryValueKind.String);
        else k.DeleteValue(ValueName, false);
    }
}
