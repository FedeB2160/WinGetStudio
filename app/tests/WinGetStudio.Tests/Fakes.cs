using System.Windows;
using Microsoft.Win32;
using WinGetStudio.Core;
using WinGetStudio.ViewModels;

namespace WinGetStudio.Tests;

// winget finto: registra ogni chiamata (senza --version e --no-progress) e risponde con Respond.
// Before gira prima della risposta: serve a tenere un winget "in corso" o a guardare lo stato
// dell'app in quel momento. Running/MaxRunning contano le chiamate sovrapposte (ADR 0003).
internal sealed class FakeWinGet : IProcessRunner
{
    public readonly List<string[]> Calls = [];
    public Func<string[], ProcessResult> Respond = _ => Result(0, "");
    public Func<string[], Task>? Before;
    public TimeSpan? Tick;
    public int Running, MaxRunning;

    public static ProcessResult Result(int exit, string output) => new(exit, output, TimeSpan.Zero);

    public async Task<ProcessResult> RunAsync(string exePath, IReadOnlyList<string> arguments, Action<TimeSpan>? tick = null)
    {
        if (arguments is ["--version"]) return Result(0, "v1.29.380");
        MaxRunning = Math.Max(MaxRunning, Interlocked.Increment(ref Running));
        try
        {
            var a = arguments.Where(x => x != "--no-progress").ToArray();
            lock (Calls) Calls.Add(a);
            if (Before is not null) await Before(a);
            if (Tick is { } t) tick?.Invoke(t);
            return Respond(a);
        }
        finally { Interlocked.Decrement(ref Running); }
    }

    public int Count(params string[] prefix) => Calls.Count(c => c.Take(prefix.Length).SequenceEqual(prefix));

    // Tabella a larghezza fissa come la stampa winget: intestazione, trattini, righe.
    public static string Table(string[] headers, params string[][] rows)
    {
        var widths = headers.Select((h, i) => rows.Select(r => r[i].Length).Append(h.Length).Max() + 2).ToArray();
        string Line(string[] cells) => string.Concat(cells.Select((c, i) => c.PadRight(widths[i]))).TrimEnd();
        return string.Join("\r\n", [Line(headers), new string('-', widths.Sum()), .. rows.Select(Line)]) + "\r\n";
    }

    public static string Upgrades(params PackageRow[] rows) =>
        Table(["Name", "Id", "Version", "Available", "Source"], [.. rows.Select(r => new[] { r.Name, r.Id, r.Version, r.Available, "winget" })]);

    public static string Installed(params PackageRow[] rows) =>
        Table(["Name", "Id", "Version", "Source"], [.. rows.Select(r => new[] { r.Name, r.Id, r.Version, "winget" })]);

    public static string Search(params PackageRow[] rows) =>
        Table(["Name", "Id", "Version", "Match"], [.. rows.Select(r => new[] { r.Name, r.Id, r.Version, "" })]);

    public static string Pins(params string[] ids) =>
        Table(["Name", "Id", "Version", "Source", "Pin type"], [.. ids.Select(id => new[] { id, id, "1.0", "winget", "Blocking" })]);
}

// Dialoghi finti: registrano le chiamate e rispondono come chi preme Invio (il pulsante
// predefinito), salvo Answer diverso.
internal sealed class FakeDialogs : IDialogService
{
    public sealed record Call(string Text, string Title, MessageBoxButton Button, MessageBoxImage Image, MessageBoxResult Default, object? Content, bool Links);

    public readonly List<Call> Calls = [];
    public Func<Call, MessageBoxResult> Answer = c => c.Default == MessageBoxResult.None ? MessageBoxResult.OK : c.Default;
    public string? SaveFile, OpenFile;

    public MessageBoxResult Show(string text, string title = "WinGet Studio", MessageBoxButton button = MessageBoxButton.OK,
        MessageBoxImage image = MessageBoxImage.None, MessageBoxResult defaultResult = MessageBoxResult.None, object? content = null, bool links = false)
    {
        var call = new Call(text, title, button, image, defaultResult, content, links);
        Calls.Add(call);
        return Answer(call);
    }

    // Le pagine aperte, in ordine: "Settings" o "About <versione>".
    public readonly List<string> Pages = [];
    public void ShowSettings(SettingsViewModel settings) => Pages.Add("Settings");
    public void ShowAbout(string version) => Pages.Add($"About {version}");

    public string? PickSaveFile(string title, string filter, string fileName) => SaveFile;
    public string? PickOpenFile(string title, string filter) => OpenFile;
}

// GitHub, l'exe e winget finti. Releases per repo (null: nessuna release); Requests registra
// ogni chiamata a GitHub come "repo asset". Before gira prima della risposta di GitHub.
internal sealed class FakeUpdateHost : IUpdateHost
{
    public InstallChannel Channel { get; set; } = InstallChannel.Portable;
    public string? ExePath { get; set; } = @"C:\Tools\WinGetStudio.exe";
    public bool StartsWithWindows { get; set; }
    public string AppVersion { get; set; } = "2.0.0";
    public readonly Dictionary<string, Release?> Releases = [];
    public readonly List<string> Requests = [];
    public Func<Task>? Before;
    public string? WinGetVersion = "1.29.380";
    public bool Store;
    public DownloadResult Download = new(null, "no network");
    public readonly List<bool> Applied = [];
    public string? WinGetFoundAfterInstall = @"C:\WindowsApps\winget.exe";
    public string? InstallError;
    public readonly List<bool> Installs = [];

    public async Task<Release?> GetLatestReleaseAsync(string repo, string assetName)
    {
        lock (Requests) Requests.Add($"{repo} {assetName}");
        if (Before is not null) await Before();
        return Releases.GetValueOrDefault(repo);
    }

    public Task<DownloadResult> DownloadAsync(Release release) => Task.FromResult(Download);

    public string? Apply(VerifiedFile file, bool installed)
    {
        Applied.Add(installed);
        return null;
    }

    public Task<string?> GetWinGetVersionAsync() => Task.FromResult(WinGetVersion);
    public bool StoreUpdatesWinGet() => Store;
    public string? FindWinGet() => Installs.Count > 0 ? WinGetFoundAfterInstall : null;

    public Task<string?> InstallWinGetAsync(bool register, Action<string> log)
    {
        Installs.Add(register);
        return Task.FromResult(InstallError);
    }

    public static Release Release(string tag, string? sha256 = "AB", string name = "WinGetStudio.exe") =>
        new(tag, tag.TrimStart('v'), name, $"https://example.invalid/{name}", 2048, sha256);
}

// La finestra senza finestra: MainViewModel su winget e dialoghi finti, preferenze in una
// chiave di registro propria del test, cancellata alla fine.
internal sealed class Harness : IDisposable
{
    private readonly string _key = $@"Software\WinGetStudio.Tests\{Guid.NewGuid():N}";
    public readonly FakeWinGet WinGet = new();
    public readonly FakeDialogs Dialogs = new();
    public readonly FakeUpdateHost Host = new();
    public readonly Preferences Prefs;
    public readonly MainViewModel Vm;
    public bool WinGetFound = true;

    public Harness(Action<Harness>? setup = null)
    {
        Prefs = new Preferences(_key);
        setup?.Invoke(this);
        Vm = new MainViewModel(new WinGetCli("winget.exe", WinGet), Prefs, Dialogs, Host, WinGetFound);
    }

    public AppState State => Vm.State;
    public string Log => Vm.Log.Text;

    public void Dispose() => Registry.CurrentUser.DeleteSubKeyTree(_key, false);
}
