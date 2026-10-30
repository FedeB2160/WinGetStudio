using System.IO;
using System.Windows;
using WinGetStudio.Core;
using WinGetStudio.ViewModels;

namespace WinGetStudio.Tests;

// Scheda Settings: tema, linguette, self-update (ADR 0013, 0022) e winget stesso (ADR 0019).
public class SettingsViewModelTests
{
    [Fact]
    public void ThemeIsSavedAndAppliedAtOnce()
    {
        using var h = new Harness(h => h.Prefs.Set(Preferences.Theme, "Auto"));
        var s = h.Vm.Settings;
        // "Auto" delle 1.x fino alla 1.9.0: lo stesso comportamento di System.
        Assert.Equal("System", s.SelectedTheme);
        Assert.StartsWith("following the system: ", s.ThemeHint);
        string? applied = null;
        s.ApplyTheme = t => applied = t;
        s.SelectedTheme = "Dark";
        Assert.Equal(("Dark", "Dark", ""), (applied, h.Prefs.GetString(Preferences.Theme, ""), s.ThemeHint));
    }

    // Settings e About sono finestre a parte, aperte dai pulsanti in alto a destra (ADR 0028).
    [Fact]
    public void SettingsAndAboutOpenAsPages()
    {
        using var h = new Harness();
        h.Vm.OpenSettingsCommand.Execute(null);
        h.Vm.OpenAboutCommand.Execute(null);
        Assert.Equal(["Settings", "About 2.0.0"], h.Dialogs.Pages);
    }

    // Il controllo parla solo con GitHub e con winget --version (sotto il lock): non va in conflitto
    // con una coda, quindi resta sempre premibile. L'installazione invece aspetta.
    [Fact]
    public async Task CheckForUpdatesStaysAvailableWhileBusy()
    {
        using var h = new Harness();
        h.Host.Releases[SelfUpdate.Repo] = FakeUpdateHost.Release("v9.0.0");
        Assert.True(h.State.TryBegin());
        Assert.True(h.Vm.Settings.CheckForUpdatesCommand.CanExecute(null));
        await h.Vm.Settings.CheckForUpdatesCommand.ExecuteAsync(null);
        Assert.True(h.Vm.Settings.UpdateAppVisible);
        Assert.False(h.Vm.Settings.UpdateAppCommand.CanExecute(null));
        h.State.End();
        Assert.True(h.Vm.Settings.UpdateAppCommand.CanExecute(null));
    }

    // Avvio con Windows: legge e scrive la voce vera; una build di sviluppo non ha un exe da avviare.
    [Fact]
    public void StartWithWindowsFollowsTheRunEntry()
    {
        using var h = new Harness(h => h.Host.StartsWithWindows = true);
        var s = h.Vm.Settings;
        Assert.Equal((true, true), (s.CanStartWithWindows, s.StartWithWindows));
        s.StartWithWindows = false;
        Assert.False(h.Host.StartsWithWindows);

        using var dev = new Harness(h => h.Host.ExePath = null);
        Assert.False(dev.Vm.Settings.CanStartWithWindows);
        dev.Vm.Settings.StartWithWindows = true;
        Assert.False(dev.Host.StartsWithWindows);
    }

    [Fact]
    public void TabStripShowsIconTextOrBoth()
    {
        using var h = new Harness(h => h.Prefs.Set(Preferences.TabHeaderStyle, "Big"));
        var s = h.Vm.Settings;
        Assert.Equal(("Icon + Text", true, true), (s.SelectedTabStyle, s.TabIconVisible, s.TabTextVisible));
        s.SelectedTabStyle = "Icon";
        Assert.Equal((true, false), (s.TabIconVisible, s.TabTextVisible));
        s.SelectedTabStyle = "Text";
        Assert.Equal((false, true, "Text"), (s.TabIconVisible, s.TabTextVisible, h.Prefs.GetString(Preferences.TabHeaderStyle, "")));
    }

    // Spento, all'avvio non si va su GitHub; la versione di winget si legge lo stesso.
    [Fact]
    public async Task StartupCheckHonoursCheckAtStartup()
    {
        using var h = new Harness(h => h.Prefs.Set(Preferences.CheckAtStartup, false));
        h.Host.Releases[SelfUpdate.Repo] = FakeUpdateHost.Release("v9.0.0");
        await h.Vm.StartAsync();
        Assert.Empty(h.Host.Requests);
        Assert.Equal("v1.29.380", h.Vm.Settings.WinGetVersionText);
        Assert.False(h.Vm.Settings.UpdateAppVisible);
        // Il pulsante invece va in rete: chi lo preme lo sta chiedendo adesso.
        await h.Vm.Settings.CheckForUpdatesCommand.ExecuteAsync(null);
        Assert.True(h.Vm.Settings.UpdateAppVisible);
    }

