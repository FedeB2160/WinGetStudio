using System.Windows;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using Microsoft.Win32;
using WinGetStudio.Core;

namespace WinGetStudio.ViewModels;

// Scheda Settings (App.Theme.ps1, App.Update.ps1, WinGet.Setup.ps1 della 1.x): tema, striscia
// delle schede, versione e aggiornamento dell'app e di winget.
public sealed partial class SettingsViewModel : ObservableObject
{
    // Le voci sono ANCHE i valori salvati nel registro: nessuna tabella di conversione.
    public IReadOnlyList<string> Themes { get; } = ["Light", "Dark", "System"];
    public IReadOnlyList<string> TabStyles { get; } = ["Icon", "Text", "Icon + Text"];

    private readonly IUpdateHost _host;
    private Release? _pendingApp, _pendingWinGet;

    public SettingsViewModel(AppState state, IUpdateHost host)
    {
        State = state;
        _host = host;
        // Un valore fuori dai tre torna al default, compreso l'"Auto" delle 1.x fino alla 1.9.0.
        var theme = state.Prefs.GetString(Preferences.Theme, "System");
        _theme = Themes.Contains(theme) ? theme : "System";
        var style = state.Prefs.GetString(Preferences.TabHeaderStyle, "Icon + Text");
        _tabStyle = TabStyles.Contains(style) ? style : "Icon + Text";
        _checkAtStartup = state.Prefs.GetBool(Preferences.CheckAtStartup, true);
        VersionText = $"v{host.AppVersion}";
        UpdateAppText = UpdateWinGetText = UpdateStatus = WinGetStatus = WinGetVersionText = ThemeHint = "";
        RefreshThemeHint();
        state.PropertyChanged += (_, e) => { if (e.PropertyName == nameof(AppState.IsBusy)) NotifyCommands(); };
    }

    public AppState State { get; }

    // Applica il tema alla finestra (Application.ThemeMode); i test lo guardano da qui.
    public Action<string>? ApplyTheme { get; set; }

    // No alla conferma di winget mancante: la finestra si chiude, come nella 1.x. Anche dopo un
    // aggiornamento avviato: il setup o il nuovo exe prendono il posto di questa copia.
    public event Action? CloseRequested;
    // winget appena installato: la scansione parte ora.
    public event Func<Task>? WinGetInstalled;

    private string _theme;
    public string SelectedTheme
    {
        get => _theme;
        set
        {
            if (value is null || !SetProperty(ref _theme, value)) return;
            State.Prefs.Set(Preferences.Theme, value);
            ApplyTheme?.Invoke(value);
            RefreshThemeHint();
        }
    }

    // In System si dice quale dei due temi sta seguendo, altrimenti la scelta non spiega cosa si
    // vede a schermo.
    [ObservableProperty] public partial string ThemeHint { get; private set; }

    public void RefreshThemeHint() => ThemeHint = _theme == "System" ? $"following the system: {(SystemIsDark() ? "dark" : "light")}" : "";

    // AppsUseLightTheme = 0: scuro. Assente: chiaro.
    private static bool SystemIsDark()
    {
        try
        {
            using var k = Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize");
            return k?.GetValue("AppsUseLightTheme") is 0;
        }
        catch (Exception e) when (e is System.Security.SecurityException or System.IO.IOException or UnauthorizedAccessException) { return false; }
    }

    private string _tabStyle;
    public string SelectedTabStyle
    {
        get => _tabStyle;
        set
        {
            if (value is null || !SetProperty(ref _tabStyle, value)) return;
            State.Prefs.Set(Preferences.TabHeaderStyle, value);
            OnPropertyChanged(nameof(TabIconVisible));
            OnPropertyChanged(nameof(TabTextVisible));
        }
    }

    public bool TabIconVisible => _tabStyle != "Text";
    public bool TabTextVisible => _tabStyle != "Icon";

    // Il controllo all'avvio va in rete da solo: si dice e si puo' spegnere (ADR 0013).
    private bool _checkAtStartup;
    public bool CheckAtStartup
    {
        get => _checkAtStartup;
        set { if (SetProperty(ref _checkAtStartup, value)) State.Prefs.Set(Preferences.CheckAtStartup, value); }
    }

