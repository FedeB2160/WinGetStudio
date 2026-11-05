using System.Windows;
using WinGetStudio.Core;
using WinGetStudio.ViewModels;

namespace WinGetStudio.Tests;

// Scheda Install (Tab.Install.ps1 della 1.x): ricerca mentre si scrive (>= 3 caratteri, mai lo
// Store), Invio con lo Store se spuntato, Install for, sorgente della riga, dettagli con Install.
public class InstallViewModelTests
{
    private static readonly PackageRow Zip = new("7-Zip", "7zip.7zip", "24.09");
    private static readonly PackageRow Store = new("7-Zip Store", "9NBLGGH4S6S1", "Unknown");

    private static Harness Create() => new(h => h.WinGet.Respond = a => a switch
    {
        ["search", _, _, _, _, "winget", ..] => FakeWinGet.Result(0, FakeWinGet.Search(Zip)),
        ["search", _, _, _, _, "msstore", ..] => FakeWinGet.Result(0, FakeWinGet.Search(Store)),
        _ => FakeWinGet.Result(0, ""),
    });

    [Fact]
    public async Task TypingSearchesWingetOnlyAfterThreeCharacters()
    {
        using var h = Create();
        var vm = h.Vm.Install;
        vm.IncludeStore = true;

        vm.SearchText = "7z";
        Assert.Equal("Type a package name to search the winget catalog.", vm.Message);
        Assert.Empty(h.WinGet.Calls);

        vm.SearchText = "7zi";
        vm.SearchText = "7zip";   // la pausa riparte a ogni tasto: una sola ricerca
        await vm.TypeaheadTask;

        var call = Assert.Single(h.WinGet.Calls);
        Assert.Equal(["search", "7zip", "--count", "25", "--source", "winget"], call.Take(6));
        Assert.Equal(["7zip.7zip"], vm.Items.Select(i => i.Id));
        Assert.Equal("winget", vm.Items[0].Source);
        Assert.Equal("1 result - tick the ones to install, or double click a row for details", vm.InfoText);
    }

    [Fact]
    public async Task EnterAlsoSearchesTheStoreWhenTicked()
    {
        using var h = Create();
        var vm = h.Vm.Install;
        vm.IncludeStore = true;
        vm.SearchText = "7zip";

        await vm.SearchNowAsync();
        await vm.TypeaheadTask;   // annullata da Invio

        Assert.Equal(["winget", "msstore"], h.WinGet.Calls.Select(c => c[5]));
        Assert.Equal(["7zip.7zip", "9NBLGGH4S6S1"], vm.Items.Select(i => i.Id));
        Assert.Equal(["winget", "msstore"], vm.Items.Select(i => i.Source));
        Assert.True(h.Prefs.GetBool(Preferences.IncludeStore, false));
    }

    [Fact]
    public async Task ShortQueryAndNoMatchHaveTheirMessages()
    {
        using var h = new Harness(h => h.WinGet.Respond = _ => FakeWinGet.Result(ExitCodes.NoApplicationsFound, "No package found matching input criteria."));
        var vm = h.Vm.Install;

        vm.SearchText = "ab";
        await vm.SearchNowAsync();
        Assert.Equal("Type at least 3 characters.", vm.Message);

        vm.SearchText = "nothing";
        await vm.SearchNowAsync();
        Assert.Equal("No package matches 'nothing'.", vm.Message);
        Assert.Empty(vm.Items);
    }

    [Fact]
    public async Task AnOutdatedResultIsDropped()
    {
        using var h = Create();
        var vm = h.Vm.Install;
        var release = new TaskCompletionSource();
        h.WinGet.Before = _ => release.Task;
        vm.SearchText = "7zip";
        var search = vm.SearchNowAsync();

        vm.SearchText = "7z";   // l'utente ha continuato a scrivere
        release.SetResult();
        await search;

        Assert.Empty(vm.Items);
        Assert.Equal("Type a package name to search the winget catalog.", vm.Message);
    }

    [Fact]
    public async Task InstallPassesSourceAndScopeAndMarksTheOtherListsStale()
    {
        using var h = Create();
        var vm = h.Vm.Install;
        vm.SearchText = "7zip";
        await vm.SearchNowAsync();

        vm.SelectedScope = vm.Scopes[1];
        Assert.Equal(("Current user", "Install for the current user only (--scope user)"), (vm.SelectedScope.Label, vm.SelectedScope.ToolTip));
        Assert.Equal("User", h.Prefs.GetString(Preferences.InstallScope, ""));
        vm.Items[0].Selected = true;
        Assert.Equal("1 selected", vm.InfoText);
        await vm.InstallAsync();

        var install = Assert.Single(h.WinGet.Calls, c => c[0] == "install");
        Assert.Equal(WinGetCommands.Install(vm.Items[0].Row, InstallScope.User), install);
        Assert.Equal(RowStatus.Ok, vm.Items[0].Status);
        Assert.True(h.Vm.Updates.Stale);
        Assert.False(h.Vm.Installed.Loaded);
    }

    // Doppio clic (e menu): i dettagli, con Install fra i pulsanti e Close predefinito. Invio
    // chiude; Install installa quella riga, con la sua sorgente, senza passare dalle spunte.
    [Fact]
    public async Task DetailsOfferInstallForThatRowOnly()
    {
        using var h = Create();
        var vm = h.Vm.Install;
        vm.SearchText = "7zip";
        vm.IncludeStore = true;
        await vm.SearchNowAsync();

        await vm.DetailsAsync(vm.Items[1]);
        var details = Assert.Single(h.Dialogs.Calls);
        Assert.Equal(("7-Zip Store - details", MessageBoxButton.YesNo, MessageBoxResult.No, ("Install", "Close")),
            (details.Title, details.Button, details.Default, details.Verbs));
        Assert.Equal(0, h.WinGet.Count("install"));

        h.Dialogs.Answer = _ => MessageBoxResult.Yes;
        await vm.DetailsAsync(vm.Items[1]);

        var install = Assert.Single(h.WinGet.Calls, c => c[0] == "install");
        Assert.Equal(["install", "--id", "9NBLGGH4S6S1", "-e", "--source", "msstore"], install.Take(6));
        Assert.False(vm.Items[1].Selected);
    }

    [Fact]
    public void ScopeIsReadFromThePreferences()
    {
        using var h = new Harness(h => h.Prefs.Set(Preferences.InstallScope, "Machine"));
        var vm = h.Vm.Install;
        Assert.Equal(["Auto", "Current user", "All users"], vm.Scopes.Select(s => s.Label));
        Assert.Equal(InstallScope.Machine, vm.SelectedScope.Value);
        vm.SelectedScope = vm.Scopes[0];
        Assert.Equal("Auto", h.Prefs.GetString(Preferences.InstallScope, ""));
    }
}