    // Il controllo all'avvio NON aspetta lo stato occupato: la scansione lo alza nello stesso
    // momento, e con la guardia non partiva mai (ADR 0013, dalla v1.9.0 alla v1.11.1).
    [Fact]
    public async Task StartupCheckRunsWhileTheScanIsBusy()
    {
        var scanning = new TaskCompletionSource();
        using var h = new Harness(h => h.WinGet.Before = a => a[0] == "upgrade" ? scanning.Task : Task.CompletedTask);
        h.Host.Releases[SelfUpdate.Repo] = FakeUpdateHost.Release("v9.0.0");
        var busyDuringCheck = false;
        h.Host.Before = () => { busyDuringCheck = h.State.IsBusy; return Task.CompletedTask; };
        var start = h.Vm.StartAsync();
        await Task.Delay(50);
        Assert.True(busyDuringCheck);
        Assert.True(h.Vm.Settings.UpdateAppVisible);
        Assert.Equal("Update to v9.0.0", h.Vm.Settings.UpdateAppText);
        Assert.Contains("Version v9.0.0 is available (you have v2.0.0).", h.Log);
        // Il pulsante resta spento finche' la scansione non finisce.
        Assert.False(h.Vm.Settings.UpdateAppCommand.CanExecute(null));
        scanning.SetResult();
        await start;
        Assert.True(h.Vm.Settings.UpdateAppCommand.CanExecute(null));
    }

    [Fact]
    public async Task ManualCheckAlwaysReportsAndPicksTheAssetOfTheChannel()
    {
        using var h = new Harness(h => h.Host.Channel = InstallChannel.Installed);
        var s = h.Vm.Settings;
        await s.CheckAsync(manual: true);
        Assert.Equal("No release found (or GitHub not reachable).", s.UpdateStatus);
        Assert.Contains($"{SelfUpdate.Repo} {SelfUpdate.SetupAssetName}", h.Host.Requests);

        h.Host.Releases[SelfUpdate.Repo] = FakeUpdateHost.Release("v2.0.0");
        await s.CheckAsync(manual: true);
        Assert.Equal("Up to date (latest published is v2.0.0).", s.UpdateStatus);

        h.Host.Releases[SelfUpdate.Repo] = FakeUpdateHost.Release("v2.1.0") with { Url = null };
        await s.CheckAsync(manual: true);
        Assert.Equal("v2.1.0 is out, but without WinGetStudio.exe: nothing to update with.", s.UpdateStatus);
        Assert.False(s.UpdateAppVisible);
    }

    // Una copia che winget possiede la aggiorna winget; una build di sviluppo git.
    [Theory]
    [InlineData(InstallChannel.WinGetPortable, "Installed with winget: update with 'winget upgrade FedeB2160.WinGetStudio'.")]
    [InlineData(InstallChannel.Source, "Updates apply to the published exe only; from source use git.")]
    public async Task ChannelsThatDoNotSelfUpdateStandDown(InstallChannel channel, string status)
    {
        using var h = new Harness(h => h.Host.Channel = channel);
        h.Host.Releases[SelfUpdate.Repo] = FakeUpdateHost.Release("v9.0.0");
        await h.Vm.Settings.CheckAsync(manual: true);
        Assert.Equal(status, h.Vm.Settings.UpdateStatus);
        Assert.DoesNotContain(h.Host.Requests, r => r.StartsWith(SelfUpdate.Repo));
        await h.Vm.Settings.UpdateAppAsync();
        Assert.Empty(h.Dialogs.Calls);
    }

    [Fact]
    public async Task UpdateAsksWithNoAsDefaultBeforeDownloading()
    {
        using var h = new Harness();
        h.Host.Releases[SelfUpdate.Repo] = FakeUpdateHost.Release("v9.0.0", sha256: null);
        await h.Vm.Settings.CheckAsync(manual: false);
        h.Host.Download = new DownloadResult(null, "should not download");
        await h.Vm.Settings.UpdateAppAsync();
        var c = Assert.Single(h.Dialogs.Calls);
        Assert.Equal((MessageBoxButton.YesNo, MessageBoxResult.No), (c.Button, c.Default));
        // Senza digest il canale portable si affida alla sola firma, e lo dice.
        Assert.Contains("checked against the WinGet Studio signature only", c.Text);
        Assert.DoesNotContain("Downloading", h.Log);
    }

