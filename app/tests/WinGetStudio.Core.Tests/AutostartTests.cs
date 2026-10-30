using Microsoft.Win32;
using WinGetStudio.Core;

namespace WinGetStudio.Core.Tests;

// Avvio con Windows: una voce nella chiave Run dell'utente, che e' anche la fonte di verita'.
public class AutostartTests
{
    [Fact]
    public void RunValueIsTheQuotedExeAndOnlyOurs()
    {
        var key = $@"Software\WinGetStudio.Tests\{Guid.NewGuid():N}";
        try
        {
            const string exe = @"C:\Program Files\WinGet Studio\WinGetStudio.exe";
            Assert.False(Autostart.IsOn(exe, key));

            Autostart.Set(true, exe, key);
            using (var k = Registry.CurrentUser.OpenSubKey(key))
                Assert.Equal($"\"{exe}\"", k?.GetValue(Autostart.ValueName));
            Assert.True(Autostart.IsOn(exe.ToUpperInvariant(), key));
            // La voce di un'altra copia non e' la nostra: accesa si sovrascrive.
            Assert.False(Autostart.IsOn(@"C:\Tools\WinGetStudio.exe", key));

            Autostart.Set(false, exe, key);
            Assert.False(Autostart.IsOn(exe, key));
            Autostart.Set(false, exe, key);
        }
        finally { Registry.CurrentUser.DeleteSubKeyTree(key, false); }
    }
}
