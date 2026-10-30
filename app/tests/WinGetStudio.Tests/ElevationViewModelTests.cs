using System.Windows;
using WinGetStudio.Core;
using WinGetStudio.ViewModels;

namespace WinGetStudio.Tests;

// L'app gira non elevata e chiede l'UAC solo quando serve (ADR 0024): Retry as administrator per
// le righe che l'elevazione puo' risolvere, l'attesa dell'UAC che si vede e si annulla, Restart as
// administrator dove l'exe lo permette (ADR 0026), e da elevata il banner e la 1.x (ADR 0018).
public class ElevationViewModelTests
{
    private const int UninstallFailed = unchecked((int)0x8A150030);
    private static readonly PackageRow A = new("Alpha", "A.A", "1.0");
    private static readonly PackageRow B = new("Beta", "B.B", "2.0");

    // Installed con A e B; disinstallare A fallisce con 0x8A150030 (per-machine senza UAC), B con 1.
    private static Harness Create(List<PackageRow> installed, Action<Harness>? setup) =>
        new(h =>
        {
            h.WinGet.Respond = a => a switch
            {
                ["list", ..] => FakeWinGet.Result(0, FakeWinGet.Installed([.. installed])),
                ["pin", "list", ..] => FakeWinGet.Result(0, FakeWinGet.Pins()),
                ["uninstall", "--id", "A.A", ..] => FakeWinGet.Result(UninstallFailed, "Uninstall failed with exit code: 1603"),
                ["uninstall", ..] => FakeWinGet.Result(1, ""),
                _ => FakeWinGet.Result(0, ""),
            };
            setup?.Invoke(h);
        });

    private static async Task<Harness> AfterFailedUninstallAsync(List<PackageRow>? installed = null, Action<Harness>? setup = null)
    {
        var h = Create(installed ?? [A, B], setup);
        await h.Vm.Installed.LoadAsync();
        foreach (var i in h.Vm.Installed.Items) i.Selected = true;
        h.Dialogs.Answer = _ => MessageBoxResult.Yes;
        await h.Vm.Installed.UninstallAsync();
        h.Dialogs.Calls.Clear();
        return h;
    }

    [Fact]
    public async Task OnlyFailuresElevationCanFixAreOfferedAsAdministrator()
    {
        using var h = await AfterFailedUninstallAsync();
        var vm = h.Vm.Installed;

        Assert.True(vm.RetryAdminVisible);
        Assert.Equal("Retry as administrator (1)", vm.RetryAdminText);
        Assert.Equal("Retry failed (2)", vm.RetryText);
    }

    // Conferma con No predefinito; poi le stesse righe di comando in un solo runas, e la lista si
    // rilegge come dopo la coda.
    [Fact]
    public async Task RetryAsAdministratorRunsOneBatchAfterConfirmation()
    {
        var installed = new List<PackageRow> { A, B };
        using var h = await AfterFailedUninstallAsync(installed);
        var vm = h.Vm.Installed;
        h.Dialogs.Answer = c => c.Default;

        await vm.RetryAdminAsync();
        Assert.Empty(h.Elevation.Batches);
        var confirm = Assert.Single(h.Dialogs.Calls);
        Assert.Equal(("Retry as administrator", MessageBoxResult.No), (confirm.Title, confirm.Default));
        Assert.StartsWith("Retry the uninstall of 1 package as administrator?", confirm.Text);

        h.Dialogs.Answer = _ => MessageBoxResult.Yes;
        h.Elevation.Respond = a => { installed.RemoveAll(r => r.Id == a[2]); return FakeWinGet.Result(0, ""); };
        var lists = h.WinGet.Count("list");
        await vm.RetryAdminAsync();

        Assert.Equal([[WinGetCommands.Uninstall(A)]], h.Elevation.Batches);
        Assert.Equal(lists + 1, h.WinGet.Count("list"));
        Assert.Equal(["B.B"], vm.Items.Select(i => i.Id));
        Assert.False(vm.RetryAdminVisible);
    }

    // UAC rifiutato: esito proprio, e la riga resta ripetibile da amministratore.
    [Fact]
    public async Task DeclinedPromptStaysRetryable()
    {
        using var h = await AfterFailedUninstallAsync();
        var vm = h.Vm.Installed;
        h.Elevation.Approved = false;
        h.Dialogs.Answer = _ => MessageBoxResult.Yes;

        await vm.RetryAdminAsync();

        var a = vm.Items.Single(i => i.Id == "A.A");
        Assert.Equal((RowStatus.Error, "Cancelled at the administrator prompt"), (a.Status, a.StatusDetail));
        Assert.Equal("Retry as administrator (1)", vm.RetryAdminText);
        Assert.Contains("Cancelled at the administrator prompt: nothing was run.", h.Log);
    }

