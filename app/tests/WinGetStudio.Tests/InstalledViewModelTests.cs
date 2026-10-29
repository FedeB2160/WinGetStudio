using System.IO;
using System.Text.Json.Nodes;
using System.Windows;
using WinGetStudio.Core;
using WinGetStudio.ViewModels;

namespace WinGetStudio.Tests;

// Scheda Installed (Tab.Installed.ps1 e App.Backup.ps1 della 1.x): filtro, disinstallazione con
// conferma (No predefinito) e nota sui nascosti, export, import con anteprima.
public class InstalledViewModelTests
{
    private static readonly PackageRow A = new("Alpha", "A.A", "1.0");
    private static readonly PackageRow B = new("Beta", "B.B", "2.0");

    private static Harness Create(List<PackageRow> installed, Func<string[], ProcessResult?>? other = null) =>
        new(h => h.WinGet.Respond = a => other?.Invoke(a) ?? (a switch
        {
            ["list", ..] => FakeWinGet.Result(0, FakeWinGet.Installed([.. installed])),
            ["pin", "list", ..] => FakeWinGet.Result(0, FakeWinGet.Pins("B.B")),
            ["uninstall", "--id", var id, ..] => Remove(installed, id),
            _ => FakeWinGet.Result(0, ""),
        }));

    private static ProcessResult Remove(List<PackageRow> installed, string id)
    {
        installed.RemoveAll(r => r.Id == id);
        return FakeWinGet.Result(0, "");
    }

    [Fact]
    public async Task OpeningTheTabLoadsTheListOnce()
    {
        using var h = Create([A, B]);
        h.Vm.SelectedTab = MainViewModel.InstalledTab;
        await h.State.LastFired;

        Assert.Equal(["A.A", "B.B"], h.Vm.Installed.Items.Select(i => i.Id));
        Assert.Equal([false, true], h.Vm.Installed.Items.Select(i => i.Pinned));
        Assert.Equal("2 installed", h.Vm.Installed.CountText);
        Assert.Contains("Found 2 installed packages.", h.Log);

        h.Vm.SelectedTab = MainViewModel.UpdatesTab;
        h.Vm.SelectedTab = MainViewModel.InstalledTab;
        Assert.Equal(1, h.WinGet.Count("list"));
    }

    [Fact]
    public async Task FilterMatchesNameOrIdAndTellsAboutHiddenSelections()
    {
        using var h = Create([A, B]);
        var vm = h.Vm.Installed;
        await vm.LoadAsync();
        vm.Items[0].Selected = true;
        vm.Items[1].Selected = true;

        vm.FilterText = "b.b";

        Assert.Equal([false, true], vm.Items.Select(vm.Matches));
        Assert.Equal("1 of 2 installed", vm.CountText);
        Assert.Equal("2 selected (1 hidden by the filter)", vm.InfoText);
    }

    [Fact]
    public async Task UninstallAsksFirstWithNoAsDefault()
    {
        using var h = Create([A, B]);
        var vm = h.Vm.Installed;
        await vm.LoadAsync();
        vm.Items[0].Selected = true;
        vm.Items[1].Selected = true;
        vm.FilterText = "Beta";

        await vm.UninstallAsync();

        var ask = Assert.Single(h.Dialogs.Calls);
        Assert.Equal(("Confirm uninstall", MessageBoxButton.YesNo, MessageBoxImage.Warning, MessageBoxResult.No),
            (ask.Title, ask.Button, ask.Image, ask.Default));
        Assert.Equal("Uninstall 2 packages?\n\n  - Alpha\n  - Beta\n\n1 of them are currently hidden by the filter.\n\nThis cannot be undone.", ask.Text);
        Assert.Equal(0, h.WinGet.Count("uninstall"));
        Assert.Contains("Uninstall cancelled.", h.Log);
    }

