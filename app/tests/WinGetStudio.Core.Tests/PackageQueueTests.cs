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
        Assert.Equal(new PackageOutcome(OperationStatus.Ok, "exit 0"), r.Outcomes["A.A"]);
        Assert.Equal(OperationStatus.Warning, r.Outcomes["B.B"].Status);
        Assert.Equal(new PackageOutcome(OperationStatus.Error, "exit 1"), r.Outcomes["C.C"]);
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