    // La riga dice che aspetta l'UAC, e Cancel (il pulsante stesso) smette di aspettare.
    [Fact]
    public async Task WaitingForApprovalShowsAndCancelStopsTheWait()
    {
        using var h = await AfterFailedUninstallAsync();
        var vm = h.Vm.Installed;
        h.Elevation.Approval = new TaskCompletionSource<bool>();
        h.Dialogs.Answer = _ => MessageBoxResult.Yes;

        var retry = vm.RetryAdminAsync();
        var a = vm.Items.Single(i => i.Id == "A.A");
        Assert.Equal((RowStatus.Running, "Waiting for administrator approval"), (a.Status, a.StatusDetail));
        Assert.Equal("Waiting for administrator approval", h.State.ProgressText);
        Assert.Equal("Cancel", vm.RetryAdminText);
        Assert.True(vm.RetryAdminCommand.CanExecute(null));

        await vm.RetryAdminCommand.ExecuteAsync(null);
        await retry;

        Assert.Empty(h.Elevation.Batches);
        Assert.Equal((RowStatus.Error, "Cancelled at the administrator prompt"), (a.Status, a.StatusDetail));
        Assert.Equal("Retry as administrator (1)", vm.RetryAdminText);
        Assert.True(h.State.IsIdle);
        // Il log dice cosa e' successo nell'ordine giusto: prima l'annullamento, poi l'esito.
        var log = h.Log;
        Assert.True(log.IndexOf("Cancelling: no longer waiting for administrator approval.") < log.IndexOf("Cancelled at the administrator prompt: nothing was run."));
    }

    // Elevata: niente Retry as administrator (sarebbe lo stesso livello), un banner che lo dice.
    [Fact]
    public async Task ElevatedAppShowsTheBannerAndNoRetryAsAdministrator()
    {
        using var h = await AfterFailedUninstallAsync(setup: h => h.Elevation.IsElevated = true);

        Assert.False(h.Vm.Installed.RetryAdminVisible);
        Assert.Equal(@"Running as administrator (PC\admin): winget runs elevated, and per-user packages are those of this account.", h.State.ElevatedBanner);
    }

    [Fact]
    public void UnelevatedAppHasNoBanner()
    {
        using var h = new Harness();
        Assert.Null(h.State.ElevatedBanner);
    }

    // Elevata con un altro account, Install avvisa una volta: i pacchetti per utente andrebbero in
    // quel profilo (1.x, ADR 0018).
    [Fact]
    public async Task ElevatedAsAnotherAccountWarnsOnceBeforeInstalling()
    {
        using var h = new Harness(h =>
        {
            h.Elevation.IsElevated = h.Elevation.OtherAccount = true;
            h.WinGet.Respond = a => a is ["search", ..] ? FakeWinGet.Result(0, FakeWinGet.Search(A)) : FakeWinGet.Result(0, "");
        });
        var vm = h.Vm.Install;
        vm.SearchText = "alpha";
        await vm.SearchNowAsync();

        await vm.InstallOneAsync(vm.Items[0]);
        await vm.InstallOneAsync(vm.Items[0]);

        Assert.Equal(1, h.Log.Split('\n').Count(l => l.Contains(@"WARNING: running elevated as PC\admin, not as the signed-in user.")));
    }

    [Theory]
    [InlineData(InstallChannel.Installed, true)]
    [InlineData(InstallChannel.Source, true)]
    [InlineData(InstallChannel.Portable, false)]
    public void RestartAsAdministratorOnlyWhereTheExeAllowsIt(InstallChannel channel, bool offered)
    {
        using var h = new Harness(h => h.Host.Channel = channel);
        var s = h.Vm.Settings;
        Assert.Equal(offered, s.RestartElevatedCommand.CanExecute(null));
        Assert.Equal(offered, s.CanRestartElevated);
        Assert.Equal(offered, s.CanStartElevated);
        if (!offered) Assert.StartsWith("Only in the installed version", s.StartElevatedHint);
    }

    // Always start as administrator si accende solo da elevata (nessun riavvio: lo e' gia').
    [Fact]
    public void StartAsAdministratorTurnsOnOnlyWhenElevated()
    {
        using var h = new Harness(h => h.Host.Channel = InstallChannel.Installed);
        Assert.False(h.Vm.Settings.CanToggleStartElevated);
        h.Vm.Settings.StartElevated = true;
        Assert.False(h.Vm.Settings.StartElevated);
        Assert.False(h.Prefs.GetBool(Preferences.StartElevated, false));
        Assert.Equal("To turn this on, restart as administrator first.", h.Vm.Settings.StartElevatedHint);

        using var e = new Harness(h => { h.Host.Channel = InstallChannel.Installed; h.Elevation.IsElevated = true; });
        Assert.True(e.Vm.Settings.CanToggleStartElevated);
        e.Vm.Settings.StartElevated = true;
        Assert.True(e.Prefs.GetBool(Preferences.StartElevated, false));
        Assert.Empty(e.Dialogs.Calls);
        Assert.Equal(0, e.Host.Restarts);
    }

