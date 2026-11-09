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
        // La lettura degli aggiornamenti resta in corso finche' il test non apre il cancello.
        var gate = new TaskCompletionSource();
        using var h = new Harness(h =>
        {
            h.WinGet.Respond = a => FakeWinGet.Result(0, a[0] == "upgrade" ? FakeWinGet.Upgrades(rows) : "");
            h.WinGet.Before = a => a[0] == "upgrade" ? gate.Task : Task.CompletedTask;
        });
        var w = new MainWindow(h.Vm)
        {
            ShowActivated = false, ShowInTaskbar = false, WindowStartupLocation = WindowStartupLocation.Manual, Left = -20000, Top = -20000,
        };
        w.Show();
        // Con winget al lavoro: lo spinner grande al centro della griglia e la scritta, dopo 400 ms;
        // a lavoro finito sparisce e la scritta si vuota (ADR 0028, punto 19).
        var busy = (BusyOverlay)w.FindName("BusyUpdates");
        var caption = (TextBlock)busy.FindName("Caption");
        Pump(() => caption.Text.Length > 0);
        Assert.Equal((Visibility.Visible, 1d, "Checking for updates..."), (busy.Visibility, busy.Opacity, caption.Text));
        // Nessuno spinner accanto ai pulsanti delle schede: gli unici della finestra sono nei tre overlay.
        var overlays = FindLogical<BusyOverlay>(w).ToList();
        Assert.Equal(3, overlays.Count);
        Assert.Equal(3, FindLogical<Spinner>(w).Count());
        Assert.Equal(3, overlays.Sum(o => FindLogical<Spinner>(o).Count()));
        gate.SetResult();
        Pump(() => !h.State.IsBusy && h.Vm.Updates.Items.Count == rows.Length);
        Assert.Equal((Visibility.Collapsed, ""), (busy.Visibility, caption.Text));

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
        // Tutti i titoli al centro della colonna (scelta dell'utente, ADR 0028 punto 18), e Seleziona
        // tutto sopra le spunte delle righe. Lo spazio che l'intestazione Fluent tiene a destra per
        // la freccia di ordinamento dipende dal font dei glifi (piu' grande qui sotto): HeaderBalance
        // lo rende anche a sinistra, con qualunque font.
        var updatesGrid = (DataGrid)w.FindName("GridUpdates");
        var firstRow = FindChild<DataGridRow>(updatesGrid)!;
        double Left(FrameworkElement e) => e.TranslatePoint(new Point(), updatesGrid).X;
        double Middle(FrameworkElement e) => Left(e) + e.ActualWidth / 2;
        // Il quadratino, non il controllo: il template Fluent lo disegna a sinistra, e un controllo
        // con piu' padding ha il centro altrove.
        FrameworkElement Box(CheckBox c) => (FrameworkElement)c.Template.FindName("ControlBorderIconPresenter", c);
        void SelectAllCentered() => Assert.Equal(Middle(Box(FindChild<CheckBox>(firstRow)!)), Middle(Box(all)), 0.5);
        void HeadersCentered()
        {
            foreach (var header in FindAll<DataGridColumnHeader>(headers).Where(c => c.Column is not null))
            {
                FrameworkElement content = header.Content is string ? FindChild<TextBlock>(header)! : FindChild<CheckBox>(header)!;
                Assert.True(Math.Abs(Middle(header) - Middle(content)) <= 0.5, $"{header.Content}: {Middle(header)} vs {Middle(content)}");
            }
            SelectAllCentered();
        }
        HeadersCentered();
        // Spunte con etichetta: centro del testo sul centro del quadratino (ADR 0028 punto 20).
        // Entro 1 px: il font del runner CI non e' quello di Windows 11.
        void LabelCentered(CheckBox c)
        {
            var text = FindChild<TextBlock>((ContentPresenter)c.Template.FindName("ContentPresenter", c))!;
            double Mid(FrameworkElement e) => e.TranslatePoint(new Point(0, e.ActualHeight / 2), c).Y;
            Assert.True(Math.Abs(Mid(Box(c)) - Mid(text)) <= 1.0, $"{c.Content}: {Mid(Box(c))} vs {Mid(text)}");
        }
        LabelCentered(FindAll<CheckBox>(w).First(c => c.Content as string == "Include unknown versions"));
        updatesGrid.Resources["DataGridSortIndicatorIconFontSize"] = 18d;
        Pump(() => true);
        SelectAllCentered();
        updatesGrid.Resources.Remove("DataGridSortIndicatorIconFontSize");
        Pump(() => true);
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
        // Un nome solo per lo Store (2.0 UI/UX review R18).
        Assert.Equal("Microsoft Store", ((CheckBox)w.FindName("ChkStore")).Content);
        // Le scorciatoie nei tooltip e per i lettori di schermo (2.0 UI/UX review R21).
        foreach (var (element, tip, key) in new[]
        {
            ("BtnRefresh", "Read the installed packages again (F5)", "F5"),
            ("BtnCheck", "Look for newer versions of the installed packages (F5)", "F5"),
            ("TxtSearch", "Search the winget catalog (Ctrl+F)", "Ctrl+F"),
        })
        {
            var control = (FrameworkElement)w.FindName(element);
            Assert.Equal((tip, key), (control.ToolTip as string, System.Windows.Automation.AutomationProperties.GetAcceleratorKey(control)));
        }
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
        // Il velo sotto un dialogo copre tutta l'area della finestra, margine della griglia compreso.
        w.SetDim(true);
        Pump(() => true);
        var dim = (FrameworkElement)w.FindName("DialogDim");
        var area = (FrameworkElement)VisualTreeHelper.GetParent((Visual)w.Content);
        Assert.Equal(new Rect(0, 0, area.ActualWidth, area.ActualHeight), dim.TransformToAncestor(area).TransformBounds(new Rect(dim.RenderSize)));
        w.SetDim(false);
        // Settings e About sono finestre a parte (ADR 0028): si aprono, col logo, e si chiudono.
        var about = new AboutWindow("2.0.0") { Owner = w, ShowActivated = false };
        about.Show();
        Pump(() => true);
        Assert.True(about.FindName("TxtVersion") is TextBlock { Text: "v2.0.0" });
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
        var tray = FindAll<CheckBox>(settings).First(c => c.Content as string == "Close to tray");
        LabelCentered(tray);
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
        LabelCentered(tray);
        settings.NavCompact = false;
        // App updates: etichetta e valore sulla stessa riga, centrati (2.0 UI/UX review R20).
        nav.SelectedIndex = 2;
        Pump(() => true);
        double Center(TextBlock t) => t.TranslatePoint(new Point(0, t.ActualHeight / 2), settings).Y;
        var shown = FindAll<TextBlock>(settings).Where(t => t.IsVisible).ToList();
        foreach (var (label, value) in new[] { ("WinGet Studio", h.Vm.Settings.VersionText), ("winget", h.Vm.Settings.WinGetVersionText) })
            Assert.Equal(Center(shown.First(t => t.Text == label)), Center(shown.First(t => t.Text == value)), 1.0);
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
        // Dettagli letti per posizione (ADR 0021): il nome come titolo e l'Id sotto, poi una sezione
        // per lettura col nome dato dall'app e una tabella etichetta/valore, etichette secondarie e
        // allineate a sinistra, link cliccabili; un valore lungo va a capo, la finestra non si allarga.
        var parsed = PackageDetails.Parse("App A", "A.A", new DetailsReads("",
            "Found App A [A.A]\r\nHomepage: https://example.com\r\nTags:\r\n  one\r\n  two\r\nSHA256: " + new string('a', 64)), "winget")!;
        var table = new AppDialog("text", "App A - details", MessageBoxButton.OK, MessageBoxImage.None, MessageBoxResult.None, parsed, links: true)
        {
            Owner = w, ShowActivated = false,
        };
        var detailsViewer = ((StackPanel)table.FindName("DlgBody")).Children.OfType<FlowDocumentScrollViewer>().First();
        var doc = detailsViewer.Document;
        Assert.Equal(table.FontFamily, doc.FontFamily);
        Assert.Equal(TextAlignment.Left, doc.TextAlignment);
        var blocks = doc.Blocks.ToList();
        string Text(TextElement e) => new TextRange(e.ContentStart, e.ContentEnd).Text;
        var title = Assert.IsType<Paragraph>(blocks[0]);
        Assert.Equal(("App A", 14d, FontWeights.SemiBold), (Text(title), title.FontSize, title.FontWeight));
        Assert.Equal("A.A", Text(blocks[1]));
        Assert.Equal("Catalog (winget)", Text(blocks[2]));
        var tableRows = Assert.Single(blocks.OfType<Table>()).RowGroups.SelectMany(g => g.Rows).ToList();
        Assert.Equal(["Homepage", "Tags", "SHA256"], tableRows.Select(r => Text(r.Cells[0]).Trim()));
        Assert.Equal("one, two", Text(tableRows[1].Cells[1]).Trim());
        Assert.Equal(((SolidColorBrush)w.FindResource("TextFillColorSecondaryBrush")).Color, ((SolidColorBrush)tableRows[0].Cells[0].Foreground).Color);
        var link = Assert.Single(FindLinks(doc));
        Assert.Equal("https://example.com/", link.NavigateUri.AbsoluteUri);
        // Un pulsante solo: Close, come la scheda Install.
        Assert.Equal("Close", ((StackPanel)table.FindName("DlgButtons")).Children.Cast<Button>().Single().Content);
        table.Show();
        Pump(() => true);
        Assert.True(table.ActualWidth <= 760, $"{table.ActualWidth}");
        // Il valore comincia dopo la colonna delle etichette, larga quanto la piu' lunga.
        Assert.InRange(link.ContentStart.GetCharacterRect(LogicalDirection.Forward).X, 90, 240);
        table.Close();
        // Anteprima dell'import (2.0 UI/UX review R22): Seleziona tutto sopra le spunte delle righe,
        // "latest" in secondario dove il file non ha la versione.
        var import = new AppDialog("Install?", "Confirm import", MessageBoxButton.YesNo, MessageBoxImage.Warning, MessageBoxResult.No,
            new ImportPreviewViewModel(InstalledViewModelTests.TwoPackages()), links: false) { Owner = w, ShowActivated = false };
        import.Show();
        Pump(() => true);
        var importGrid = FindChild<DataGrid>(import)!;
        var importAll = FindChild<CheckBox>(FindChild<DataGridColumnHeadersPresenter>(importGrid)!)!;
        Assert.True(importAll.IsChecked);
        var importRow = FindChild<DataGridRow>(importGrid)!;
        double ImportMiddle(FrameworkElement e) => e.TranslatePoint(new Point(), importGrid).X + e.ActualWidth / 2;
        FrameworkElement ImportBox(CheckBox c) => (FrameworkElement)c.Template.FindName("ControlBorderIconPresenter", c);
        Assert.Equal(ImportMiddle(ImportBox(FindChild<CheckBox>(importRow)!)), ImportMiddle(ImportBox(importAll)), 0.5);
        var texts = FindAll<TextBlock>(importGrid).ToList();
        Assert.Contains(texts, t => t.Text == "1.0");
        var latest = texts.Single(t => t.Text == "latest");
        Assert.Equal(((SolidColorBrush)w.FindResource("TextFillColorSecondaryBrush")).Color, ((SolidColorBrush)latest.Foreground).Color);
        import.Close();

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

    // Albero logico: arriva anche nelle schede non selezionate, che non hanno ancora un albero visuale.
    private static IEnumerable<T> FindLogical<T>(DependencyObject parent) where T : DependencyObject
    {
        foreach (var c in LogicalTreeHelper.GetChildren(parent).OfType<DependencyObject>())
        {
            if (c is T t) yield return t;
            foreach (var d in FindLogical<T>(c)) yield return d;
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