    public string VersionText { get; }
    [ObservableProperty] public partial string UpdateStatus { get; private set; }
    [ObservableProperty, NotifyCanExecuteChangedFor(nameof(CheckForUpdatesCommand))] public partial bool Checking { get; private set; }
    [ObservableProperty] public partial bool UpdateAppVisible { get; private set; }
    [ObservableProperty] public partial string UpdateAppText { get; private set; }
    [ObservableProperty] public partial string? UpdateAppToolTip { get; private set; }

    [ObservableProperty] public partial string WinGetVersionText { get; private set; }
    [ObservableProperty] public partial bool WinGetStore { get; private set; }
    [ObservableProperty] public partial string WinGetStatus { get; private set; }
    [ObservableProperty] public partial bool UpdateWinGetVisible { get; private set; }
    [ObservableProperty] public partial string UpdateWinGetText { get; private set; }
    [ObservableProperty] public partial string? UpdateWinGetToolTip { get; private set; }

    private bool CanCheck() => State.IsIdle && !Checking;
    private bool IsIdle() => State.IsIdle;

    private void NotifyCommands()
    {
        CheckForUpdatesCommand.NotifyCanExecuteChanged();
        UpdateAppCommand.NotifyCanExecuteChanged();
        UpdateWinGetCommand.NotifyCanExecuteChanged();
    }

    // "Check for updates": l'app e winget, e riferisce SEMPRE l'esito.
    [RelayCommand(CanExecute = nameof(CanCheck))]
    private Task CheckForUpdates() => CheckAsync(manual: true);

    // All'avvio (manual false) tace se non c'e' nulla da dire. NESSUNA guardia sullo stato
    // occupato: all'avvio la scansione lo alza nello stesso momento, e la guardia faceva tacere
    // il controllo sempre (ADR 0013). Si parla solo con GitHub; il pulsante resta spento finche'
    // la scansione non finisce.
    public Task CheckAsync(bool manual) => Task.WhenAll(CheckAppAsync(manual), CheckWinGetAsync(manual));

    private async Task CheckAppAsync(bool manual)
    {
        var channel = _host.Channel;
        if (channel == InstallChannel.Source)
        {
            if (manual) UpdateStatus = "Updates apply to the published exe only; from source use git.";
            return;
        }
        // winget possiede la copia: il pulsante non deve nemmeno comparire (ADR 0013).
        if (channel == InstallChannel.WinGetPortable)
        {
            if (manual) UpdateStatus = $"Installed with winget: update with 'winget upgrade {SelfUpdate.SelfPackageId}'.";
            return;
        }
        if (!manual && !CheckAtStartup) return;
        if (manual) { UpdateStatus = "Checking..."; Checking = true; }
        Release? rel;
        try { rel = await _host.GetLatestReleaseAsync(SelfUpdate.Repo, channel == InstallChannel.Installed ? SelfUpdate.SetupAssetName : SelfUpdate.PortableAssetName); }
        finally { Checking = false; }
        if (manual) UpdateStatus = "";
        var outcome = rel is null ? "No release found (or GitHub not reachable)."
            : !GitHubReleases.IsNewer(rel.Version, _host.AppVersion) ? $"Up to date (latest published is {rel.Tag})."
            : rel.Url is null ? $"{rel.Tag} is out, but without {rel.Name}: nothing to update with."
            : null;
        if (outcome is not null)
        {
            if (manual) UpdateStatus = outcome;
            return;
        }
        _pendingApp = rel;
        UpdateAppText = $"Update to {rel!.Tag}";
        UpdateAppToolTip = channel == InstallChannel.Installed
            ? $"Download the installer {rel.Name} ({rel.Size / 1024} KB): WinGet Studio closes, updates and reopens"
            : $"Download {rel.Name} ({rel.Size / 1024} KB) from GitHub and restart";
        UpdateAppVisible = true;
        // Il pulsante dice gia' quale versione c'e': una scritta accanto la ripeterebbe.
        UpdateStatus = "";
        State.Log.Write($"Version {rel.Tag} is available (you have v{_host.AppVersion}).");
    }

