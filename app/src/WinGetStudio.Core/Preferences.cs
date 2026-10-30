using Microsoft.Win32;

namespace WinGetStudio.Core;

// Preferenze dell'utente in HKCU, stessa chiave e stessi nomi della 1.x (ADR 0023): le scelte
// passano alla 2.0 senza migrazione. Il registro NON e' un requisito: se non si legge vale il
// default, se non si scrive la scelta vale per questa sessione.
public sealed class Preferences(string key = Preferences.DefaultKey)
{
    public const string DefaultKey = @"Software\WinGetStudio";

    public const string Theme = "Theme";                   // System | Light | Dark
    public const string TabHeaderStyle = "TabHeaderStyle"; // default Icon + Text
    public const string CheckAtStartup = "CheckAtStartup";
    public const string IncludeUnknown = "IncludeUnknown";
    public const string IncludeStore = "IncludeStore";
    public const string InstallScope = "InstallScope";     // Auto | User | Machine
    public const string StartElevated = "StartElevated";   // 2.0: ogni avvio chiede l'UAC (ADR 0024)

    public string GetString(string name, string defaultValue) => Read(name) as string ?? defaultValue;

    // I booleani sono 0/1: DWORD, o la stringa "0"/"1".
    public bool GetBool(string name, bool defaultValue) => Read(name) switch
    {
        int i => i != 0,
        string s when int.TryParse(s, out var i) => i != 0,
        _ => defaultValue,
    };

    public void Set(string name, string value) => Write(name, value, RegistryValueKind.String);

    public void Set(string name, bool value) => Write(name, value ? 1 : 0, RegistryValueKind.DWord);

    private object? Read(string name)
    {
        try
        {
            using var k = Registry.CurrentUser.OpenSubKey(key);
            return k?.GetValue(name);
        }
        catch (Exception e) when (e is System.Security.SecurityException or IOException or UnauthorizedAccessException) { return null; }
    }

    private void Write(string name, object value, RegistryValueKind kind)
    {
        try
        {
            using var k = Registry.CurrentUser.CreateSubKey(key);
            k.SetValue(name, value, kind);
        }
        catch (Exception e) when (e is System.Security.SecurityException or IOException or UnauthorizedAccessException) { }
    }
}
