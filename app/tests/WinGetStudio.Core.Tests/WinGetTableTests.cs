using WinGetStudio.Core;

namespace WinGetStudio.Core.Tests;

// Parser per posizione di colonna (ADR 0006). Fixture dalle uscite reali di winget, come in
// tests\Test-InvokeWinGet.ps1 della 1.x.
public class WinGetTableTests
{
    // Dopo gli upgrade normali winget stampa una seconda tabella, con larghezze proprie, per i
    // pacchetti a targeting esplicito. Con una sola ancora il suo header diventava una riga
    // fantasma e i suoi pacchetti sparivano.
    internal const string TwoTables = """
        Nome                                  Id                                        Versione       Disponibile    Origine
        ---------------------------------------------------------------------------------------------------------------------
        Claude                                Anthropic.Claude                          1.24012.1.0    1.24012.9      winget
        Google Chrome                         Google.Chrome.EXE                         150.0.7871.187 151.0.7922.72  winget
        MEGAsync                              Mega.MEGASync                             < 6.5.0.2      6.5.0.2        winget
        Visual Studio Community 2026 Insiders Microsoft.VisualStudio.Community.Insiders 18.9.12020.428 18.9.12023.133 winget
        4 aggiornamenti disponibili.

        Per i pacchetti seguenti e' disponibile un aggiornamento, ma e' necessario un targeting esplicito per l'aggiornamento:
        Nome    Id              Versione Disponibile Origine
        ----------------------------------------------------
        Discord Discord.Discord 1.0.9249 1.0.9250    winget
        """;

    [Fact]
    public void TwoTablesAreReanchoredAtEachSeparator()
    {
        var rows = WinGetTable.Parse(TwoTables);

        Assert.Equal(5, rows.Count);
        Assert.DoesNotContain(rows, r => r[1] == "Id" || r[0] == "Nome");
        Assert.DoesNotContain(rows, r => r[0].Contains("aggiornament"));
        Assert.Equal(["Google Chrome", "Google.Chrome.EXE", "150.0.7871.187", "151.0.7922.72", "winget"], rows[1]);
        Assert.Equal("Visual Studio Community 2026 Insiders", rows[3][0]);
        Assert.Equal(["Discord", "Discord.Discord", "1.0.9249", "1.0.9250", "winget"], rows[4]);
    }

    // "winget list --source winget" e "search ab --count 5" hanno tre colonne: con la vecchia
    // soglia a quattro la tabella veniva scartata in silenzio.
    [Fact]
    public void ThreeColumnsAndTruncationProse()
    {
        var rows = WinGetTable.Parse("""
            Nome        Id                      Versione
            --------------------------------------------
            Robo 3T     3TSoftwareLabs.Robo3T   1.4.4
            Studio 3T   3TSoftwareLabs.Studio3T 2026.12.0
            <voci aggiuntive troncate a causa del limite dei risultati>
            """);

        Assert.Equal(2, rows.Count);
        Assert.Equal(["Studio 3T", "3TSoftwareLabs.Studio3T", "2026.12.0"], rows[1]);
    }

    // In list la quarta colonna e' Origine, e la versione puo' avere il prefisso "> ".
    [Fact]
    public void ListKeepsNamesAndVersionPrefix()
    {
        var rows = WinGetTable.Parse("""
            Nome              Id                   Versione       Origine
            -------------------------------------------------------------
            1Password         AgileBits.1Password  > 8.12.30.21   winget
            7-Zip 26.02 (x64) 7zip.7zip            26.02          winget
            """);

        Assert.Equal(2, rows.Count);
        Assert.Equal("7-Zip 26.02 (x64)", rows[1][0]);
        Assert.Equal("> 8.12.30.21", rows[0][2]);
        Assert.Equal("winget", rows[0][3]);
    }

    // "Tipo di pin" ha spazi: senza il limite le sue parole diventano colonne i cui offset
    // cadono nel testo delle righe, e ogni riga e' scartata come disallineata.
    internal const string Pins = """
        Nome              Id           Versione Origine Tipo di pin
        -----------------------------------------------------------
        7-Zip 26.02 (x64) 7zip.7zip    26.02    winget  Pinning
        VLC media player  VideoLAN.VLC 3.0.23   winget  Blocking
        """;

    [Fact]
    public void HeaderWithSpacesNeedsMaxColumns()
    {
        var rows = WinGetTable.Parse(Pins, maxColumns: 3);
        Assert.Equal(["7zip.7zip", "VideoLAN.VLC"], rows.Select(r => r[1]));
        Assert.True(WinGetTable.Parse(Pins).Count < 2);
    }

    [Fact]
    public void ProgressSegmentsKeepTheLastOne()
    {
        var rows = WinGetTable.Parse("  -\r  |\rName     Id       Version\n-------------------------\nOnly One Only.One 1.0\n");
        Assert.Equal(["Only One", "Only.One", "1.0"], Assert.Single(rows));
    }

    [Fact]
    public void ProseWithoutTableIsEmpty() => Assert.Empty(WinGetTable.Parse("Nessun PIN configurato."));

    [Fact]
    public void OutputTailKeepsLastMeaningfulLines()
    {
        Assert.Equal(["Errore X", @"Log: C:\x.log"],
            WinGetTable.OutputTail("  -\r  |\rSorgente aperta\r\n\r\nErrore X\r\nLog: C:\\x.log\r\n"));
        Assert.Equal(["Solo questa"], WinGetTable.OutputTail("  -\r  |\rSolo questa\r\n"));
    }

    // Dettagli (ADR 0021): resta l'ultimo segmento \r, si scartano le righe di solo spinner,
    // l'indentazione resta perche' show la usa per i gruppi.
    [Fact]
    public void CleanTextDropsSpinnersAndKeepsIndentation() =>
        Assert.Equal("Trovato 7-Zip [7zip.7zip]\r\nVersione: 26.04\r\nTag:\r\n  zip",
            WinGetTable.CleanText("  -\r  \\\rTrovato 7-Zip [7zip.7zip]\r\nVersione: 26.04\r\n  |\r\nTag:\r\n  zip\r\n"));
}
