using WinGetStudio.Core;

namespace WinGetStudio.Core.Tests;

// La coda della 1.x (Start-WinGetQueue): un pacchetto per volta, esito per riga, un errore
// non ferma la coda, l'annullamento si controlla PRIMA di partire con un pacchetto, mai a meta'.
public class PackageQueueTests
{
    private static readonly PackageRow A = new("App A", "A.A", "1.0", "2.0", "winget");
    private static readonly PackageRow B = new("App B", "B.B", "1.0", "2.0", "winget");
    private static readonly PackageRow C = new("App C", "C.C", "1.0", "2.0", "winget");

    private static (PackageQueue Queue, FakeRunner Runner) Create(Func<IReadOnlyList<string>, ProcessResult> respond)
    {
        var runner = new FakeRunner { Respond = respond };
        return (new PackageQueue(new WinGetCli("winget.exe", runner)), runner);
    }

    private static int ExitFor(IReadOnlyList<string> a) => a[2] switch { "A.A" => 0, "B.B" => 3010, _ => 1 };

    [Fact]
    public async Task RunsInOrderAndRecordsAnOutcomePerRow()
    {
        var (queue, runner) = Create(a => FakeRunner.Result(ExitFor(a), "line 1\r\nInstaller failed\r\nLog: C:\\x.log\r\n"));
        var log = new List<string>();

        var r = await queue.RunAsync(new QueueRequest(QueueVerb.Update, [A, B, C], WinGetCommands.Upgrade), log.Add);

        Assert.Equal(["A.A", "B.B", "C.C"], runner.Calls.Select(c => c[2]));
        Assert.Equal(new PackageOutcome(OperationStatus.Ok, "exit 0", 0), r.Outcomes["A.A"]);
        Assert.Equal(OperationStatus.Warning, r.Outcomes["B.B"].Status);
        Assert.Equal(new PackageOutcome(OperationStatus.Error, "exit 1", 1), r.Outcomes["C.C"]);
        Assert.False(r.Cancelled);
        Assert.Equal(["C.C"], r.FailedIds);
        Assert.Equal("1 ok, 1 with warnings, 1 failed", r.Summary);
        Assert.Equal("Starting update of 3 packages...", log[0]);
        Assert.Contains("-> App A [A.A]", log);
        Assert.Contains("   WARNING (exit 3010): App B", log);
        // Le ultime DUE righe: il percorso del log arriva DOPO il messaggio d'errore.
        var error = log.IndexOf("   ERROR (exit 1): App C");
        Assert.Equal(["      Installer failed", @"      Log: C:\x.log"], log.Skip(error + 1).Take(2));
        Assert.Equal("Update complete: 1 ok, 1 with warnings, 1 failed.", log[^1]);
    }

    [Fact]
    public async Task ExceptionsFailTheRowNotTheQueue()
    {
        var (queue, runner) = Create(a => a[2] == "A.A" ? throw new System.ComponentModel.Win32Exception(2, "not found") : FakeRunner.Result(0, ""));
        var log = new List<string>();
        var bad = B with { Id = "--bad" };

        var r = await queue.RunAsync(new QueueRequest(QueueVerb.Uninstall, [A, bad, C], WinGetCommands.Uninstall), log.Add);

        Assert.Equal(new PackageOutcome(OperationStatus.Error, "not found"), r.Outcomes["A.A"]);
        Assert.Equal(OperationStatus.Error, r.Outcomes["--bad"].Status);
        Assert.Equal(OperationStatus.Ok, r.Outcomes["C.C"].Status);
        Assert.Contains("   EXCEPTION: not found", log);
        // L'Id non valido non arriva a winget.
        Assert.Equal(["A.A", "C.C"], runner.Calls.Select(c => c[2]));
    }

    [Fact]
    public async Task CancelFinishesThePackageInProgressAndLeavesTheRest()
    {
        var (queue, runner) = Create(_ => FakeRunner.Result(0, ""));
        using var cts = new CancellationTokenSource();
        var log = new List<string>();

        var r = await queue.RunAsync(new QueueRequest(QueueVerb.Update, [A, B, C], WinGetCommands.Upgrade), log.Add,
            (row, outcome) => { if (row == A && outcome is null) cts.Cancel(); }, cts.Token);

        Assert.Single(runner.Calls);
        Assert.Equal(OperationStatus.Ok, r.Outcomes["A.A"].Status);
        Assert.False(r.Outcomes.ContainsKey("B.B"));
        Assert.True(r.Cancelled);
        Assert.Equal("Update cancelled after 1 of 3 packages; the rest were left untouched: 1 ok, 2 not run.", log[^1]);
    }

