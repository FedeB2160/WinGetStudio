using Microsoft.Win32;
using WinGetStudio.Core;

namespace WinGetStudio.Core.Tests;

// Preferenze in HKCU con gli stessi nomi della 1.x (ADR 0023): le scelte passano alla 2.0 da
// sole. Qui una chiave di prova propria, cancellata alla fine.
public sealed class PreferencesTests : IDisposable
{
    // Un livello solo: cancellandola non resta una chiave padre vuota.
    private readonly string _key = $@"Software\WinGetStudio.Tests.{Guid.NewGuid():N}";

    public void Dispose() => Registry.CurrentUser.DeleteSubKeyTree(_key, throwOnMissingSubKey: false);

    [Fact]
    public void MissingValuesReturnTheDefault()
    {
        var p = new Preferences(_key);
        Assert.Equal("System", p.GetString(Preferences.Theme, "System"));
        Assert.True(p.GetBool(Preferences.CheckAtStartup, true));
    }

    // I booleani come 0/1 (DWORD), come li scrive la 1.x: Set-ItemProperty su un [bool]
    // scriverebbe "True"/"False".
    [Fact]
    public void RoundTripsAndStoresBooleansAsDword()
    {
        var p = new Preferences(_key);
        p.Set(Preferences.InstallScope, "Machine");
        p.Set(Preferences.IncludeStore, true);

        Assert.Equal("Machine", p.GetString(Preferences.InstallScope, "Auto"));
        Assert.True(p.GetBool(Preferences.IncludeStore, false));
        using var k = Registry.CurrentUser.OpenSubKey(_key)!;
        Assert.Equal(RegistryValueKind.DWord, k.GetValueKind(Preferences.IncludeStore));
        Assert.Equal(1, k.GetValue(Preferences.IncludeStore));
    }

    // Valori scritti dalla 1.x: DWORD per i booleani, stringhe per il resto.
    [Fact]
    public void ReadsWhatOneXWrote()
    {
        using (var k = Registry.CurrentUser.CreateSubKey(_key))
        {
            k.SetValue(Preferences.IncludeUnknown, 0);
            k.SetValue(Preferences.CheckAtStartup, "1");
            k.SetValue(Preferences.TabHeaderStyle, "Text");
        }
        var p = new Preferences(_key);
        Assert.False(p.GetBool(Preferences.IncludeUnknown, true));
        Assert.True(p.GetBool(Preferences.CheckAtStartup, false));
        Assert.Equal("Text", p.GetString(Preferences.TabHeaderStyle, "Icon + Text"));
    }

    // Una preferenza illeggibile vale il default, non ferma l'avvio.
    [Fact]
    public void WrongTypeIsTheDefault()
    {
        using (var k = Registry.CurrentUser.CreateSubKey(_key))
            k.SetValue(Preferences.IncludeStore, "maybe");
        Assert.True(new Preferences(_key).GetBool(Preferences.IncludeStore, true));
    }

    [Fact]
    public void TheRealKeyIsTheOneOfOneX() => Assert.Equal(@"Software\WinGetStudio", Preferences.DefaultKey);
}