    // Accesa e non elevata (UAC rifiutato all'avvio) si spegne lo stesso, senza riavvio.
    [Fact]
    public void StartAsAdministratorCanAlwaysBeTurnedOff()
    {
        using var h = new Harness(h => { h.Host.Channel = InstallChannel.Installed; h.Prefs.Set(Preferences.StartElevated, true); });
        Assert.True(h.Vm.Settings.CanToggleStartElevated);
        h.Vm.Settings.StartElevated = false;
        Assert.False(h.Prefs.GetBool(Preferences.StartElevated, true));
        Assert.Empty(h.Dialogs.Calls);
        Assert.False(h.Vm.Settings.CanToggleStartElevated);
    }

    // Togliere la spunta da elevata riavvia subito senza diritti: l'attivita' pianificata avvia
    // l'exe non elevato, poi questa copia si chiude.
    [Fact]
    public async Task UntickingWhileElevatedRestartsWithoutAdministratorRights()
    {
        using var h = new Harness(h =>
        {
            h.Host.Channel = InstallChannel.Installed;
            h.Elevation.IsElevated = true;
            h.Prefs.Set(Preferences.StartElevated, true);
        });
        var closed = false;
        h.Vm.Settings.CloseRequested += () => closed = true;
        Assert.True(h.Vm.Settings.StartElevated);
        h.Dialogs.Answer = _ => MessageBoxResult.Yes;

        h.Vm.Settings.StartElevated = false;
        await h.State.LastFired;

        Assert.False(h.Prefs.GetBool(Preferences.StartElevated, true));
        Assert.Equal((1, true), (h.Host.UnelevatedRestarts, closed));
    }

    // All'avvio, anche da Start with Windows, la spunta chiede l'UAC; rifiutato si resta non elevati.
    [Fact]
    public void StartupElevatesWhenTheBoxIsTicked()
    {
        using var h = new Harness(h => { h.Host.Channel = InstallChannel.Installed; h.Prefs.Set(Preferences.StartElevated, true); });
        Assert.True(h.Vm.Settings.ElevateAtStartup());
        Assert.Equal(1, h.Host.Restarts);

        h.Host.RestartApproved = false;
        Assert.False(h.Vm.Settings.ElevateAtStartup());
        Assert.Contains("Starting without administrator rights: the administrator prompt was declined.", h.Log);

        // Da Start with Windows la spunta non conta: nessun UAC all'accesso.
        Assert.False(h.Vm.Settings.ElevateAtStartup(automatic: true));
        Assert.Equal(2, h.Host.Restarts);

        using var off = new Harness(h => h.Host.Channel = InstallChannel.Installed);
        Assert.False(off.Vm.Settings.ElevateAtStartup());
        using var elevated = new Harness(h => { h.Host.Channel = InstallChannel.Installed; h.Elevation.IsElevated = true; h.Prefs.Set(Preferences.StartElevated, true); });
        Assert.False(elevated.Vm.Settings.ElevateAtStartup());
        using var portable = new Harness(h => { h.Host.Channel = InstallChannel.Portable; h.Prefs.Set(Preferences.StartElevated, true); });
        Assert.False(portable.Vm.Settings.ElevateAtStartup());
        Assert.Equal(0, elevated.Host.Restarts + portable.Host.Restarts + off.Host.Restarts);
    }

    [Fact]
    public void RestartAsAdministratorClosesThisCopy()
    {
        using var h = new Harness(h => h.Host.Channel = InstallChannel.Installed);
        var closed = false;
        h.Vm.Settings.CloseRequested += () => closed = true;

        h.Vm.Settings.RestartElevatedCommand.Execute(null);

        Assert.Equal((1, true), (h.Host.Restarts, closed));
    }

    [Fact]
    public void DeclinedRestartKeepsThisCopy()
    {
        using var h = new Harness(h => { h.Host.Channel = InstallChannel.Installed; h.Host.RestartApproved = false; });
        var closed = false;
        h.Vm.Settings.CloseRequested += () => closed = true;

        h.Vm.Settings.RestartElevatedCommand.Execute(null);

        Assert.False(closed);
        Assert.Contains("Restart cancelled at the administrator prompt.", h.Log);
    }

    // Non si chiude l'app sopra una coda; e da elevata non c'e' nulla da riavviare.
    [Fact]
    public void RestartAsAdministratorWaitsForIdleAndIsOffWhenElevated()
    {
        using var h = new Harness(h => h.Host.Channel = InstallChannel.Installed);
        Assert.True(h.State.TryBegin());
        Assert.False(h.Vm.Settings.RestartElevatedCommand.CanExecute(null));
        h.State.End();
        Assert.True(h.Vm.Settings.RestartElevatedCommand.CanExecute(null));

        using var e = new Harness(h => { h.Host.Channel = InstallChannel.Installed; h.Elevation.IsElevated = true; });
        Assert.False(e.Vm.Settings.RestartElevatedCommand.CanExecute(null));
    }
}
