using WinGetStudio.Core;

namespace WinGetStudio.Core.Tests;

// I lettori della CLI con un winget finto: comandi lanciati, esito separato dalla lista vuota
// (ADR 0005), sorgente per riga, un solo processo alla volta (ADR 0003).
public class WinGetCliTests
{
    private const int NoApplicationsFound = unchecked((int)0x8A150014);

    private static ProcessResult Result(int exit, string output) => FakeRunner.Result(exit, output);

    private static (WinGetCli Cli, FakeRunner Runner) Create(string output = "", int exit = 0)
    {
        var runner = new FakeRunner { Respond = _ => Result(exit, output) };
        return (new WinGetCli("winget.exe", runner), runner);
    }

    [Fact]
    public async Task UpgradesReadBothTables()
    {
        var (cli, runner) = Create(WinGetTableTests.TwoTables);
        var r = await cli.GetUpgradesAsync(includeUnknown: true);

        Assert.True(r.Success);
        Assert.Equal(5, r.Rows.Count);
        Assert.Equal(new PackageRow("Discord", "Discord.Discord", "1.0.9249", "1.0.9250", "winget"), r.Rows[4]);
        Assert.Equal(["upgrade", "--accept-source-agreements", "--include-pinned", "--include-unknown", "--no-progress"], runner.Calls.Single());
    }

    // Con --include-pinned winget 1.29 stampa i pin bloccanti in una tabella a parte, dopo una riga
    // di prosa (output reale, 2026-11-10). Senza l'opzione la riga spariva da Updates (ADR 0007).
    [Fact]
    public async Task UpgradesIncludeBlockingPins()
    {
        var (cli, runner) = Create("""
            Nome               Id                 Versione       Disponibile    Origine
            ---------------------------------------------------------------------------
            Antigravity 2.29.0 Google.Antigravity 2.29.0         2.30.0         winget
            ChatGPT            OpenAI.ChatGPT     26.1103.4239.0 26.1103.7773.0 winget
            3 aggiornamenti disponibili.

            1 pacchetti hanno un PIN che deve essere rimosso prima dell'aggiornamento
            Nome               Id                                Versione Disponibile Origine
            ---------------------------------------------------------------------------------
            PDF-XChange Editor TrackerSoftware.PDF-XChangeEditor 11.1.1.0 11.1.2.0    winget
            """);
        var r = await cli.GetUpgradesAsync(includeUnknown: false);

        Assert.Equal(["Google.Antigravity", "OpenAI.ChatGPT", "TrackerSoftware.PDF-XChangeEditor"], r.Rows.Select(p => p.Id));
        Assert.Equal(new PackageRow("PDF-XChange Editor", "TrackerSoftware.PDF-XChangeEditor", "11.1.1.0", "11.1.2.0", "winget"), r.Rows[2]);
        Assert.Equal(["upgrade", "--accept-source-agreements", "--include-pinned", "--no-progress"], runner.Calls.Single());
    }

    // Prima della 1.29 --no-progress non c'e': i frame \r li toglie il parser.
    [Fact]
    public async Task NoProgressOnlyFromWinGet129()
    {
        var (cli, runner) = Create();
        runner.Version = "v1.28.240";
        await cli.GetUpgradesAsync(includeUnknown: false);
        Assert.Equal(["upgrade", "--accept-source-agreements", "--include-pinned"], runner.Calls.Single());
    }

    [Fact]
    public async Task InstalledTakesSourceFromTheLastColumnAndDropsTheUpgradeMark()
    {
        var (cli, _) = Create("""
            Nome           Id                             Versione     Disponibile Origine
            ------------------------------------------------------------------------------
            1Password      AgileBits.1Password            > 8.12.36.40             winget
            Android Studio ARP\Machine\X64\Android Studio 2026.1
            7-Zip          7zip.7zip                      26.03        26.04       winget
            """);
        var r = await cli.GetInstalledAsync();

        Assert.Equal(["winget", "", "winget"], r.Rows.Select(x => x.Source));
        Assert.Equal("8.12.36.40", r.Rows[0].Version);
        Assert.Equal(@"ARP\Machine\X64\Android Studio", r.Rows[1].Id);
    }

