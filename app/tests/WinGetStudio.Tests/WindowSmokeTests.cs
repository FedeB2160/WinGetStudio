using System.Runtime.ExceptionServices;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Media;
using System.Windows.Threading;
using WinGetStudio.Core;
using WinGetStudio.ViewModels;

namespace WinGetStudio.Tests;

// La finestra vera, su winget finto: si apre col tema Fluent, carica gli aggiornamenti, cambia
// tema a caldo (ADR 0027); il dialogo ha No predefinito e in colore accento (ADR 0020).
// Un solo test: un processo ha una sola Application.
public class WindowSmokeTests
{
    // Le chiavi Fluent usate dallo XAML dell'app: una chiave sbagliata non da' errore, lascia
    // solo il colore di default.
    private static readonly string[] FluentKeys =
    [
        "AccentButtonStyle", "SystemFillColorSuccessBrush", "SystemFillColorCautionBrush", "SystemFillColorCriticalBrush",
        "TextFillColorSecondaryBrush", "AccentTextFillColorPrimaryBrush", "SmokeFillColorDefaultBrush",
        "CardBackgroundFillColorDefaultBrush", "CardStrokeColorDefaultBrush", "OverlayCornerRadius",
        "ControlStrongStrokeColorDefault", "TextFillColorPrimaryBrush", "SolidBackgroundFillColorTertiaryBrush",
        "AccentFillColorDefaultBrush", "TextOnAccentFillColorPrimaryBrush", "ControlStrongStrokeColorDisabledBrush",
        "SystemFillColorCautionBackgroundBrush", "ControlCornerRadius",
    ];

    [Fact]
    public void WindowOpensLoadsAndSwitchesTheme() => RunSta(() =>
    {
        var app = new Application { ShutdownMode = ShutdownMode.OnExplicitShutdown, ThemeMode = ThemeMode.Light };
        using var h = new Harness(h => h.WinGet.Respond = a => FakeWinGet.Result(0,
            a[0] == "upgrade" ? FakeWinGet.Upgrades(new PackageRow("App A", "A.A", "1.0", "2.0")) : ""));
        var w = new MainWindow(h.Vm)
        {
            ShowActivated = false, ShowInTaskbar = false, WindowStartupLocation = WindowStartupLocation.Manual, Left = -20000, Top = -20000,
        };
        w.Show();
        Pump(() => !h.State.IsBusy && h.Vm.Updates.Items.Count == 1);

        var tabs = (TabControl)w.FindName("TabMain");
        Assert.Equal(["Install", "Installed", "Updates"], tabs.Items.Cast<TabItem>().Select(t => (string)t.Header));
        Assert.Equal(MainViewModel.UpdatesTab, tabs.SelectedIndex);
        // Seleziona tutto e' la spunta nell'intestazione della griglia (ADR 0028).
        var headers = FindChild<DataGridColumnHeadersPresenter>((DataGrid)w.FindName("GridUpdates"));
        Assert.NotNull(headers);
        var all = FindChild<CheckBox>(headers);
        Assert.NotNull(all);
        Assert.True(all.IsEnabled);
        all.IsChecked = true;
        Assert.True(h.Vm.Updates.Items[0].Selected);
        // Titoli delle colonne al centro (ADR 0028).
        var name = FindAll<DataGridColumnHeader>(headers).First(c => c.Content as string == "Name");
        Assert.Equal(HorizontalAlignment.Center, name.HorizontalContentAlignment);
        // Una colonna allargata oltre la griglia (doppio clic sul bordo): dopo Refit tutte le
        // colonne, Result compresa, stanno dentro e le fisse non cambiano larghezza.
        var grid = (DataGrid)w.FindName("GridUpdates");
        grid.Columns[2].Width = new DataGridLength(3000);
        Pump(() => true);
        MainWindow.Refit(grid);
        Pump(() => true);
        Assert.True(grid.Columns.Sum(c => c.ActualWidth) <= grid.ActualWidth, $"{grid.Columns.Sum(c => c.ActualWidth)} > {grid.ActualWidth}");
        Assert.Equal(80, grid.Columns[^1].ActualWidth);
        Assert.False(grid.CanUserReorderColumns);
        all.IsChecked = false;
        // Settings e About sono finestre a parte (ADR 0028): si aprono, col logo, e si chiudono.
        var about = new AboutWindow("2.0.0") { Owner = w, ShowActivated = false };
        about.Show();
        Pump(() => true);
        Assert.True(about.FindName("TxtVersion") is TextBlock { Text: "Version 2.0.0" });
        Assert.NotNull(FindChild<Image>(about)?.Source);
        about.Close();
        var settings = new SettingsWindow { DataContext = h.Vm.Settings, Owner = w, ShowActivated = false };
        settings.Show();
        Pump(() => true);
        Assert.Equal(h.Vm.Settings.Themes.Count, FindChild<ComboBox>(settings)!.Items.Count);
        h.Vm.Settings.ApplyTheme = name => app.ThemeMode = App.Theme(name);
        Assert.Contains("Found 1 updates.", ((TextBox)w.FindName("TxtLog")).Text);
        foreach (var key in FluentKeys) Assert.True(w.TryFindResource(key) is not null, key);

        var light = ((SolidColorBrush)w.FindResource("TextFillColorPrimaryBrush")).Color;
        h.Vm.Settings.SelectedTheme = "Dark";
        Pump(() => true);
        Assert.NotEqual(light, ((SolidColorBrush)w.FindResource("TextFillColorPrimaryBrush")).Color);

        var dialog = new AppDialog("Uninstall 1 package?", "Confirm uninstall", MessageBoxButton.YesNo,
            MessageBoxImage.Warning, MessageBoxResult.No, null, links: false);
        var buttons = ((StackPanel)dialog.FindName("DlgButtons")).Children.Cast<Button>().ToList();
        Assert.Equal(["Yes", "No"], buttons.Select(b => (string)b.Content));
        Assert.True(buttons[1].IsDefault && buttons[1].IsCancel && !buttons[0].IsDefault);
        Assert.Same(w.FindResource("AccentButtonStyle"), buttons[1].Style);
        dialog.Close();

        // I dettagli (testo coi link): il font della finestra e non il serif del FlowDocument,
        // piu' piccolo e piu' largo del resto.
        var details = new AppDialog("Name: App A\nHomepage: https://example.com", "App A - details", MessageBoxButton.OK,
            MessageBoxImage.None, MessageBoxResult.None, null, links: true);
        var rich = ((StackPanel)details.FindName("DlgBody")).Children.OfType<RichTextBox>().First();
        Assert.Equal(details.FontFamily, rich.Document.FontFamily);
        Assert.Equal((12d, 680d), (rich.Document.FontSize, rich.Width));
        details.Close();

        settings.Close();
        w.Close();
        app.Shutdown();
    });

