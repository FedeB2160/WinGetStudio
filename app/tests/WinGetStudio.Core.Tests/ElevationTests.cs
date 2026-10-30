using System.ComponentModel;

namespace WinGetStudio.Core.Tests;

// Elevazione su richiesta (ADR 0024): un solo runas per tutte le righe, exit code di ogni passo,
// annullamento cooperativo; il riavvio elevato solo dove l'exe non carica librerie native da una
// cartella scrivibile dall'utente (ADR 0026). Il batch gira qui SENZA runas: stesso cmd, nessun UAC.
public class ElevationTests
{
    private static readonly string Cmd = Path.Combine(Environment.SystemDirectory, "cmd.exe");

    [Theory]
    [InlineData(unchecked((int)0x8A150030), true)]  // EXEC_UNINSTALL_COMMAND_FAILED: disinstallazione per-machine
    [InlineData(unchecked((int)0x8A150019), true)]  // COMMAND_REQUIRES_ADMIN
    [InlineData(1223, true)]                        // ERROR_CANCELLED: UAC rifiutato, si puo' ripetere
    [InlineData(unchecked((int)0x8A15007D), false)] // ADMIN_CONTEXT_ACTION_PROHIBITED: il contrario
    [InlineData(1, false)]
    [InlineData(0, false)]
    public void ElevationCanFix(int code, bool expected) => Assert.Equal(expected, ExitCodes.ElevationCanFix(code));

    // Il portable self-contained estrae le librerie native in %TEMP%\.net: elevato le caricherebbe
    // da una cartella che l'utente non elevato puo' riscrivere. La build di sviluppo resta (si prova).
    [Theory]
    [InlineData(InstallChannel.Installed, true)]
    [InlineData(InstallChannel.Source, true)]
    [InlineData(InstallChannel.Portable, false)]
    [InlineData(InstallChannel.WinGetPortable, false)]
    public void RestartElevatedOnlyWhereNoLibraryIsExtracted(InstallChannel channel, bool expected) =>
        Assert.Equal(expected, Elevation.CanRestartElevated(channel));

    // cmd espande %VAR% anche fra apici, e un apice nell'argomento chiuderebbe la quotatura: in un
    // processo elevato, comandi scelti da chi ha scritto la variabile o il nome del pacchetto.
    [Theory]
    [InlineData("A%PATH%B")]
    [InlineData("A\"B")]
    [InlineData("A\nB")]
    public void BatchRefusesWhatCmdWouldInterpret(string arg) =>
        Assert.Throws<ArgumentException>(() => Elevation.BatchLine(Cmd, [["uninstall", "--id", arg]], new BatchFiles(Path.GetTempPath(), 1)));

    [Fact]
    public void BatchLineQuotesEveryPathAndChecksTheCancelMarkerBeforeEachStep()
    {
        var files = new BatchFiles(@"C:\T", 2, "g");
        var line = Elevation.BatchLine(@"C:\W\winget.exe", [["uninstall", "--id", "A B"], ["upgrade", "--id", "C.C"]], files);

        Assert.Equal(
            "/d /v:off /s /c \"" +
            "(if not exist \"C:\\T\\wgt_g.cancel\" (\"C:\\W\\winget.exe\" uninstall --id \"A B\" >\"C:\\T\\wgt_g_0.out\" 2>\"C:\\T\\wgt_g_0.err\" & >\"C:\\T\\wgt_g_0.code\" call echo %^errorlevel%))" +
            " & (if not exist \"C:\\T\\wgt_g.cancel\" (\"C:\\W\\winget.exe\" upgrade --id C.C >\"C:\\T\\wgt_g_1.out\" 2>\"C:\\T\\wgt_g_1.err\" & >\"C:\\T\\wgt_g_1.code\" call echo %^errorlevel%))" +
            "\"", line);
    }

    // Exit code che finiscono con una cifra (3, -1978335184): con "echo 3>file" cmd leggerebbe
    // "3>" come redirezione dell'handle 3. Il redirect sta davanti.
    [Fact]
    public async Task BatchRunsEveryStepAndReadsEachExitCode()
    {
        var steps = new List<string>();
        var run = await Elevation.RunBatchAsync(Cmd, [["/d", "/c", "echo", "hello"], ["/d", "/c", "exit", "3"], ["/d", "/c", "exit", "-1978335184"]],
            (i, r) => { lock (steps) steps.Add(r is null ? $"start {i}" : $"done {i}"); }, default, verb: "");

        Assert.True(run.Approved);
        Assert.Equal([0, 3, -1978335184], run.Results.Select(r => r!.ExitCode));
        Assert.Equal("hello", run.Results[0]!.Output.Trim());
        Assert.Equal("start 0", steps[0]);
        Assert.Equal("done 2", steps[^1]);
        Assert.Equal(6, steps.Count);
    }

    // Annullare ferma i passi non ancora partiti; quello in corso finisce (ADR 0003).
    [Fact]
    public async Task CancelStopsTheStepsNotYetStarted()
    {
        using var cancel = new CancellationTokenSource();
        var run = await Elevation.RunBatchAsync(Cmd, [["/d", "/c", "ping", "-n", "3", "127.0.0.1"], ["/d", "/c", "exit", "5"]],
            (i, r) => { if (i == 0 && r is null) cancel.Cancel(); }, cancel.Token, verb: "");

        Assert.True(run.Approved);
        Assert.Equal(0, run.Results[0]!.ExitCode);
        Assert.Null(run.Results[1]);
    }

    // Cancel durante l'attesa dell'UAC: nulla parte, e se l'UAC viene approvato dopo il batch
    // trova il segnale e non fa nulla.
    [Fact]
    public async Task CancelledBeforeApprovalRunsNothing()
    {
        using var cancel = new CancellationTokenSource();
        cancel.Cancel();
        var run = await Elevation.RunBatchAsync(Cmd, [["/d", "/c", "exit", "5"]], null, cancel.Token, verb: "");

        Assert.False(run.Approved);
        Assert.Equal([null], run.Results);
    }

    [Fact]
    public void DeclinedIsTheCancelledError() =>
        Assert.True(Elevation.IsDeclined(new Win32Exception(1223)));

    // Il retry non elevato della 1.x (ADR 0018) attraverso una vera attivita' pianificata: apre una
    // console e su un runner di CI non c'e' una sessione interattiva. Solo con WINGETSTUDIO_LIVE=1.
    [Fact]
    public async Task UnelevatedTaskReturnsTheExitCode()
    {
        Assert.SkipUnless(Environment.GetEnvironmentVariable("WINGETSTUDIO_LIVE") == "1", "set WINGETSTUDIO_LIVE=1 to run a real scheduled task");
        var r = await new Elevation().RunUnelevatedAsync(Cmd, ["/d", "/c", "exit", "-1978335107"], null);

        Assert.Equal(-1978335107, r.ExitCode);
    }

    // Il riavvio non elevato: l'attivita' avvia l'exe direttamente (nessuna console) e si cancella
    // appena e' partito, senza chiuderlo.
    [Fact]
    public async Task UnelevatedStartReturnsOnceStarted()
    {
        Assert.SkipUnless(Environment.GetEnvironmentVariable("WINGETSTUDIO_LIVE") == "1", "set WINGETSTUDIO_LIVE=1 to run a real scheduled task");
        await new Elevation().StartUnelevatedAsync(Path.Combine(Environment.SystemDirectory, "whoami.exe"));
    }
}
