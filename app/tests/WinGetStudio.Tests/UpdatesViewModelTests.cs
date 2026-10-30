using System.Windows;
using WinGetStudio.Core;
using WinGetStudio.ViewModels;

namespace WinGetStudio.Tests;

// Scheda Updates (Tab.Updates.ps1 della 1.x): coda con esito per riga, Cancel che finisce il
// pacchetto in corso, ricarica con l'esito riportato per Id, Retry failed, pin saltati.
public class UpdatesViewModelTests
{
    private static readonly PackageRow A = new("App A", "A.A", "1.0", "2.0");
    private static readonly PackageRow B = new("App B", "B.B", "1.0", "2.0");
    private static readonly PackageRow C = new("App C", "C.C", "1.0", "2.0");

    // upgrade: le righe in "available", tolte quelle riuscite; pin list: i pinnati.
    private static Harness Create(List<PackageRow> available, List<string>? pins = null, Func<string, int>? exitFor = null) =>
        new(h => h.WinGet.Respond = a => a switch
        {
            ["upgrade", "--accept-source-agreements", ..] => FakeWinGet.Result(0, FakeWinGet.Upgrades([.. available])),
            ["pin", "list", ..] => FakeWinGet.Result(0, FakeWinGet.Pins([.. pins ?? []])),
            ["pin", "add", _, _, var id, ..] => Pin(pins!, id, true),
            ["pin", "remove", _, var id, ..] => Pin(pins!, id, false),
            ["upgrade", "--id", var id, ..] => Upgrade(available, id, exitFor?.Invoke(id) ?? 0),
            _ => FakeWinGet.Result(0, ""),
        });

    private static ProcessResult Upgrade(List<PackageRow> available, string id, int exit)
    {
        if (exit == 0) available.RemoveAll(r => r.Id == id);
        return FakeWinGet.Result(exit, exit == 0 ? "" : "Installer failed\r\nLog: C:\\x.log\r\n");
    }

    private static ProcessResult Pin(List<string> pins, string id, bool add)
    {
        if (add) pins.Add(id); else pins.Remove(id);
        return FakeWinGet.Result(0, "");
    }

    [Fact]
    public async Task LoadListsUpgradesAndFlagsPins()
    {
        using var h = Create([A, B, C], ["B.B"]);
        var vm = h.Vm.Updates;

        await vm.LoadAsync();

        Assert.Equal(["A.A", "B.B", "C.C"], vm.Items.Select(i => i.Id));
        Assert.Equal([false, true, false], vm.Items.Select(i => i.Pinned));
        Assert.Equal("3 updates available", vm.AvailableText);
        // Il numero va nel badge della linguetta; le altre schede non ne hanno.
        Assert.Equal("3", vm.Badge);
        Assert.Equal("", h.Vm.Installed.Badge);
        Assert.Contains("Searching for updates...", h.Log);
        Assert.Contains("Found 3 updates.", h.Log);
        Assert.False(h.State.IsBusy);
        // Upgrade e pin nella stessa operazione, uno dopo l'altro (ADR 0003).
        Assert.Equal(1, h.WinGet.MaxRunning);
    }

    [Fact]
    public async Task EmptyAndFailedReadsSayDifferentThings()
    {
        using var empty = Create([]);
        await empty.Vm.Updates.LoadAsync();
        Assert.Equal("No updates available.", empty.Vm.Updates.EmptyText);

        using var failed = new Harness(h => h.WinGet.Respond = a => a[0] == "upgrade"
            ? FakeWinGet.Result(-1978335231, "x\r\nFailed to open the source\r\n") : FakeWinGet.Result(0, ""));
        await failed.Vm.Updates.LoadAsync();
        Assert.Equal("winget upgrade failed (exit -1978335231): x Failed to open the source", failed.Vm.Updates.EmptyText);
    }

    [Fact]
    public async Task UnknownIsSavedAndReloads()
    {
        using var h = Create([A]);
        h.Vm.Updates.IncludeUnknown = true;
        await h.State.LastFired;

        Assert.True(h.Prefs.GetBool(Preferences.IncludeUnknown, false));
        Assert.Contains(h.WinGet.Calls, c => c is ["upgrade", "--accept-source-agreements", "--include-unknown"]);
    }