    // La riga dice che e' in corso (esito null), poi il suo esito.
    [Fact]
    public async Task RowChangesAreReported()
    {
        var (queue, _) = Create(_ => FakeRunner.Result(0, ""));
        var changes = new List<string>();
        await queue.RunAsync(new QueueRequest(QueueVerb.Pin, [A], WinGetCommands.PinAdd), rowChanged: (row, o) => changes.Add($"{row.Id}:{o?.Status.ToString() ?? "running"}"));
        Assert.Equal(["A.A:running", "A.A:Ok"], changes);
    }

    // Nessun timeout: gli installer lenti non si troncano, il log dice solo da quanto girano.
    [Fact]
    public async Task TicksAreLogged()
    {
        var runner = new FakeRunner { Tick = TimeSpan.FromSeconds(30) };
        var log = new List<string>();
        await new PackageQueue(new WinGetCli("winget.exe", runner)).RunAsync(new QueueRequest(QueueVerb.Install, [A], r => WinGetCommands.Install(r, InstallScope.Auto)), log.Add);
        Assert.Contains("   ...App A running for 30s", log);
    }

    // Retry failed: la stessa richiesta sulle sole righe fallite, anche se ricaricate.
    [Fact]
    public async Task RetryReusesTheRequestOnTheFailedRows()
    {
        var (queue, runner) = Create(a => FakeRunner.Result(ExitFor(a), ""));
        var first = await queue.RunAsync(new QueueRequest(QueueVerb.Update, [A, C], WinGetCommands.Upgrade));
        var reloaded = new[] { A, C with { Version = "1.0" } };
        var retry = first.Request with { Rows = reloaded.Where(r => first.FailedIds.Contains(r.Id)).ToList() };

        await queue.RunAsync(retry);

        Assert.Equal(["A.A", "C.C", "C.C"], runner.Calls.Select(c => c[2]));
    }

    private const int AdminContextProhibited = unchecked((int)0x8A15007D);
    private const int UninstallFailed = unchecked((int)0x8A150030);

    private static (PackageQueue Queue, FakeRunner Runner, FakeElevation Elevation) CreateElevated(bool elevated, Func<IReadOnlyList<string>, ProcessResult> respond)
    {
        var runner = new FakeRunner { Respond = respond };
        var elevation = new FakeElevation { IsElevated = elevated };
        return (new PackageQueue(new WinGetCli("winget.exe", runner, elevation)), runner, elevation);
    }

    // Da amministratore winget rifiuta i pacchetti per utente (ADR 0018): la stessa riga si ripete
    // come lo stesso account, senza elevazione, e il suo esito sostituisce il primo.
    [Fact]
    public async Task ElevatedRetriesWithoutElevationWhenWinGetRefusesAdministrator()
    {
        var (queue, _, elevation) = CreateElevated(true, a => FakeRunner.Result(a[2] == "A.A" ? AdminContextProhibited : 0, ""));
        var log = new List<string>();

        var r = await queue.RunAsync(new QueueRequest(QueueVerb.Uninstall, [A, B], WinGetCommands.Uninstall), log.Add);

        Assert.Equal([[.. WinGetCommands.Uninstall(A), "--no-progress"]], elevation.Unelevated);
        Assert.Equal(new PackageOutcome(OperationStatus.Ok, "exit 0", 0), r.Outcomes["A.A"]);
        Assert.Contains("   winget refuses this as administrator: retrying without elevation...", log);
    }

    // Elevati con un altro account i pacchetti per utente sono suoi: ripetere come l'utente della
    // sessione agirebbe su un altro profilo.
    [Fact]
    public async Task ElevatedAsAnotherAccountDoesNotRetry()
    {
        var (queue, _, elevation) = CreateElevated(true, _ => FakeRunner.Result(AdminContextProhibited, ""));
        elevation.OtherAccount = true;
        var log = new List<string>();

        var r = await queue.RunAsync(new QueueRequest(QueueVerb.Uninstall, [A], WinGetCommands.Uninstall), log.Add);

        Assert.Empty(elevation.Unelevated);
        Assert.Equal(OperationStatus.Error, r.Outcomes["A.A"].Status);
        Assert.Contains(@"   winget refuses this as administrator, and the package belongs to PC\admin, which is not the signed-in user: sign in as PC\admin to uninstall it.", log);
    }

