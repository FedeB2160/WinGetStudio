using System.IO;
using WinGetStudio.Core;
using WinGetStudio.ViewModels;

namespace WinGetStudio;

// Il vero IUpdateHost: GitHub, l'exe in esecuzione, winget.
public sealed class UpdateHost(WinGetCli cli) : IUpdateHost
{
    // Il file in esecuzione, solo se single-file (pubblicato): una build di sviluppo ha la dll
    // accanto e non si aggiorna da sola.
    public static string? ExePath => string.IsNullOrEmpty(typeof(App).Assembly.Location) ? Environment.ProcessPath : null;

    public InstallChannel Channel { get; } = SelfUpdate.Channel(ExePath, SelfUpdate.InstalledLocation());

    string? IUpdateHost.ExePath => ExePath;

    public bool StartsWithWindows
    {
        get => ExePath is { } exe && Autostart.IsOn(exe);
        set { if (ExePath is { } exe) Autostart.Set(value, exe); }
    }
    public string AppVersion { get; } = typeof(App).Assembly.GetName().Version?.ToString(3) ?? "0.0.0";

    public Task<Release?> GetLatestReleaseAsync(string repo, string assetName) => GitHubReleases.GetLatestAsync(repo, assetName);

    public Task<DownloadResult> DownloadAsync(Release release) => SelfUpdate.DownloadVerifiedAsync(release);

    public string? Apply(VerifiedFile file, bool installed) =>
        installed ? SelfUpdate.StartSetup(file, SetupLog) : SelfUpdate.ReplaceAndRestart(file, ExePath!);

    // Il log di Inno resta nel %TEMP% dell'utente.
    public static string SetupLog => Path.Combine(Path.GetTempPath(), "WinGetStudio-update.log");

    public Task<string?> GetWinGetVersionAsync() => cli.GetVersionAsync();
    public bool StoreUpdatesWinGet() => WinGetSetup.StoreUpdatesWinGet();
    public string? FindWinGet() => WinGetCli.FindWinGet();
    public Task<string?> InstallWinGetAsync(bool register, Action<string> log) => WinGetSetup.InstallAsync(register, log);
}
