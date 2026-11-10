using WinGetStudio.Core;

namespace WinGetStudio.Core.Tests;

// Le righe di comando delle operazioni, le stesse della 1.x ma come lista di argomenti.
// --disable-interactivity ovunque: senza console un prompt di winget aspetterebbe per sempre.
public class WinGetCommandsTests
{
    private static readonly PackageRow SevenZip = new("7-Zip", "7zip.7zip", "26.03", "26.04", "winget");

    // --source della riga (o niente, per le righe ARP e senza sorgente) dopo -e, come Install:
    // senza, winget cerca l'Id in tutte le sorgenti e un msstore guasto fa fallire il comando.
    [Theory]
    [InlineData("winget", "upgrade --id 7zip.7zip --include-unknown -e --source winget --silent --disable-interactivity --accept-source-agreements --accept-package-agreements")]
    [InlineData("", "upgrade --id 7zip.7zip --include-unknown -e --silent --disable-interactivity --accept-source-agreements --accept-package-agreements")]
    public void Upgrade(string source, string expected) =>
        Assert.Equal(expected, string.Join(' ', WinGetCommands.Upgrade(SevenZip with { Source = source })));

    // --source della riga: senza, winget cerca l'Id in tutte le sorgenti, Store compreso (rete).
    [Theory]
    [InlineData(InstallScope.Auto, "winget", "install --id 7zip.7zip -e --source winget --silent --disable-interactivity --accept-source-agreements --accept-package-agreements")]
    [InlineData(InstallScope.User, "", "install --id 7zip.7zip -e --silent --disable-interactivity --accept-source-agreements --accept-package-agreements --scope user")]
    [InlineData(InstallScope.Machine, "msstore", "install --id 7zip.7zip -e --source msstore --silent --disable-interactivity --accept-source-agreements --accept-package-agreements --scope machine")]
    public void Install(InstallScope scope, string source, string expected) =>
        Assert.Equal(expected, string.Join(' ', WinGetCommands.Install(SevenZip with { Source = source }, scope)));

    [Fact]
    public void UninstallPassesTheSource() =>
        Assert.Equal(["uninstall", "--id", "7zip.7zip", "-e", "--source", "winget", "--silent", "--disable-interactivity", "--accept-source-agreements"],
            WinGetCommands.Uninstall(SevenZip));

    // Match esatto anche per gli Id ARP, che contengono spazi: arrivano come un solo argomento.
    // Le righe ARP non hanno sorgente: niente --source.
    [Fact]
    public void UninstallKeepsArpIdsWhole() =>
        Assert.Equal(["uninstall", "--id", @"ARP\Machine\X64\Android Studio", "-e", "--silent", "--disable-interactivity", "--accept-source-agreements"],
            WinGetCommands.Uninstall(SevenZip with { Id = @"ARP\Machine\X64\Android Studio", Source = "" }));

    // ADR 0007: un pin Pinning winget lo ignora su upgrade --id, cioe' come aggiorna l'app.
    [Fact]
    public void PinsAreBlocking()
    {
        Assert.Equal(["pin", "add", "--blocking", "--id", "7zip.7zip", "-e", "--source", "winget", "--accept-source-agreements"], WinGetCommands.PinAdd(SevenZip));
        Assert.Equal(["pin", "remove", "--id", "7zip.7zip", "-e", "--source", "winget", "--accept-source-agreements"], WinGetCommands.PinRemove(SevenZip));
    }

    // Righe ARP e senza sorgente: come prima, senza --source.
    [Fact]
    public void PinsWithoutSource()
    {
        var arp = SevenZip with { Id = @"ARP\Machine\X64\Android Studio", Source = "" };
        Assert.Equal(["pin", "add", "--blocking", "--id", arp.Id, "-e", "--accept-source-agreements"], WinGetCommands.PinAdd(arp));
        Assert.Equal(["pin", "remove", "--id", arp.Id, "-e", "--accept-source-agreements"], WinGetCommands.PinRemove(arp));
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