    [Fact]
    public async Task UnelevatedNeverRetriesThroughATask()
    {
        var (queue, _, elevation) = CreateElevated(false, _ => FakeRunner.Result(AdminContextProhibited, ""));
        var r = await queue.RunAsync(new QueueRequest(QueueVerb.Uninstall, [A], WinGetCommands.Uninstall));
        Assert.Empty(elevation.Unelevated);
        Assert.Equal(OperationStatus.Error, r.Outcomes["A.A"].Status);
    }

    // Retry as administrator (ADR 0024): le stesse righe di comando in UN solo runas, esito per riga.
    [Fact]
    public async Task ElevatedRetryRunsEveryRowInOneBatch()
    {
        var (queue, runner, elevation) = CreateElevated(false, _ => FakeRunner.Result(0, ""));
        elevation.Respond = a => FakeRunner.Result(a[2] == "B.B" ? 1 : 0, "");
        var log = new List<string>();
        var changes = new List<string>();

        var r = await queue.RunElevatedAsync(new QueueRequest(QueueVerb.Uninstall, [A, B], WinGetCommands.Uninstall), log.Add,
            (row, o) => changes.Add($"{row.Id}:{o?.Status.ToString() ?? "running"}"));

        Assert.Equal([[[.. WinGetCommands.Uninstall(A), "--no-progress"], [.. WinGetCommands.Uninstall(B), "--no-progress"]]], elevation.Batches);
        Assert.Empty(runner.Calls);
        Assert.Equal(["A.A:running", "A.A:Ok", "B.B:running", "B.B:Error"], changes);
        Assert.Equal(new PackageOutcome(OperationStatus.Error, "exit 1", 1), r.Outcomes["B.B"]);
        Assert.Equal("Starting uninstall of 2 packages as administrator: approve the Windows prompt to continue...", log[0]);
        Assert.Equal("Uninstall complete: 1 ok, 1 failed.", log[^1]);
    }

    // UAC rifiutato: un esito suo, e la riga resta ripetibile da amministratore.
    [Fact]
    public async Task DeclinedPromptIsAnOutcomeOfItsOwn()
    {
        var (queue, _, elevation) = CreateElevated(false, _ => FakeRunner.Result(0, ""));
        elevation.Approved = false;
        var log = new List<string>();

        var r = await queue.RunElevatedAsync(new QueueRequest(QueueVerb.Uninstall, [A], WinGetCommands.Uninstall), log.Add);

        Assert.Equal(new PackageOutcome(OperationStatus.Error, "Cancelled at the administrator prompt", 1223), r.Outcomes["A.A"]);
        Assert.Equal(["A.A"], r.ElevatableIds);
        Assert.Contains("Cancelled at the administrator prompt: nothing was run.", log);
    }

    [Fact]
    public void ElevatableIdsAreTheFailuresElevationCanFix()
    {
        var r = new QueueResult(new QueueRequest(QueueVerb.Uninstall, [A, B, C], WinGetCommands.Uninstall), new Dictionary<string, PackageOutcome>
        {
            ["A.A"] = new(OperationStatus.Error, "", UninstallFailed),
            ["B.B"] = new(OperationStatus.Error, "", 1),
            ["C.C"] = new(OperationStatus.Ok, "", 0),
        }, false);
        Assert.Equal(["A.A"], r.ElevatableIds);
    }

    [Theory]
    [InlineData("ok,ok,warning,error,", "2 ok, 1 with warnings, 1 failed, 1 not run")]
    [InlineData("ok", "1 ok")]
    [InlineData("", "1 not run")]
    public void Summary(string statuses, string expected)
    {
        var parsed = statuses.Split(',').Select(s => s switch
        {
            "ok" => OperationStatus.Ok,
            "warning" => OperationStatus.Warning,
            "error" => (OperationStatus?)OperationStatus.Error,
            _ => null,
        });
        Assert.Equal(expected, QueueResult.FormatSummary(parsed));
    }
}