    [Fact]
    public async Task PinsAreIds()
    {
        var (cli, runner) = Create(WinGetTableTests.Pins);
        var r = await cli.GetPinsAsync();
        Assert.Equal(["7zip.7zip", "VideoLAN.VLC"], r.Rows);
        Assert.Equal(["pin", "list", "--accept-source-agreements", "--no-progress"], runner.Calls.Single());
    }

    [Fact]
    public async Task OneRowTableStaysOneRow()
    {
        var (cli, _) = Create("Name     Id       Version Source Pin type\n-----------------------------------------\nOnly One Only.One 1.0     winget Blocking\n");
        Assert.Equal(["Only.One"], (await cli.GetPinsAsync()).Rows);
    }

    public static TheoryData<string> Readers => ["search", "pins", "installed", "upgrades"];

    // Success del lettore scelto.
    private static async Task<bool> Read(WinGetCli cli, string reader) => reader switch
    {
        "search" => (await cli.SearchAsync("fixture", includeStore: false)).Success,
        "pins" => (await cli.GetPinsAsync()).Success,
        "installed" => (await cli.GetInstalledAsync()).Success,
        _ => (await cli.GetUpgradesAsync(includeUnknown: false)).Success,
    };

    // Prima un errore di winget diventava una lista vuota e la UI diceva "nessun aggiornamento".
    [Theory, MemberData(nameof(Readers))]
    public async Task FailureIsNotAnEmptyList(string reader)
    {
        var (cli, _) = Create("Failed to open source: test fixture", 1);
        Assert.False(await Read(cli, reader));
    }

    [Fact]
    public async Task FailureKeepsCodeAndOutputAndHasNoRows()
    {
        var (cli, _) = Create("Name  Id      Version Available\n-------------------------------\nFoo   Foo.Foo 1.0     2.0\nFailed", 1);
        var r = await cli.GetUpgradesAsync(includeUnknown: false);
        Assert.False(r.Success);
        Assert.Equal(1, r.ExitCode);
        Assert.Contains("Failed", r.Output);
        Assert.Empty(r.Rows);
    }

    // 0x8A150014 NO_APPLICATIONS_FOUND: vuoto valido per la ricerca, errore per gli altri.
    [Theory, MemberData(nameof(Readers))]
    public async Task NoApplicationsFoundIsEmptyOnlyForSearch(string reader)
    {
        var (cli, _) = Create("Nessun pacchetto trovato.", NoApplicationsFound);
        Assert.Equal(reader == "search", await Read(cli, reader));
    }

    [Theory, MemberData(nameof(Readers))]
    public async Task ExitZeroWithProseIsEmptySuccess(string reader)
    {
        var (cli, _) = Create("Nessun PIN configurato.");
        Assert.True(await Read(cli, reader));
    }

    [Fact]
    public async Task RunnerFailureIsAReadFailure()
    {
        var runner = new FakeRunner { Respond = _ => throw new System.ComponentModel.Win32Exception(2) };
        var r = await new WinGetCli("winget.exe", runner).GetInstalledAsync();
        Assert.False(r.Success);
        Assert.Equal(-1, r.ExitCode);
        Assert.NotEmpty(r.Output);
    }

    [Fact]
    public async Task EmptyQueryRunsNothing()
    {
        var (cli, runner) = Create();
        var r = await cli.SearchAsync("  ", includeStore: true);
        Assert.True(r.Success);
        Assert.Empty(runner.Calls);
    }

    private const string WinGetSearch = """
        Nome    Id             Versione Corrispondenza
        ----------------------------------------------
        7-Zip   7zip.7zip      26.04    Moniker: 7zip
        NanaZip M2Team.NanaZip 7.0.1843 Tag: 7zip
        """;