    // Il setup chiede l'amministratore: senza digest non si scarica nemmeno.
    [Fact]
    public async Task InstalledChannelRefusesAReleaseWithoutChecksum()
    {
        using var h = new Harness(h => h.Host.Channel = InstallChannel.Installed);
        h.Host.Releases[SelfUpdate.Repo] = FakeUpdateHost.Release("v9.0.0", sha256: null, name: SelfUpdate.SetupAssetName);
        await h.Vm.Settings.CheckAsync(manual: false);
        await h.Vm.Settings.UpdateAppAsync();
        Assert.Empty(h.Dialogs.Calls);
        Assert.Contains("Update refused: v9.0.0 publishes no checksum for WinGetStudio_Setup.exe", h.Log);
    }

    // Firma che non torna: un dialogo dice dove prendere l'ultima versione a mano.
    [Fact]
    public async Task RejectedSignatureTellsWhereToUpdateByHand()
    {
        using var h = new Harness();
        h.Host.Releases[SelfUpdate.Repo] = FakeUpdateHost.Release("v9.0.0");
        await h.Vm.Settings.CheckAsync(manual: false);
        h.Dialogs.Answer = c => c.Button == MessageBoxButton.YesNo ? MessageBoxResult.Yes : MessageBoxResult.OK;
        h.Host.Download = new DownloadResult(null, "the download does not carry the WinGet Studio signature (0x800B0100), it was discarded", true);
        var closed = false;
        h.Vm.Settings.CloseRequested += () => closed = true;
        await h.Vm.Settings.UpdateAppAsync();
        Assert.Contains("Update FAILED: the download does not carry the WinGet Studio signature", h.Log);
        var warning = h.Dialogs.Calls[^1];
        Assert.Equal(("Update not installed", true), (warning.Title, warning.Links));
        Assert.Contains("https://github.com/FedeB2160/WinGetStudio/releases/latest", warning.Text);
        Assert.False(closed);
        Assert.False(h.State.IsBusy);
        Assert.Empty(h.Host.Applied);
    }

