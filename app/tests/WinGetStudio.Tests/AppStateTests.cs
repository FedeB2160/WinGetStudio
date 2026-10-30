using System.IO;
using WinGetStudio.Core;
using WinGetStudio.ViewModels;

// Le code bloccano winget statico (WinGetCli.Gate) e i test guardano lo stato a meta' coda:
// in parallelo, un test aspetterebbe il lock tenuto da un altro e il suo Cancel arriverebbe
// prima del primo pacchetto.
[assembly: CollectionBehavior(CollectionBehavior.CollectionPerAssembly)]

namespace WinGetStudio.Tests;

// Stato occupato globale: un solo winget alla volta (ADR 0003), ricerche comprese; log.
public class AppStateTests
{
    private static readonly PackageRow A = new("App A", "A.A", "1.0", "2.0");

    [Fact]
    public async Task NoScanStartsWhileASearchIsInFlight()
    {
        using var h = new Harness();
        var release = new TaskCompletionSource();
        h.WinGet.Before = a => a[0] == "search" ? release.Task : Task.CompletedTask;
        h.Vm.Install.SearchText = "7zip";
        var search = h.Vm.Install.SearchNowAsync();
        Assert.True(h.State.IsWinGetBusy);

        await h.Vm.Updates.LoadAsync();
        await h.Vm.Installed.LoadAsync();
        await h.Vm.Installed.ExportAsync();

        release.SetResult();
        await search;
        Assert.Equal(["search"], h.WinGet.Calls.Select(c => c[0]));
        Assert.False(h.State.IsWinGetBusy);
    }

    [Fact]
    public async Task NoSearchOrQueueStartsWhileBusy()
    {
        using var h = new Harness();
        var release = new TaskCompletionSource();
        h.WinGet.Before = a => a[0] == "upgrade" ? release.Task : Task.CompletedTask;
        var load = h.Vm.Updates.LoadAsync();
        Assert.True(h.State.IsBusy);
        Assert.False(h.State.IsIdle);

        h.Vm.Install.SearchText = "7zip";
        await h.Vm.Install.SearchNowAsync();
        var queued = await h.State.RunQueueAsync(new QueueRequest(QueueVerb.Install, [A], r => WinGetCommands.Install(r, InstallScope.Auto)), [], null);

        release.SetResult();
        await load;
        Assert.Null(queued);
        Assert.Contains("Another winget operation is still running: try again in a moment.", h.Log);
        Assert.DoesNotContain(h.WinGet.Calls, c => c[0] is "search" or "install");
        Assert.Equal(1, h.WinGet.MaxRunning);
    }

    // La barra condivisa e' per le code: una scansione ha lo spinner della sua scheda.
    [Fact]
    public async Task SharedProgressBarOnlyForQueues()
    {
        var shown = new List<(string, bool, bool)>();
        using var h = new Harness(h => h.WinGet.Respond = a => FakeWinGet.Result(0, a[0] == "upgrade" ? FakeWinGet.Upgrades(A) : ""));
        h.WinGet.Before = a => { shown.Add((a[0], h.State.ShowProgress, h.Vm.Updates.Loading)); return Task.CompletedTask; };
        await h.Vm.Updates.LoadAsync();
        h.Vm.Updates.Items[0].Selected = true;
        await h.Vm.Updates.UpdateAsync();
        // Scansione: spinner, niente barra. Coda: barra.
        Assert.Contains(("upgrade", false, true), shown);
        Assert.Contains(("upgrade", true, false), shown);
        Assert.False(h.State.ShowProgress);
    }

    [Fact]
    public async Task QueueShowsProgressAndTicksInTheLog()
    {
        using var h = new Harness();
        h.WinGet.Tick = TimeSpan.FromSeconds(30);
        var progress = new List<double>();
        h.State.PropertyChanged += (_, e) => { if (e.PropertyName == nameof(AppState.ProgressValue)) progress.Add(h.State.ProgressValue); };

        await h.State.RunQueueAsync(new QueueRequest(QueueVerb.Install, [A, A with { Id = "B.B" }], r => WinGetCommands.Install(r, InstallScope.Auto)), [], null);

        Assert.Equal(2, h.State.ProgressMaximum);
        Assert.Equal([1, 2], progress);
        Assert.Contains("   ...App A running for 30s", h.Log);
    }

    [Fact]
    public void LogLinesHaveATimestampAndCanBeSavedAndCleared()
    {
        var log = new LogViewModel();
        var lines = new List<string>();
        log.Appended += lines.Add;
        log.Write("hello");
        Assert.Matches(@"^\[\d\d:\d\d:\d\d\] hello\r\n$", lines[0]);

        var file = Path.Combine(Path.GetTempPath(), $"wgt-test-{Guid.NewGuid():N}.txt");
        try
        {
            log.SaveTo(file);
            Assert.Contains("hello", File.ReadAllText(file));
            Assert.EndsWith($"Log saved to {file}\r\n", log.Text);
        }
        finally { File.Delete(file); }

        log.Clear();
        Assert.Equal("", log.Text);
    }

    // Righe dal thread del processo (il tick ogni 30 s): passano dal contesto della UI.
    [Fact]
    public async Task LinesFromAnotherThreadArePostedToTheUi()
    {
        var ui = new RecordingContext();
        var log = new LogViewModel(ui);
        await Task.Run(() => log.Write("tick"));
        Assert.Equal(1, ui.Posts);
        Assert.Contains("tick", log.Text);
    }

    private sealed class RecordingContext : SynchronizationContext
    {
        public int Posts;
        public override void Post(SendOrPostCallback d, object? state) { Posts++; d(state); }
    }

    [Theory]
    [InlineData("See https://7-zip.org/.", "See |https://7-zip.org/|.")]
    [InlineData("(https://a.example/x?y=1), next", "(|https://a.example/x?y=1|), next")]
    [InlineData("no link", "no link")]
    public void LinksAreFoundWithoutClosingPunctuation(string text, string expected)
    {
        var parts = LinkText.Split(text).Select(p => p.Text);
        Assert.Equal(expected, string.Join("|", parts));
        Assert.Equal(expected.Contains('|'), LinkText.Split(text).Any(p => p.IsLink));
    }
}
