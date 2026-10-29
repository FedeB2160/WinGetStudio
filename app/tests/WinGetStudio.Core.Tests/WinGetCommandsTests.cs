using WinGetStudio.Core;

namespace WinGetStudio.Core.Tests;

// Le righe di comando delle operazioni, le stesse della 1.x ma come lista di argomenti.
// --disable-interactivity ovunque: senza console un prompt di winget aspetterebbe per sempre.
public class WinGetCommandsTests
{
    private static readonly PackageRow SevenZip = new("7-Zip", "7zip.7zip", "26.03", "26.04", "winget");

    [Fact]
    public void Upgrade() =>
        Assert.Equal(["upgrade", "--id", "7zip.7zip", "--include-unknown", "-e", "--silent", "--disable-interactivity",
            "--accept-source-agreements", "--accept-package-agreements"], WinGetCommands.Upgrade(SevenZip));

    // --source della riga: senza, winget cerca l'Id in tutte le sorgenti, Store compreso (rete).
    [Theory]
    [InlineData(InstallScope.Auto, "winget", "install --id 7zip.7zip -e --source winget --silent --disable-interactivity --accept-source-agreements --accept-package-agreements")]
    [InlineData(InstallScope.User, "", "install --id 7zip.7zip -e --silent --disable-interactivity --accept-source-agreements --accept-package-agreements --scope user")]
    [InlineData(InstallScope.Machine, "msstore", "install --id 7zip.7zip -e --source msstore --silent --disable-interactivity --accept-source-agreements --accept-package-agreements --scope machine")]
    public void Install(InstallScope scope, string source, string expected) =>
        Assert.Equal(expected, string.Join(' ', WinGetCommands.Install(SevenZip with { Source = source }, scope)));

    // Match esatto anche per gli Id ARP, che contengono spazi: arrivano come un solo argomento.
    [Fact]
    public void UninstallKeepsArpIdsWhole() =>
        Assert.Equal(["uninstall", "--id", @"ARP\Machine\X64\Android Studio", "-e", "--silent", "--disable-interactivity", "--accept-source-agreements"],
            WinGetCommands.Uninstall(SevenZip with { Id = @"ARP\Machine\X64\Android Studio" }));

    // ADR 0007: un pin Pinning winget lo ignora su upgrade --id, cioe' come aggiorna l'app.
    [Fact]
    public void PinsAreBlocking()
    {
        Assert.Equal(["pin", "add", "--blocking", "--id", "7zip.7zip", "-e", "--accept-source-agreements"], WinGetCommands.PinAdd(SevenZip));
        Assert.Equal(["pin", "remove", "--id", "7zip.7zip", "-e", "--accept-source-agreements"], WinGetCommands.PinRemove(SevenZip));
    }

    // Niente --include-versions: una versione non piu' pubblicata farebbe fallire l'import.
    // --ignore-unavailable: senza, un solo pacchetto sparito fa fallire tutto.
    [Fact]
    public void ExportAndImport()
    {
        Assert.Equal(["export", "-o", @"C:\a b\list.json", "--accept-source-agreements"], WinGetCommands.Export(@"C:\a b\list.json"));
        Assert.Equal(["import", "-i", @"C:\a b\list.json", "--ignore-unavailable", "--accept-source-agreements",
            "--accept-package-agreements", "--disable-interactivity"], WinGetCommands.Import(@"C:\a b\list.json"));
    }

    [Fact]
    public void InvalidIdsAreRefused()
    {
        var bad = SevenZip with { Id = "--source" };
        Assert.Throws<ArgumentException>(() => WinGetCommands.Upgrade(bad));
        Assert.Throws<ArgumentException>(() => WinGetCommands.Install(bad, InstallScope.Auto));
        Assert.Throws<ArgumentException>(() => WinGetCommands.Uninstall(bad));
        Assert.Throws<ArgumentException>(() => WinGetCommands.PinAdd(bad));
        Assert.Throws<ArgumentException>(() => WinGetCommands.PinRemove(bad));
    }

    // winget elenca a parte i pacchetti che nessuna sorgente conosce: non finiscono nel file.
    [Fact]
    public void ExportSkippedCount() =>
        Assert.Equal(2, WinGetCommands.ExportSkippedCount(
            "Installed package is not available from any source: Foo\r\nok\nIl pacchetto installato non è disponibile in alcuna origine: Bar\n"));
}