    [Fact]
    public async Task VerifiedUpdateIsAppliedAndTheWindowCloses()
    {
        using var h = new Harness();
        h.Host.Releases[SelfUpdate.Repo] = FakeUpdateHost.Release("v9.0.0");
        await h.Vm.Settings.CheckAsync(manual: false);
        h.Dialogs.Answer = _ => MessageBoxResult.Yes;
        var path = Path.GetTempFileName();
        try
        {
            h.Host.Download = new DownloadResult(new VerifiedFile(path, new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read)), null);
            var closed = false;
            h.Vm.Settings.CloseRequested += () => closed = true;
            await h.Vm.Settings.UpdateAppAsync();
            Assert.Equal([false], h.Host.Applied);
            Assert.True(closed);
            Assert.Contains("Updated to v9.0.0. Restarting...", h.Log);
            // Il handle e' stato chiuso dopo l'avvio.
            File.WriteAllText(path, "");
        }
        finally { File.Delete(path); }
    }

    // Mai mentre un winget e' in corso: finisce chiudendo la finestra (ADR 0003).
    [Fact]
    public async Task UpdateDoesNotStartOverWinGet()
    {
        using var h = new Harness();
        h.Host.Releases[SelfUpdate.Repo] = FakeUpdateHost.Release("v9.0.0");
        await h.Vm.Settings.CheckAsync(manual: false);
        h.State.SearchesInFlight = 1;
        await h.Vm.Settings.UpdateAppAsync();
        Assert.Empty(h.Dialogs.Calls);
    }

    // Dove lo Store aggiorna winget non si chiede nulla a GitHub.
    [Fact]
    public async Task StoreUpdatedWinGetMakesNoGitHubCall()
    {
        using var h = new Harness(h => h.Host.Store = true);
        h.Host.Releases[WinGetSetup.Repo] = FakeUpdateHost.Release("v1.30.0", name: WinGetSetup.BundleAsset);
        await h.Vm.Settings.CheckAsync(manual: true);
        Assert.True(h.Vm.Settings.WinGetStore);
        Assert.DoesNotContain(h.Host.Requests, r => r.StartsWith(WinGetSetup.Repo));
        Assert.False(h.Vm.Settings.UpdateWinGetVisible);
    }

    [Fact]
    public async Task NewerWinGetOffersTheButtonAndUpdatesBehindNo()
    {
        using var h = new Harness();
        h.Host.Releases[WinGetSetup.Repo] = FakeUpdateHost.Release("v1.30.0", name: WinGetSetup.BundleAsset);
        await h.Vm.Settings.CheckAsync(manual: false);
        var s = h.Vm.Settings;
        Assert.Equal((true, "Update to v1.30.0"), (s.UpdateWinGetVisible, s.UpdateWinGetText));
        Assert.Contains("winget v1.30.0 is available (winget 1.29.380 is installed).", h.Log);

        await s.UpdateWinGetCommand.ExecuteAsync(null);
        Assert.Equal(MessageBoxResult.No, Assert.Single(h.Dialogs.Calls).Default);
        Assert.Empty(h.Host.Installs);

        h.Dialogs.Answer = _ => MessageBoxResult.Yes;
        h.Host.WinGetVersion = "1.30.0";
        await s.UpdateWinGetCommand.ExecuteAsync(null);
        // Aggiornamento: niente registrazione, la lista Updates diventa vecchia.
        Assert.Equal([false], h.Host.Installs);
        Assert.Contains("winget is ready (v1.30.0).", h.Log);
        Assert.Equal("v1.30.0", s.WinGetVersionText);
        Assert.True(h.Vm.Updates.Stale);
        Assert.False(s.UpdateWinGetVisible);
        Assert.False(h.State.IsBusy);
    }

    // winget mancante all'avvio: No chiude l'app, come nella 1.x (ADR 0019).
    [Fact]
    public async Task MissingWinGetNoCloses()
    {
        using var h = new Harness(h => h.WinGetFound = false);
        var closed = false;
        h.Vm.Settings.CloseRequested += () => closed = true;
        await h.Vm.StartAsync();
        var c = Assert.Single(h.Dialogs.Calls);
        Assert.Equal(("winget not found", MessageBoxResult.No), (c.Title, c.Default));
        Assert.True(closed);
        Assert.Empty(h.Host.Installs);
        Assert.Empty(h.WinGet.Calls);
    }

    [Fact]
    public async Task MissingWinGetInstalledThenScans()
    {
        using var h = new Harness(h =>
        {
            h.WinGetFound = false;
            h.Dialogs.Answer = _ => MessageBoxResult.Yes;
            h.WinGet.Respond = a => FakeWinGet.Result(0, a[0] == "upgrade" ? FakeWinGet.Upgrades(new PackageRow("App A", "A.A", "1.0", "2.0")) : "");
        });
        await h.Vm.StartAsync();
        Assert.Equal([true], h.Host.Installs);
        Assert.Equal(@"C:\WindowsApps\winget.exe", h.State.Cli.WinGetPath);
        Assert.Single(h.Vm.Updates.Items);
        Assert.Contains("winget is ready (v1.29.380).", h.Log);
    }

    // Fallita: la finestra resta aperta col motivo nel log, e nessun comando parte.
    [Fact]
    public async Task MissingWinGetFailureKeepsTheWindowBusy()
    {
        using var h = new Harness(h =>
        {
            h.WinGetFound = false;
            h.Dialogs.Answer = c => c.Button == MessageBoxButton.YesNo ? MessageBoxResult.Yes : MessageBoxResult.OK;
            h.Host.InstallError = "the latest winget release on GitHub has no verifiable DesktopAppInstaller_Dependencies.zip";
        });
        await h.Vm.StartAsync();
        Assert.Contains("winget could not be installed: the latest winget release", h.Log);
        Assert.Equal(("winget not found", MessageBoxImage.Error), (h.Dialogs.Calls[^1].Title, h.Dialogs.Calls[^1].Image));
        Assert.True(h.State.IsBusy);
        Assert.Empty(h.WinGet.Calls);
    }

    // winget non sovrascrive un exe in esecuzione: WinGet Studio non sta nella propria lista.
    [Fact]
    public async Task WinGetStudioIsLeftOutOfUpdates()
    {
        using var h = new Harness(h => h.WinGet.Respond = a => FakeWinGet.Result(0, a[0] == "upgrade"
            ? FakeWinGet.Upgrades(new PackageRow("App A", "A.A", "1.0", "2.0"), new PackageRow("WinGet Studio", "FedeB2160.WinGetStudio", "1.12.0", "2.0.0"))
            : ""));
        await h.Vm.Updates.LoadAsync();
        Assert.Equal(["A.A"], h.Vm.Updates.Items.Select(i => i.Id));
        Assert.Contains("An update for WinGet Studio itself is available: update it from the Settings tab.", h.Log);
        Assert.Contains("Found 1 updates.", h.Log);
    }
}