    // La versione locale si legge sempre; GitHub solo dove lo Store non aggiorna winget, e col
    // controllo all'avvio acceso o dal pulsante (ADR 0019).
    private async Task CheckWinGetAsync(bool manual)
    {
        if (manual) WinGetStatus = "Checking...";
        var version = await _host.GetWinGetVersionAsync();
        var store = _host.StoreUpdatesWinGet();
        WinGetVersionText = version is null ? "not found" : $"v{version}";
        WinGetStore = store;
        WinGetStatus = "";
        if (store || version is null || (!manual && !CheckAtStartup)) return;
        var rel = await _host.GetLatestReleaseAsync(WinGetSetup.Repo, WinGetSetup.BundleAsset);
        var outcome = rel is null ? "No release found (or GitHub not reachable)."
            : !GitHubReleases.IsNewer(rel.Version, version) ? $"Up to date (latest published is {rel.Tag})."
            : rel.Url is null ? $"{rel.Tag} is out, but without {rel.Name}: nothing to update with."
            : null;
        if (outcome is not null)
        {
            if (manual) WinGetStatus = outcome;
            return;
        }
        _pendingWinGet = rel;
        UpdateWinGetText = $"Update to {rel!.Tag}";
        UpdateWinGetToolTip = $"Download App Installer {rel.Tag} ({rel.Size / (1024 * 1024)} MB) and its dependencies from GitHub, and install them";
        UpdateWinGetVisible = true;
        State.Log.Write($"winget {rel.Tag} is available (winget {version} is installed).");
    }

    // Scarica, verifica (hash e firmatario, ADR 0022) e sostituisce. Finisce chiudendo la
    // finestra, quindi mai mentre un winget e' in corso (ADR 0003).
    [RelayCommand(CanExecute = nameof(IsIdle))]
    public async Task UpdateAppAsync()
    {
        var rel = _pendingApp;
        var channel = _host.Channel;
        if (rel is null || State.IsWinGetBusy || channel is InstallChannel.Source or InstallChannel.WinGetPortable) return;
        var installed = channel == InstallChannel.Installed;
        // Il setup chiede l'amministratore: senza digest non si scarica nemmeno.
        if (installed && rel.Sha256 is null)
        {
            State.Log.Write($"Update refused: {rel.Tag} publishes no checksum for {rel.Name}, and the installer would run as administrator.");
            return;
        }
        var answer = State.Dialogs.Show(
            (installed ? $"Download the {rel.Tag} installer and update WinGet Studio? It closes, updates and reopens.\n\n" : $"Download {rel.Tag} and restart WinGet Studio?\n\n") +
            $"{rel.Name} - {rel.Size / 1024} KB\nFrom: {rel.Url}\n\n" +
            (rel.Sha256 is not null ? "The download is checked against the SHA-256 published with the release, and must carry the WinGet Studio signature."
                : "WARNING: this release publishes no checksum, so the download is checked against the WinGet Studio signature only."),
            "Update WinGet Studio", MessageBoxButton.YesNo, MessageBoxImage.Question, MessageBoxResult.No);
        if (answer != MessageBoxResult.Yes || !State.TryBegin()) return;
        try
        {
            State.ProgressIndeterminate = true;
            State.Log.Write($"Downloading {rel.Name} ...");
            var d = await _host.DownloadAsync(rel);
            if (d.File is null)
            {
                State.Log.Write($"Update FAILED: {d.Error}.");
                // Chi resta qui (una release con un certificato nuovo) deve sapere che puo'
                // aggiornare a mano, e da dove: il log non lo legge nessuno.
                if (d.SignatureRejected)
                    State.Dialogs.Show("WinGet Studio could not confirm that this update was signed by its author, so it was not installed. " +
                        "This happens when a release is signed with a new certificate, or when the file was altered.\n\n" +
                        $"You can get the latest version by hand from https://github.com/{SelfUpdate.Repo}/releases/latest",
                        "Update not installed", MessageBoxButton.OK, MessageBoxImage.Warning, links: true);
                return;
            }
            using var file = d.File;
            State.Log.Write(rel.Sha256 is not null ? "Download verified (SHA-256 matches, signed by WinGet Studio)." : "Download verified (signed by WinGet Studio; no checksum to compare).");
            if (installed) State.Log.Write($"Running {rel.Name}; if the update fails, its log is WinGetStudio-update.log in %TEMP%.");
            if (_host.Apply(file, installed) is { } error)
            {
                State.Log.Write(installed ? $"Update FAILED: the installer did not start: {error}" : $"Update FAILED while replacing the executable: {error}");
                return;
            }
            if (!installed) State.Log.Write($"Updated to {rel.Tag}. Restarting...");
            CloseRequested?.Invoke();
        }
        finally { State.End(); }
    }

