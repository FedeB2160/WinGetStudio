using System.Runtime.ExceptionServices;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Documents;
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
        "SystemFillColorCautionBackgroundBrush", "ControlCornerRadius", "FocusStrokeColorOuterBrush",
    ];

    [Fact]
    public void WindowOpensLoadsAndSwitchesTheme() => RunSta(() =>
    {
        var app = new Application { ShutdownMode = ShutdownMode.OnExplicitShutdown, ThemeMode = ThemeMode.Light };
        // Piu' righe di quante ne stanno: la barra di scorrimento serve.
        var rows = Enumerable.Range(0, 30).Select(i => new PackageRow(i == 0 ? "App A" : $"App {i}", i == 0 ? "A.A" : $"A.{i}", "1.0", "2.0")).ToArray();
        using var h = new Harness(h => h.WinGet.Respond = a => FakeWinGet.Result(0,
            a[0] == "upgrade" ? FakeWinGet.Upgrades(rows) : ""));
        var w = new MainWindow(h.Vm)
        {
            ShowActivated = false, ShowInTaskbar = false, WindowStartupLocation = WindowStartupLocation.Manual, Left = -20000, Top = -20000,
        };
        w.Show();
        Pump(() => !h.State.IsBusy && h.Vm.Updates.Items.Count == rows.Length);

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
        // Titoli delle colonne a sinistra, dove comincia il testo delle celle; al centro solo le
        // colonne fisse (ADR 0028, punto 17). La spunta di Seleziona tutto resta sopra quelle delle
        // righe (i 7 px di SelectAllHeader).
        var updatesGrid = (DataGrid)w.FindName("GridUpdates");
        var firstRow = FindChild<DataGridRow>(updatesGrid)!;
        double Left(FrameworkElement e) => e.TranslatePoint(new Point(), updatesGrid).X;
        double Middle(FrameworkElement e) => Left(e) + e.ActualWidth / 2;
        var name = FindAll<DataGridColumnHeader>(headers).First(c => c.Content as string == "Package Name");
        Assert.Equal(HorizontalAlignment.Left, name.HorizontalContentAlignment);
        var nameCell = FindAll<DataGridCell>(firstRow).First(c => c.Column == name.Column);
        Assert.Equal(Left(FindChild<TextBlock>(nameCell)!), Left(FindChild<TextBlock>(name)!), 1.0);
        Assert.Equal(HorizontalAlignment.Center, FindAll<DataGridColumnHeader>(headers).First(c => c.Content as string == "Result").HorizontalContentAlignment);
        // 2 px: lo spazio che l'intestazione Fluent tiene per la freccia di ordinamento dipende dal
        // font dei glifi, e sul runner della CI (Windows Server) la spunta finiva 1,3 px piu' in la'.
        Assert.Equal(Middle(FindChild<CheckBox>(firstRow)!), Middle(all), 2.0);
        // Una colonna allargata oltre la griglia (doppio clic sul bordo): dopo Refit tutte le
        // colonne, Result compresa, stanno dentro e le fisse non cambiano larghezza. Le altre
        // elastiche non restano schiacciate ai 20 px minimi del DataGrid: tengono almeno il titolo.
        var grid = (DataGrid)w.FindName("GridUpdates");
        grid.Columns[2].Width = new DataGridLength(3000);
        Pump(() => true);
        MainWindow.Refit(grid);
        Pump(() => true);
        Assert.True(grid.Columns.Sum(c => c.ActualWidth) <= grid.ActualWidth, $"{grid.Columns.Sum(c => c.ActualWidth)} > {grid.ActualWidth}");
        foreach (var c in grid.Columns.Skip(3).Where(c => c.CanUserResize))
            Assert.True(c.ActualWidth >= 60, $"{c.Header}: {c.ActualWidth}");
        Assert.Equal(56, grid.Columns[^1].ActualWidth);
        // La barra di scorrimento sta fuori dalla griglia: quella del DataGrid e' nascosta, la sua
        // compare con piu' righe di quante ne stanno e segue lo scorrimento.
        var bar = (ScrollBar)w.FindName("BarUpdates");
        var viewer = FindAll<ScrollViewer>(grid).First();
        Assert.Equal(ScrollBarVisibility.Hidden, viewer.VerticalScrollBarVisibility);
        Assert.Equal(Visibility.Visible, bar.Visibility);
        viewer.ScrollToVerticalOffset(5);
        Pump(() => true);
        Assert.Equal(5, bar.Value);
        // Bordi opachi (sovrapposti non si sommano); linguetta attiva a 2 px, le altre a 1.
        Assert.Equal(255, ((SolidColorBrush)w.FindResource("AreaStrokeBrush")).Color.A);
        Assert.Equal(255, ((SolidColorBrush)w.FindResource("TabStrokeInactiveBrush")).Color.A);
        Assert.Equal([2d, 1d, 1d], tabs.Items.Cast<TabItem>().OrderByDescending(t => t.IsSelected)
            .Select(t => ((Border)t.Template.FindName("Border", t)).BorderThickness.Top));
        Assert.False(grid.CanUserReorderColumns);
        // Accessibilita' (ADR 0028, punto 16): nome delle linguette inattive in testo secondario,
        // cornice di fuoco sulla riga (solo da tastiera), nome del badge, testo che si annuncia.
        var secondary = ((SolidColorBrush)w.FindResource("TextFillColorSecondaryBrush")).Color;
        foreach (var t in tabs.Items.Cast<TabItem>().Where(t => !t.IsSelected))
            Assert.Equal(secondary, ((SolidColorBrush)FindAll<TextBlock>(t).First(b => b.Text == (string)t.Header).Foreground).Color);
        // Le celle non hanno cornice; quella della riga c'e' solo da tastiera, una per tutta la riga
        // sia dalla spunta sia da Result, disegnata dentro la riga e quindi dentro la griglia.
        // La prima riga visibile: la griglia e' scorsa qui sopra, la riga 0 non c'e' piu'.
        var row = FindChild<DataGridRow>(grid)!;
        var cells = FindAll<DataGridCell>(row).ToList();
        Assert.All(cells, c => Assert.Null(c.FocusVisualStyle));
        // Ne' la spunta della riga: con la sua, le cornici erano due. Seleziona tutto la tiene.
        Assert.Null(FindChild<CheckBox>(row)!.FocusVisualStyle);
        Assert.NotNull(all.FocusVisualStyle);
        var layer = AdornerLayer.GetAdornerLayer(row)!;
        w.ShowRowFocus(cells[0], keyboard: false);
        Assert.Null(layer.GetAdorners(row));
        var inside = new Rect(1, 1, grid.ActualWidth - 2, grid.ActualHeight - 2);
        foreach (var cell in new[] { cells[0], cells[^1] })
        {
            w.ShowRowFocus(cell, keyboard: true);
            Pump(() => true);
            var frame = Assert.IsType<RowFocusFrame>(Assert.Single(layer.GetAdorners(row)!));
            var drawn = VisualTreeHelper.GetContentBounds(frame);
            Assert.Equal(new Rect(row.RenderSize), drawn);
            var box = frame.TransformToAncestor(grid).TransformBounds(drawn);
            Assert.True(inside.Contains(box), $"{box} fuori da {inside}");
        }
        w.ShowRowFocus(cells[^1], keyboard: false);
        Assert.Null(layer.GetAdorners(row));
        // Spazio su una cella qualsiasi cambia la spunta della riga, avanti e indietro.
        var item = (PackageItem)row.Item;
        var before = item.Selected;
        Assert.True(MainWindow.ToggleRowCheck(cells[2]));
        Assert.Equal(!before, item.Selected);
        Assert.True(MainWindow.ToggleRowCheck(cells[^1]));
        Assert.Equal(before, item.Selected);
        Assert.False(MainWindow.ToggleRowCheck(grid));
        var updatesTab = tabs.Items.Cast<TabItem>().ElementAt(MainViewModel.UpdatesTab);
        Assert.Contains(FindAll<Border>(updatesTab), b => System.Windows.Automation.AutomationProperties.GetName(b) == "30 updates available");
        var hint = FindAll<TextBlock>(w).First(t => t.Style == w.FindResource("Hint"));
        Assert.Equal(System.Windows.Automation.AutomationLiveSetting.Polite, System.Windows.Automation.AutomationProperties.GetLiveSetting(hint));
        Assert.Equal(System.Windows.Automation.AutomationLiveSetting.Polite,
            System.Windows.Automation.AutomationProperties.GetLiveSetting((TextBlock)w.FindName("Announcement")));
        all.IsChecked = false;
        // Etichette che dicono l'azione (ADR 0028, punto 17), nella scheda aperta (Updates): il
        // contenuto sta nel TabControl, non nella TabItem.
        Assert.Contains(FindAll<Button>(tabs), b => b.Content as string == "Check for updates");
        Assert.Contains(FindAll<CheckBox>(tabs), c => c.Content as string == "Include unknown versions");
        var scope = (ComboBox)w.FindName("CmbScope");
        Assert.Equal(["Auto", "Current user", "All users"], scope.Items.Cast<ScopeChoice>().Select(s => s.Label));
        Assert.Equal("Auto", ((ScopeChoice)scope.SelectedItem).Label);
        // Suggerimento nel campo vuoto (ADR 0028, punto 17): dove comincia il testo scritto, e solo
        // finche' il campo e' vuoto.
        tabs.SelectedIndex = MainViewModel.InstallTab;
        var search = (TextBox)w.FindName("TxtSearch");
        var placeholder = (TextBlock)w.FindName("HintSearch");
        Pump(() => placeholder.IsVisible);
        Assert.True(placeholder.IsVisible);
        Assert.Equal(search.GetRectFromCharacterIndex(0).X, placeholder.TranslatePoint(new Point(), search).X, 1.0);
        h.Vm.Install.SearchText = "ab";
        Pump(() => true);
        Assert.False(placeholder.IsVisible);
        h.Vm.Install.SearchText = "";
        tabs.SelectedIndex = MainViewModel.UpdatesTab;
        Pump(() => true);
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
        // Menu a sinistra (ADR 0028): tre sezioni, si apre sulla prima e mostra solo la sua pagina.
        var nav = (ListBox)settings.FindName("Nav");
        Assert.Equal(["Appearance", "General", "App updates"], nav.Items.Cast<ListBoxItem>().Select(i => (string)i.Content));
        Assert.Equal(0, nav.SelectedIndex);
        Assert.True(FindAll<CheckBox>(settings).All(c => !c.IsVisible));
        nav.SelectedIndex = 1;
        Pump(() => true);
        Assert.Contains(FindAll<CheckBox>(settings), c => c.IsVisible && (string)c.Content == "Close to tray");
        Assert.False(FindChild<ComboBox>(settings)!.IsVisible);
        // Il pulsante in alto comprime il menu alle sole icone.
        // Le voci restano alla stessa altezza: senza il nome non salgono.
        var wide = nav.ActualWidth;
        var last = (ListBoxItem)nav.ItemContainerGenerator.ContainerFromIndex(2);
        var y = last.TranslatePoint(new Point(), nav).Y;
        settings.NavCompact = true;
        Pump(() => nav.ActualWidth < 60);
        Assert.True(nav.ActualWidth < 60 && wide > 150, $"{wide} -> {nav.ActualWidth}");
        Assert.Equal(y, last.TranslatePoint(new Point(), nav).Y);
        h.Vm.Settings.ApplyTheme = name => app.ThemeMode = App.Theme(name);
        Assert.Contains("Found 30 updates.", ((TextBox)w.FindName("TxtLog")).Text);
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
        // Coi verbi (ADR 0020): i pulsanti dicono cosa fanno, default e accento restano sul secondo.
        var verbs = new AppDialog("Uninstall 1 package?", "Confirm uninstall", MessageBoxButton.YesNo,
            MessageBoxImage.Warning, MessageBoxResult.No, null, links: false, verbs: ("Uninstall", "Cancel"));
        buttons = ((StackPanel)verbs.FindName("DlgButtons")).Children.Cast<Button>().ToList();
        Assert.Equal(["Uninstall", "Cancel"], buttons.Select(b => (string)b.Content));
        Assert.True(buttons[1].IsDefault && buttons[1].IsCancel && !buttons[0].IsDefault);
        Assert.Equal(MessageBoxResult.No, verbs.Answer);
        verbs.Close();

        // I dettagli (testo coi link): il font della finestra e non il serif del FlowDocument,
        // piu' piccolo e piu' largo del resto.
        var details = new AppDialog("Name: App A\nHomepage: https://example.com", "App A - details", MessageBoxButton.OK,
            MessageBoxImage.None, MessageBoxResult.None, null, links: true);
        var rich = ((StackPanel)details.FindName("DlgBody")).Children.OfType<RichTextBox>().First();
        Assert.Equal(details.FontFamily, rich.Document.FontFamily);
        Assert.Equal((12d, 680d), (rich.Document.FontSize, rich.Width));
        details.Close();
        // Dettagli letti per posizione (ADR 0021): titolo col nome, poi una tabella etichetta/valore
        // con etichette secondarie e link; un valore lungo va a capo, la finestra non si allarga.
        var parsed = PackageDetails.Parse("App A", "Found App A [A.A]\r\nHomepage: https://example.com\r\nTags:\r\n  one\r\n  two\r\nSHA256: " + new string('a', 64))!;
        var table = new AppDialog("text", "App A - details", MessageBoxButton.OK, MessageBoxImage.None, MessageBoxResult.None, parsed, links: true)
        {
            Owner = w, ShowActivated = false,
        };
        var doc = ((StackPanel)table.FindName("DlgBody")).Children.OfType<RichTextBox>().First().Document;
        Assert.Equal(table.FontFamily, doc.FontFamily);
        var title = Assert.IsType<Paragraph>(doc.Blocks.FirstBlock);
        Assert.Equal(("App A", 14d, FontWeights.SemiBold), (new TextRange(title.ContentStart, title.ContentEnd).Text, title.FontSize, title.FontWeight));
        var tableRows = Assert.Single(doc.Blocks.OfType<Table>()).RowGroups.SelectMany(g => g.Rows).ToList();
        Assert.Equal(4, tableRows.Count);
        Assert.Equal(((SolidColorBrush)w.FindResource("TextFillColorSecondaryBrush")).Color, ((SolidColorBrush)tableRows[1].Cells[0].Foreground).Color);
        var link = Assert.Single(FindLinks(doc));
        Assert.Equal("https://example.com/", link.NavigateUri.AbsoluteUri);
        table.Show();
        Pump(() => true);
        Assert.True(table.ActualWidth <= 760, $"{table.ActualWidth}");
        table.Close();

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

    private static IEnumerable<Hyperlink> FindLinks(FlowDocument doc) =>
        doc.Blocks.OfType<Table>().SelectMany(t => t.RowGroups).SelectMany(g => g.Rows).SelectMany(r => r.Cells)
            .SelectMany(c => c.Blocks.OfType<Paragraph>()).SelectMany(p => p.Inlines.OfType<Hyperlink>());

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

    // Announce accende e spegne LiveSetting; un testo che cambia senza lettori di schermo non
    // lancia nulla. Nessuna Application: basta un thread STA.
    [Fact]
    public void LiveRegionSetsPolite() => RunSta(() =>
    {
        var text = new TextBlock();
        LiveRegion.SetAnnounce(text, true);
        Assert.Equal(System.Windows.Automation.AutomationLiveSetting.Polite, System.Windows.Automation.AutomationProperties.GetLiveSetting(text));
        text.Text = "Update complete: 1 ok.";
        LiveRegion.SetAnnounce(text, false);
        Assert.Equal(System.Windows.Automation.AutomationLiveSetting.Off, System.Windows.Automation.AutomationProperties.GetLiveSetting(text));
    });

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
