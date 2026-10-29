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

        var winget = WinGetCli.FindWinGet();
        var dialogs = new DialogService();
        var vm = new MainViewModel(new WinGetCli(winget ?? "winget.exe"), prefs, dialogs, winget is not null, SynchronizationContext.Current);
        var window = new MainWindow(vm);
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
