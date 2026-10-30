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
        window.Show();
    }

    // La preferenza Theme della 1.x: System | Light | Dark (ADR 0027).
    internal static ThemeMode Theme(string name) => name switch
    {
        "Light" => ThemeMode.Light,
        "Dark" => ThemeMode.Dark,
        _ => ThemeMode.System,
    };
}
