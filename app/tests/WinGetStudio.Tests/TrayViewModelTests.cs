using WinGetStudio.Core;
using WinGetStudio.ViewModels;

namespace WinGetStudio.Tests;

// Icona nell'area di notifica (ADR 0030): il pallino, la notifica, il controllo periodico,
// Close to tray e l'avvio nascosto con Windows.
public class TrayViewModelTests
{
    private static readonly PackageRow A = new("App A", "A.A", "1.0", "2.0");
    private static readonly PackageRow B = new("App B", "B.B", "1.0", "2.0");

    // upgrade: le righe in "available"; upgrade --id: exit da exitFor.
    private static Harness Create(List<PackageRow> available, Func<string, int>? exitFor = null) =>
        new(h => h.WinGet.Respond = a => a switch
        {
            ["upgrade", "--accept-source-agreements", ..] => FakeWinGet.Result(0, FakeWinGet.Upgrades([.. available])),
            ["upgrade", "--id", var id, ..] => FakeWinGet.Result(exitFor?.Invoke(id) ?? 0, ""),
            _ => FakeWinGet.Result(0, ""),
        });

    // Giallo (in corso) > rosso (errori nell'ultima coda) > verde (aggiornamenti) > blu.
    [Fact]
    public async Task DotFollowsThePriority()
    {
        using var h = Create([A, B], id => id == "B.B" ? 1 : 0);
        var tray = h.Vm.Tray;
        Assert.Equal(TrayDot.Idle, tray.Dot);

        var release = new TaskCompletionSource();
        h.WinGet.Before = a => a is ["upgrade", "--accept-source-agreements", ..] ? release.Task : Task.CompletedTask;
        var load = h.Vm.Updates.LoadAsync();
        Assert.Equal(TrayDot.Busy, tray.Dot);
        release.SetResult();
        await load;
        Assert.Equal(TrayDot.Updates, tray.Dot);
        Assert.Equal("WinGet Studio - 2 updates available", tray.ToolTip);

        foreach (var i in h.Vm.Updates.Items) i.Selected = true;
        await h.Vm.Updates.UpdateAsync();
        Assert.Equal(TrayDot.Errors, tray.Dot);
        Assert.Equal("WinGet Studio - 1 failed in the last update", tray.ToolTip);
    }

    // Solo con la finestra non attiva, e solo per aggiornamenti non ancora annunciati: un
    // controllo ogni ora non ripete la stessa notifica.
    [Fact]
    public async Task NotifiesNewUpdatesOnlyWithTheWindowInactive()
    {
        var available = new List<PackageRow> { A };
        using var h = Create(available);
        var tray = h.Vm.Tray;
        var shown = new List<(string Title, string Text)>();
        tray.Notify += (title, text) => shown.Add((title, text));

        tray.WindowActive = true;
        await h.Vm.Updates.LoadAsync();
        Assert.Empty(shown);

        tray.WindowActive = false;
        await tray.BackgroundCheckAsync();
        Assert.Empty(shown);   // A era gia' a schermo

        available.Add(B);
        await tray.BackgroundCheckAsync();
        Assert.Equal(("2 updates available", "App A, App B"), Assert.Single(shown));

        await tray.BackgroundCheckAsync();
        Assert.Single(shown);
    }

    // Check for updates dal menu: l'esito si dice sempre, anche senza novita' e a finestra attiva.
    [Fact]
    public async Task CheckFromTheMenuAlwaysReports()
    {
        using var h = Create([]);
        h.Vm.Tray.WindowActive = true;
        var shown = new List<string>();
        h.Vm.Tray.Notify += (title, _) => shown.Add(title);
        await h.Vm.Tray.CheckNowAsync();
        Assert.Equal(["No updates available."], shown);
    }

    // Il controllo periodico non parte sopra un altro winget (ADR 0003), ricerche comprese:
    // parte appena il winget finisce.
    [Fact]
    public async Task BackgroundCheckWaitsForTheWinGetInProgress()
    {
        using var h = Create([A]);
        var release = new TaskCompletionSource();
        h.WinGet.Before = a => a[0] == "search" ? release.Task : Task.CompletedTask;
        h.Vm.Install.SearchText = "app";
        var search = h.Vm.Install.SearchNowAsync();
        Assert.True(h.State.IsWinGetBusy);

        await h.Vm.Tray.BackgroundCheckAsync();
        Assert.Equal(0, h.WinGet.Count("upgrade"));

        release.SetResult();
        await search;
        await h.State.LastFired;
        Assert.Equal(1, h.WinGet.Count("upgrade"));
        Assert.Equal(1, h.WinGet.MaxRunning);
    }

    // Il controllo periodico tiene gli esiti delle righe: un fallimento resta da ripetere.
    [Fact]
    public async Task BackgroundCheckKeepsTheOutcomes()
    {
        using var h = Create([A, B], id => id == "B.B" ? 1 : 0);
        await h.Vm.Updates.LoadAsync();
        foreach (var i in h.Vm.Updates.Items) i.Selected = true;
        await h.Vm.Updates.UpdateAsync();

        await h.Vm.Tray.BackgroundCheckAsync();

        Assert.Equal(RowStatus.Error, h.Vm.Updates.Items.Single(i => i.Id == "B.B").Status);
        Assert.Equal(1, h.Vm.Updates.RetryCount);
    }

    [Fact]
    public void CheckIntervalIsSavedAndNeverByDefault()
    {
        using var h = new Harness();
        var s = h.Vm.Settings;
        Assert.Equal(("Never", null), (s.SelectedCheckInterval, s.CheckEvery));
        s.SelectedCheckInterval = "Every 6 hours";
        Assert.Equal(TimeSpan.FromHours(6), s.CheckEvery);
        Assert.Equal("Every 6 hours", h.Prefs.GetString(Preferences.CheckInterval, ""));
        Assert.Equal(["Never", "Every hour", "Every 6 hours", "Every 24 hours"], s.CheckIntervals);
    }

    // La X chiude l'app come prima; con Close to tray nasconde la finestra. Exit dal menu, un
    // aggiornamento o la fine della sessione chiudono davvero.
    [Fact]
    public void CloseToTrayHidesUntilExit()
    {
        using var h = new Harness();
        Assert.False(h.Vm.Settings.CloseToTray);
        Assert.False(h.Vm.HidesOnClose);
        h.Vm.Settings.CloseToTray = true;
        Assert.True(h.Prefs.GetBool(Preferences.CloseToTray, false));
        Assert.True(h.Vm.HidesOnClose);
        h.Vm.BeginExit();
        Assert.False(h.Vm.HidesOnClose);
    }

    // Avviata da Start with Windows (--startup) parte nell'area di notifica, senza finestra; ma
    // senza winget la finestra serve, per proporre di installarlo.
    [Fact]
    public void StartupArgumentStartsHidden()
    {
        using (var h = new Harness())
        {
            Assert.True(h.Vm.StartsHidden([Autostart.StartupArgument]));
            Assert.False(h.Vm.StartsHidden([]));
        }
        using var missing = new Harness(h => h.WinGetFound = false);
        Assert.False(missing.Vm.StartsHidden([Autostart.StartupArgument]));
    }

    // Partita nascosta, la scansione all'avvio gira subito; aprire la finestra dopo non la ripete.
    [Fact]
    public async Task StartRunsOnce()
    {
        using var h = Create([A]);
        await h.Vm.StartAsync();
        await h.Vm.StartAsync();
        Assert.Equal(1, h.WinGet.Count("upgrade"));
    }
}
