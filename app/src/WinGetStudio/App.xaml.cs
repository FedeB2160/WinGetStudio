using System.Windows;
using WinGetStudio.Core;
using WinGetStudio.ViewModels;

namespace WinGetStudio;

public partial class App : Application
{
    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);
        var prefs = new Preferences();
        ThemeMode = Theme(prefs.GetString(Preferences.Theme, "System"));
        // Residui dei winget precedenti tenuti aperti da un installer.
        TempFiles.Clear();
        // Il .old e il download lasciati dall'aggiornamento precedente (ADR 0013).
        SelfUpdate.ClearLeftovers(UpdateHost.ExePath);

        var winget = WinGetCli.FindWinGet();
        var dialogs = new DialogService();
        var cli = new WinGetCli(winget ?? "winget.exe");
        var vm = new MainViewModel(cli, prefs, dialogs, new UpdateHost(cli), winget is not null, SynchronizationContext.Current);
        // Always start as administrator (ADR 0024): la copia elevata prende il posto di questa.
        if (vm.Settings.ElevateAtStartup(automatic: e.Args.Contains(Autostart.StartupArgument)))
        {
            Shutdown();
            return;
        }
        // A caldo: ThemeMode ridipinge la finestra senza ricrearla (ADR 0027).
        vm.Settings.ApplyTheme = name => ThemeMode = Theme(name);
        var window = new MainWindow(vm);
        // Prima Settings, se e' aperta: la richiesta puo' venire da li'.
        vm.Settings.CloseRequested += () =>
        {
            vm.BeginExit();
            foreach (var owned in window.OwnedWindows.OfType<Window>().ToList()) owned.Close();
            window.Close();
        };
        dialogs.Owner = window;
        // Un errore imprevisto finisce nel log invece di chiudere l'app a meta' di una coda.
        DispatcherUnhandledException += (_, args) =>
        {
            vm.Log.Write($"ERROR: {args.Exception.Message}");
            args.Handled = true;
        };

        // Area di notifica (ADR 0030). Close to tray: la X nasconde; Exit chiude davvero.
        _tray = new TrayIcon(vm, window, () =>
        {
            vm.BeginExit();
            Shutdown();
        });
        window.Closing += (_, args) =>
        {
            if (!vm.HidesOnClose) return;
            args.Cancel = true;
            window.Hide();
        };
        // La fine della sessione di Windows non deve trovare la X che nasconde.
        SessionEnding += (_, _) => vm.BeginExit();
        // Una finestra dell'app in primo piano: le notifiche tacciono.
        // Visibile E attiva: una finestra nascosta col fuoco non mostra nulla all'utente.
        void Active() => vm.Tray.WindowActive = Windows.OfType<Window>().Any(w => w.IsVisible && w.IsActive);
        Activated += (_, _) => Active();
        Deactivated += (_, _) => Active();
        window.IsVisibleChanged += (_, _) => Active();

        // Da Start with Windows parte nell'area di notifica: la scansione gira lo stesso.
        if (vm.StartsHidden(e.Args)) vm.State.Fire(vm.StartAsync);
        else window.Show();
    }

    private TrayIcon? _tray;

    // Senza, l'icona resta nell'area di notifica finche' il mouse non ci passa sopra.
    protected override void OnExit(ExitEventArgs e)
    {
        _tray?.Dispose();
        base.OnExit(e);
    }

    // La preferenza Theme della 1.x: System | Light | Dark (ADR 0027).
    internal static ThemeMode Theme(string name) => name switch
    {
        "Light" => ThemeMode.Light,
        "Dark" => ThemeMode.Dark,
        _ => ThemeMode.System,
    };
}