    [Fact]
    public async Task UninstallRunsThenReloadsAndMarksUpdatesStale()
    {
        using var h = Create([A, B]);
        var vm = h.Vm.Installed;
        await vm.LoadAsync();
        vm.Items[0].Selected = true;
        h.Dialogs.Answer = _ => MessageBoxResult.Yes;

        await vm.UninstallAsync();

        Assert.Equal(WinGetCommands.Uninstall(A), Assert.Single(h.WinGet.Calls, c => c[0] == "uninstall"));
        Assert.Equal(["B.B"], vm.Items.Select(i => i.Id));
        Assert.True(h.Vm.Updates.Stale);
        Assert.Contains("Uninstall complete: 1 ok.", h.Log);
    }

    [Fact]
    public async Task ExportWritesTheFileAndCountsThePackages()
    {
        var file = Path.Combine(Path.GetTempPath(), $"wgt-test-{Guid.NewGuid():N}.json");
        using var h = Create([], a =>
        {
            if (a[0] != "export") return null;
            File.WriteAllText(file, """{"Sources":[{"Packages":[{"PackageIdentifier":"A.A"},{"PackageIdentifier":"B.B"}]}]}""");
            return FakeWinGet.Result(0, "Installed package is not available from any source: X\r\n");
        });
        h.Dialogs.SaveFile = file;
        try
        {
            await h.Vm.Installed.ExportAsync();

            Assert.Equal(WinGetCommands.Export(file), Assert.Single(h.WinGet.Calls));
            Assert.Contains("Export done: 2 packages.", h.Log);
            Assert.Contains("  1 installed packages are in no source and were left out.", h.Log);
        }
        finally { File.Delete(file); }
    }

    [Fact]
    public async Task ImportPreviewDropsStoredArgumentsByDefault()
    {
        var file = Path.Combine(Path.GetTempPath(), $"wgt-test-{Guid.NewGuid():N}.json");
        File.WriteAllText(file, """
            {"Sources":[{"SourceDetails":{"Name":"winget"},"Packages":[
              {"PackageIdentifier":"A.A","Custom":"/evil"},
              {"PackageIdentifier":"B.B"}]}]}
            """);
        string? imported = null;
        using var h = Create([], a =>
        {
            if (a[0] == "import") imported = File.ReadAllText(a[2]);
            return null;
        });
        h.Dialogs.OpenFile = file;
        ImportPreviewViewModel? preview = null;
        h.Dialogs.Answer = c =>
        {
            preview = (ImportPreviewViewModel)c.Content!;
            preview.Rows[1].Selected = false;
            return MessageBoxResult.Yes;
        };
        try
        {
            await h.Vm.Installed.ImportAsync();

            var ask = Assert.Single(h.Dialogs.Calls);
            Assert.Equal(("Confirm import", MessageBoxResult.No), (ask.Title, ask.Default));
            Assert.Contains("1 package carries installer arguments saved in the file.", ask.Text);
            Assert.Equal("Keep the installer arguments saved for 1 package (--custom, --override)", preview!.KeepStoredText);
            var package = Assert.Single(JsonNode.Parse(imported!)!["Sources"]![0]!["Packages"]!.AsArray())!;
            Assert.Equal("""{"PackageIdentifier":"A.A"}""", package.ToJsonString());
            Assert.Contains("Importing 1 of the 2 packages in", h.Log);
            Assert.Contains("Installer arguments saved in", h.Log);
            // Dopo l'import: installati riletti, aggiornamenti vecchi.
            Assert.Equal(1, h.WinGet.Count("list"));
            Assert.True(h.Vm.Updates.Stale);
        }
        finally { File.Delete(file); }
    }

    [Fact]
    public async Task NotAPackageListIsRefused()
    {
        var file = Path.Combine(Path.GetTempPath(), $"wgt-test-{Guid.NewGuid():N}.json");
        File.WriteAllText(file, "[]");
        using var h = Create([]);
        h.Dialogs.OpenFile = file;
        try
        {
            await h.Vm.Installed.ImportAsync();
            var d = Assert.Single(h.Dialogs.Calls);
            Assert.Equal(("Cannot import", MessageBoxImage.Error), (d.Title, d.Image));
            Assert.Empty(h.WinGet.Calls);
        }
        finally { File.Delete(file); }
    }
}