    [Fact]
    public async Task SelectAllSkipsPinnedRows()
    {
        using var h = Create([A, B, C], ["B.B"]);
        var vm = h.Vm.Updates;
        await vm.LoadAsync();

        // La spunta nell'intestazione: spenta, tutte, alcune (indeterminata).
        Assert.Equal((false, true), (vm.AllChecked, vm.CanCheckAll));
        vm.AllChecked = true;
        Assert.Equal([true, false, true], vm.Items.Select(i => i.Selected));
        Assert.True(vm.AllChecked);
        Assert.Equal("2 selected", vm.SelectedText);

        vm.Items[0].Selected = false;
        Assert.Null(vm.AllChecked);
        vm.AllChecked = false;
        Assert.All(vm.Items, i => Assert.False(i.Selected));
        Assert.False(vm.AllChecked);
    }

    [Fact]
    public async Task UpdateRunsTheQueueThenReloadsWithTheOutcomeById()
    {
        using var h = Create([A, B, C], exitFor: id => id == "C.C" ? 1 : 0);
        var vm = h.Vm.Updates;
        await vm.LoadAsync();
        foreach (var i in vm.Items) i.Selected = true;

        await vm.UpdateAsync();

        Assert.Equal(["A.A", "B.B", "C.C"], h.WinGet.Calls.Where(c => c[1] == "--id").Select(c => c[2]));
        // Con un fallimento non si riscansiona: la lista resta coi suoi esiti, vecchia, e la
        // nuova ricerca la decide l'utente (Check). Retry failed resta disponibile.
        Assert.Equal(1, h.WinGet.Count("upgrade", "--accept-source-agreements"));
        Assert.Equal([RowStatus.Ok, RowStatus.Ok, RowStatus.Error], vm.Items.Select(i => i.Status));
        Assert.Equal("exit 1", vm.Items[2].StatusDetail);
        Assert.Contains("Update complete: 2 ok, 1 failed.", h.Log);
        Assert.True(vm.Stale);
        Assert.Equal("list out of date - press Check", vm.SelectedText);
        Assert.False(vm.UpdateCommand.CanExecute(null));
        Assert.Equal(1, vm.RetryCount);
        Assert.Equal("Retry failed (1)", vm.RetryText);
        Assert.True(vm.RetryCommand.CanExecute(null));
        Assert.False(h.State.IsBusy);
    }

    [Fact]
    public async Task PinnedRowsAreLeftOutOfTheQueue()
    {
        using var h = Create([A, B], ["B.B"]);
        var vm = h.Vm.Updates;
        await vm.LoadAsync();
        foreach (var i in vm.Items) i.Selected = true;   // spuntata prima che il pin arrivasse

        await vm.UpdateAsync();

        Assert.Equal(["A.A"], h.WinGet.Calls.Where(c => c[1] == "--id").Select(c => c[2]));
        Assert.Contains("Skipping 1 pinned package: remove the pin to update it.", h.Log);
    }

    [Fact]
    public async Task NothingSelectedSaysSo()
    {
        using var h = Create([A]);
        await h.Vm.Updates.LoadAsync();
        await h.Vm.Updates.UpdateAsync();
        Assert.Equal("No items selected.", Assert.Single(h.Dialogs.Calls).Text);
    }

    [Fact]
    public async Task UpdateBecomesCancelAndFinishesThePackageInProgress()
    {
        using var h = Create([A, B, C]);
        var vm = h.Vm.Updates;
        await vm.LoadAsync();
        foreach (var i in vm.Items) i.Selected = true;
        var release = new TaskCompletionSource();
        h.WinGet.Before = a => a[1] == "--id" && a[2] == "A.A" ? release.Task : Task.CompletedTask;

        var queue = vm.UpdateAsync();
        Assert.Equal("Cancel", vm.UpdateButtonText);
        Assert.True(vm.UpdateCommand.CanExecute(null));

        var cancel = vm.UpdateAsync();   // secondo clic: Cancel
        Assert.Equal("Cancelling...", vm.UpdateButtonText);
        Assert.False(vm.UpdateCommand.CanExecute(null));
        release.SetResult();
        await Task.WhenAll(queue, cancel);

        Assert.Equal(["A.A"], h.WinGet.Calls.Where(c => c[1] == "--id").Select(c => c[2]));
        Assert.Contains("Cancelling: the package in progress will finish, then the queue stops.", h.Log);
        Assert.Contains("Update cancelled after 1 of 3 packages; the rest were left untouched: 1 ok, 2 not run.", h.Log);
        Assert.Equal("Update", vm.UpdateButtonText);
    }