    private const string StoreSearch = """
        Nome                         Id           Versione
        --------------------------------------------------
        Spotify - Music and Podcasts 9NCBCSZSJRSB Unknown
        """;

    private static (WinGetCli, FakeRunner) CreateSearch(ProcessResult winget, ProcessResult store)
    {
        var runner = new FakeRunner { Respond = a => a.Contains("msstore") ? store : winget };
        return (new WinGetCli("winget.exe", runner), runner);
    }

    // Una sorgente per volta, quindi la sorgente di ogni riga e' quella interrogata. Lo Store
    // in una seconda ricerca: dalla 1.29 winget non porta piu' in cima i suoi risultati.
    [Fact]
    public async Task SearchWingetThenStore()
    {
        var (cli, runner) = CreateSearch(Result(0, WinGetSearch), Result(0, StoreSearch));

        var only = await cli.SearchAsync("7zip", includeStore: false);
        Assert.Equal(["winget", "winget"], only.Rows.Select(r => r.Source));
        Assert.Equal(["search", "7zip", "--count", "25", "--source", "winget", "--accept-source-agreements", "--no-progress"], runner.Calls.Single());

        var both = await cli.SearchAsync("7zip", includeStore: true);
        Assert.True(both.Success);
        Assert.Equal(["7zip.7zip@winget", "M2Team.NanaZip@winget", "9NCBCSZSJRSB@msstore"], both.Rows.Select(r => $"{r.Id}@{r.Source}"));
        Assert.Equal(["search", "7zip", "--count", "10", "--source", "msstore", "--accept-source-agreements", "--no-progress"], runner.Calls[^1]);
    }

    // Uno Store che non risponde non fa fallire la ricerca: il perche' finisce nell'output.
    [Fact]
    public async Task StoreDownKeepsWingetResultsAndSaysWhy()
    {
        var (cli, _) = CreateSearch(Result(0, WinGetSearch), Result(1, "Impossibile aprire la sorgente."));
        var r = await cli.SearchAsync("7zip", includeStore: true);
        Assert.True(r.Success);
        Assert.Equal(2, r.Rows.Count);
        Assert.Matches("msstore.*Impossibile aprire", r.Output);
    }

    [Fact]
    public async Task StoreWithoutMatchesIsSilent()
    {
        var (cli, _) = CreateSearch(Result(0, WinGetSearch), Result(NoApplicationsFound, "Nessun pacchetto trovato."));
        var r = await cli.SearchAsync("7zip", includeStore: true);
        Assert.Equal(2, r.Rows.Count);
        Assert.DoesNotContain("msstore", r.Output);
    }

    [Fact]
    public async Task OnlyTheStoreFinds()
    {
        var (cli, _) = CreateSearch(Result(NoApplicationsFound, "Nessun pacchetto trovato."), Result(0, StoreSearch));
        var r = await cli.SearchAsync("spotify", includeStore: true);
        Assert.True(r.Success);
        Assert.Equal("msstore", Assert.Single(r.Rows).Source);
    }

    // Dettagli come testo di winget (ADR 0021): list --details per l'installato, show dal
    // catalogo della sua sorgente; le righe ARP non hanno sorgente.
    [Theory]
    [InlineData("Pkg.Id", "winget", true, "list|show")]
    [InlineData(@"ARP\Machine\X64\Foo", "", true, "list")]
    [InlineData("9NCBCSZSJRSB", "msstore", false, "show")]
    public async Task DetailsRunTheRightCommands(string id, string source, bool installed, string expected)
    {
        var (cli, runner) = Create("x");
        await cli.GetDetailsAsync(id, source, installed);

        Assert.Equal(expected, string.Join("|", runner.Calls.Select(c => c[0])));
        if (installed)
            Assert.Equal(["list", "--id", id, "-e", "--details", "--accept-source-agreements", "--disable-interactivity", "--no-progress"], runner.Calls[0]);
        if (source != "")
            Assert.Equal(["show", "--id", id, "-e", "--source", source, "--accept-source-agreements", "--disable-interactivity", "--no-progress"], runner.Calls[^1]);
    }