    // Menu dei pin: ogni voce solo se ha qualcosa da fare sulle righe evidenziate.
    [Fact]
    public void PinMenuOffersOnlyWhatChangesSomething()
    {
        PackageItem Row(bool pinned) => new(new PackageRow("App", "A.A", "1.0")) { Pinned = pinned };
        Assert.Equal((true, false), MainWindow.PinChoices([Row(false)]));
        Assert.Equal((false, true), MainWindow.PinChoices([Row(true), Row(true)]));
        Assert.Equal((true, true), MainWindow.PinChoices([Row(true), Row(false)]));
        Assert.Equal((false, false), MainWindow.PinChoices([]));
    }

    private static IEnumerable<T> FindAll<T>(DependencyObject parent) where T : DependencyObject
    {
        for (var i = 0; i < VisualTreeHelper.GetChildrenCount(parent); i++)
        {
            var c = VisualTreeHelper.GetChild(parent, i);
            if (c is T t) yield return t;
            foreach (var d in FindAll<T>(c)) yield return d;
        }
    }

    private static T? FindChild<T>(DependencyObject parent) where T : DependencyObject
    {
        for (var i = 0; i < VisualTreeHelper.GetChildrenCount(parent); i++)
        {
            var c = VisualTreeHelper.GetChild(parent, i);
            if ((c as T ?? FindChild<T>(c)) is { } found) return found;
        }
        return null;
    }

    // Elabora la coda del dispatcher finche' la condizione vale (o 10 s).
    private static void Pump(Func<bool> until)
    {
        var deadline = DateTime.UtcNow.AddSeconds(10);
        do
        {
            var frame = new DispatcherFrame();
            Dispatcher.CurrentDispatcher.BeginInvoke(DispatcherPriority.ContextIdle, () => frame.Continue = false);
            Dispatcher.PushFrame(frame);
        }
        while (!until() && DateTime.UtcNow < deadline);
    }

    private static void RunSta(Action body)
    {
        ExceptionDispatchInfo? error = null;
        var t = new Thread(() =>
        {
            try { body(); }
            catch (Exception e) { error = ExceptionDispatchInfo.Capture(e); }
        });
        t.SetApartmentState(ApartmentState.STA);
        t.Start();
        t.Join();
        error?.Throw();
    }
}