    [Fact]
    public async Task ACancelFromAnotherTabIsNotOffered()
    {
        using var h = Create([A]);
        var release = new TaskCompletionSource();
        h.WinGet.Before = a => a[0] == "uninstall" ? release.Task : Task.CompletedTask;
        await h.Vm.Updates.LoadAsync();
        h.Vm.Updates.Items[0].Selected = true;

        var other = h.State.RunQueueAsync(new QueueRequest(QueueVerb.Uninstall, [A], WinGetCommands.Uninstall), [], null);

        Assert.Equal("Update", h.Vm.Updates.UpdateButtonText);
        Assert.False(h.Vm.Updates.UpdateCommand.CanExecute(null));
        release.SetResult();
        await other;
    }

    [Fact]
    public async Task RetryFailedAsksWithNoAsDefaultAndRepeatsOnlyTheFailedRows()
    {
        var failing = true;
        using var h = Create([A, C], exitFor: id => id == "C.C" && failing ? 1 : 0);
        var vm = h.Vm.Updates;
        await vm.LoadAsync();
        foreach (var i in vm.Items) i.Selected = true;
        await vm.UpdateAsync();

        // Invio: No, quindi niente.
        await vm.RetryAsync();
        var ask = Assert.Single(h.Dialogs.Calls);
        Assert.Equal((MessageBoxButton.YesNo, MessageBoxResult.No, "Retry failed"), (ask.Button, ask.Default, ask.Title));
        Assert.StartsWith("Retry the update of 1 package that failed?\n\n  - App C", ask.Text);
        Assert.Equal(2, h.WinGet.Calls.Count(c => c[1] == "--id"));

        failing = false;
        h.Dialogs.Answer = _ => MessageBoxResult.Yes;
        await vm.RetryAsync();
        Assert.Equal(["A.A", "C.C", "C.C"], h.WinGet.Calls.Where(c => c[1] == "--id").Select(c => c[2]));
        Assert.Empty(vm.Items);
        Assert.Equal(0, vm.RetryCount);
    }

    [Fact]
    public async Task PinRereadsThePinsInsideTheBusyState()
    {
        List<string> pins = [];
        using var h = Create([A, B], pins);
        var vm = h.Vm.Updates;
        await vm.LoadAsync();
        var busyAtReread = new List<bool>();
        h.WinGet.Before = a => { if (a is ["pin", "list", ..]) busyAtReread.Add(h.State.IsBusy); return Task.CompletedTask; };

        await vm.PinAsync([vm.Items[0], vm.Items[1]]);

        Assert.Equal(["A.A", "B.B"], pins);
        Assert.Equal([true], busyAtReread);
        Assert.All(vm.Items, i => Assert.True(i.Pinned));
        Assert.False(h.State.IsBusy);
        // Gia' pinnati: nessun winget, una riga nel log.
        await vm.PinAsync([vm.Items[0]]);
        Assert.Contains("Already pinned.", h.Log);
        Assert.Equal(2, h.WinGet.Count("pin", "add"));

        await vm.UnpinAsync([vm.Items[1]]);
        Assert.Equal(["A.A"], pins);
        Assert.False(vm.Items[1].Pinned);
    }

    [Fact]
    public async Task DetailsShowWingetTextWithLinks()
    {
        using var h = Create([A]);
        await h.Vm.Updates.LoadAsync();
        h.WinGet.Respond = a => FakeWinGet.Result(0, a[0] == "list" ? "Found App A\r\nHomepage: https://a.example/" : "");
        var busy = new List<bool>();
        h.WinGet.Before = _ => { busy.Add(h.State.IsBusy); return Task.CompletedTask; };

        await h.Vm.Updates.DetailsAsync(h.Vm.Updates.Items[0]);

        var d = Assert.Single(h.Dialogs.Calls);
        Assert.Equal(("App A - details", true), (d.Title, d.Links));
        Assert.Contains("https://a.example/", d.Text);
        Assert.All(busy, Assert.True);
        Assert.Contains("Reading the details of App A [A.A]...", h.Log);
        Assert.False(h.State.IsBusy);
    }

    [Fact]
    public async Task AnActionElsewhereMakesTheListStale()
    {
        using var h = Create([A]);
        var vm = h.Vm.Updates;
        await vm.LoadAsync();
        vm.Items[0].Selected = true;

        h.State.MarkUpdatesStale();

        Assert.False(vm.UpdateCommand.CanExecute(null));
        Assert.Equal("list out of date - press Check", vm.SelectedText);
        // Riaprire la scheda la rilegge.
        h.Vm.SelectedTab = MainViewModel.InstallTab;
        h.Vm.SelectedTab = MainViewModel.UpdatesTab;
        await h.State.LastFired;
        Assert.Equal(2, h.WinGet.Count("upgrade", "--accept-source-agreements"));
        Assert.False(vm.Stale);
    }
}