    [RelayCommand(CanExecute = nameof(IsIdle))]
    private Task UpdateWinGet() => InstallWinGetAsync(missing: false);

    // missing: all'avvio, winget non c'e'. Altrimenti il pulsante di aggiornamento. Prima la
    // conferma con No predefinito; poi lo stato occupato, perche' si sostituisce winget stesso.
    public async Task InstallWinGetAsync(bool missing)
    {
        var rel = _pendingWinGet;
        if (!missing && (rel is null || State.IsWinGetBusy)) return;
        var text = missing
            ? "WinGet Studio needs winget, which is not installed for this account.\n\n" +
              "Install it now? WinGet Studio first registers the App Installer that comes with Windows. " +
              "If there is none, it downloads App Installer and its dependencies from github.com/microsoft/winget-cli " +
              "(a few hundred MB) and checks them against the SHA-256 published with the release.\n\nNo closes WinGet Studio."
            : $"Download winget {rel!.Tag} from github.com/microsoft/winget-cli and install it?\n\n" +
              $"App Installer: {rel.Size / (1024 * 1024)} MB, plus its dependencies. The download is checked against the SHA-256 published with the release.\n\n" +
              "If winget is running somewhere else, the new version starts when it closes.";
        var answer = State.Dialogs.Show(text, missing ? "winget not found" : "Update winget", MessageBoxButton.YesNo, MessageBoxImage.Question, MessageBoxResult.No);
        if (answer != MessageBoxResult.Yes)
        {
            if (missing) CloseRequested?.Invoke();
            return;
        }
        if (!State.TryBegin()) return;
        State.ProgressIndeterminate = true;
        State.Log.Write(missing ? "Installing winget..." : $"Updating winget to {rel!.Tag}...");
        string? error;
        try { error = await _host.InstallWinGetAsync(missing, State.Log.Write); }
        catch (Exception e) { error = e.Message; }
        State.ProgressIndeterminate = false;
        var path = _host.FindWinGet();
        if (error is null && path is not null)
        {
            State.Cli.WinGetPath = path;
            State.End();
            var version = await _host.GetWinGetVersionAsync();
            State.Log.Write(rel is not null && version is not null && GitHubReleases.IsNewer(rel.Version, version)
                ? $"winget {rel.Tag} is installed: it starts when the App Installer processes still running close."
                : $"winget is ready ({(version is null ? "version unknown" : $"v{version}")}).");
            _pendingWinGet = null;
            UpdateWinGetVisible = false;
            // Installato: la scansione parte ora. Aggiornato: una riga App Installer in Updates
            // e' vecchia, e Update resta bloccato fino al Check.
            if (missing && WinGetInstalled is { } loaded) await loaded();
            else State.MarkUpdatesStale();
            await CheckWinGetAsync(false);
            return;
        }
        var why = error ?? "winget is still not found after the installation";
        if (!missing)
        {
            State.Log.Write($"winget update FAILED: {why}");
            State.End();
            return;
        }
        // La finestra resta aperta: il motivo sta nel log. Lo stato occupato resta alzato: senza
        // winget nessun comando deve partire.
        State.Log.Write($"winget could not be installed: {why}");
        State.Dialogs.Show($"winget could not be installed: {why}\n\n" +
            "The log below says what happened. Install App Installer from the Microsoft Store, or from " +
            "https://github.com/microsoft/winget-cli/releases, then start WinGet Studio again. If it is installed " +
            "already, check that the winget alias is on in Settings > Apps > Advanced app settings > App execution aliases.",
            "winget not found", MessageBoxButton.OK, MessageBoxImage.Error, links: true);
    }
}