    [Fact]
    public async Task DetailsAreCleanText()
    {
        var (cli, _) = Create("  -\r  \\\rTrovato 7-Zip [7zip.7zip]\r\nVersione: 26.04\r\nTag:\r\n  zip\r\n");
        Assert.Equal(new DetailsReads("", "Trovato 7-Zip [7zip.7zip]\r\nVersione: 26.04\r\nTag:\r\n  zip"), await cli.GetDetailsAsync("7zip.7zip", "winget", false));
    }

    // Le due letture restano separate: il dialogo dice quale e' l'installato e quale il catalogo.
    [Fact]
    public async Task DetailsKeepTheTwoReadsApart()
    {
        var (cli, runner) = Create();
        runner.Respond = a => FakeRunner.Result(0, a[0] == "list" ? "Pkg 1.0 [Pkg.Id]\r\nVersion: 1.0" : "Found Pkg [Pkg.Id]\r\nVersion: 2.0");
        var reads = await cli.GetDetailsAsync("Pkg.Id", "winget", true);
        Assert.Equal(new DetailsReads("Pkg 1.0 [Pkg.Id]\r\nVersion: 1.0", "Found Pkg [Pkg.Id]\r\nVersion: 2.0"), reads);
        Assert.Equal("Pkg 1.0 [Pkg.Id]\r\nVersion: 1.0\r\n\r\nFound Pkg [Pkg.Id]\r\nVersion: 2.0", reads.Text);
    }

    // Un winget senza list --details stampa errore e guida: se show risponde, resta solo show,
    // che il dialogo legge come tabella. Se nessuna lettura riesce, tutto il testo, com'e'.
    [Fact]
    public async Task AFailedReadIsDroppedWhenAnotherSucceeds()
    {
        var (cli, runner) = Create();
        runner.Respond = a => a[0] == "list"
            ? FakeRunner.Result(-1978335222, "Argument name was not recognized: --details\r\nUsage: winget list [<options>]")
            : FakeRunner.Result(0, "Found 7-Zip [7zip.7zip]\r\nVersion: 26.05");
        Assert.Equal(new DetailsReads("", "Found 7-Zip [7zip.7zip]\r\nVersion: 26.05"), await cli.GetDetailsAsync("7zip.7zip", "winget", true));

        runner.Respond = _ => FakeRunner.Result(-1978335222, "Argument name was not recognized: --details");
        Assert.Equal("Argument name was not recognized: --details\r\n\r\nArgument name was not recognized: --details",
            (await cli.GetDetailsAsync("7zip.7zip", "winget", true)).Text);
    }

    // Gli Id vengono dal catalogo e dal registro ARP, cioe' da terzi: uno che sembri un'opzione
    // o porti caratteri di controllo non arriva a winget.
    [Theory]
    [InlineData("")]
    [InlineData("--source")]
    [InlineData("-e")]
    [InlineData("Foo\nBar")]
    [InlineData("Foo\0")]
    public async Task InvalidIdsAreRefused(string id)
    {
        var (cli, runner) = Create();
        await Assert.ThrowsAsync<ArgumentException>(() => cli.GetDetailsAsync(id, "winget", true));
        Assert.Empty(runner.Calls);
    }

    // Due winget insieme: uno dei due esce con 1 (ADR 0003).
    [Fact]
    public async Task OneWinGetAtATimeAcrossInstances()
    {
        var runner = new FakeRunner { Delay = () => Task.Delay(50) };
        var a = new WinGetCli("winget.exe", runner);
        var b = new WinGetCli("winget.exe", runner);
        await Task.WhenAll(a.GetPinsAsync(), b.GetInstalledAsync(), a.GetUpgradesAsync(false), b.SearchAsync("x", true));
        Assert.Equal(1, runner.MaxRunning);
    }
}
