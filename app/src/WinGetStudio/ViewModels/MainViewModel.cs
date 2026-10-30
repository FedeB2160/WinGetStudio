using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using WinGetStudio.Core;

namespace WinGetStudio.ViewModels;

// La finestra: cinque schede sopra lo stato condiviso, log in fondo.
public sealed partial class MainViewModel : ObservableObject
{
    // Indici delle schede, nell'ordine della 1.x: Settings e About in fondo.
    public const int InstallTab = 0, InstalledTab = 1, UpdatesTab = 2, SettingsTab = 3, AboutTab = 4;

    private readonly bool _wingetFound;

    // ui: il contesto della UI, per le righe di log che arrivano da altri thread. updates: GitHub,
    // l'exe e winget stesso; i test ne passano uno finto.
    public MainViewModel(WinGetCli cli, Preferences prefs, IDialogService dialogs, IUpdateHost updates, bool wingetFound = true, SynchronizationContext? ui = null)
    {
        _wingetFound = wingetFound;
        Log = new LogViewModel(ui);
        State = new AppState(cli, Log, dialogs, prefs);
        Updates = new UpdatesViewModel(State);
        Install = new InstallViewModel(State);
        Installed = new InstalledViewModel(State);
        Settings = new SettingsViewModel(State, updates);
        Settings.WinGetInstalled += () => Updates.LoadAsync();
        // Si apre su Updates: la scansione all'avvio popola proprio questa.
        SelectedTab = UpdatesTab;
    }

    public LogViewModel Log { get; }
    public AppState State { get; }
    public UpdatesViewModel Updates { get; }
    public InstallViewModel Install { get; }
    public InstalledViewModel Installed { get; }
    public SettingsViewModel Settings { get; }

    [ObservableProperty] public partial int SelectedTab { get; set; }

    // Updates vecchia si rilegge appena si apre; Installed si carica alla prima apertura.
    partial void OnSelectedTabChanged(int value)
    {
        if (value == UpdatesTab && Updates.Stale) State.Fire(() => Updates.LoadAsync());
        else if (value == InstalledTab && !Installed.Loaded) State.Fire(() => Installed.LoadAsync());
        else if (value == SettingsTab) Settings.RefreshThemeHint();
    }

    // Al primo rendering. Senza winget si propone di installarlo (ADR 0019); con winget la
    // scansione e i controlli degli aggiornamenti partono insieme: solo la scansione usa winget
    // prima che i controlli chiedano la sua versione, e il lock li mette in fila.
    public Task StartAsync() => _wingetFound
        ? Task.WhenAll(Updates.LoadAsync(), Settings.CheckAsync(manual: false))
        : Settings.InstallWinGetAsync(missing: true);

    // F5: la scheda che si sta guardando. Le letture rifiutano gia' di partire sopra un winget.
    public Task RefreshCurrentAsync() => SelectedTab switch
    {
        UpdatesTab => Updates.LoadAsync(),
        InstalledTab => Installed.LoadAsync(),
        _ => Task.CompletedTask,
    };

    [RelayCommand]
    private void SaveLog()
    {
        var path = State.Dialogs.PickSaveFile("Save the log", "Text file (*.txt)|*.txt|All files (*.*)|*.*", $"wingetstudio-log-{DateTime.Now:yyyy-MM-dd-HHmm}.txt");
        if (path is not null) Log.SaveTo(path);
    }

    [RelayCommand]
    private void ClearLog() => Log.Clear();
}
