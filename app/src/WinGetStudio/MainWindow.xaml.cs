using System.Diagnostics;
using System.Globalization;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Data;
using System.Windows.Documents;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Threading;
using WinGetStudio.ViewModels;

namespace WinGetStudio;

public partial class MainWindow : Window
{
    public MainWindow(MainViewModel vm)
    {
        ViewModel = vm;
        DataContext = vm;
        InitializeComponent();
        TitleBar.Follow(this);
        // Bordo della linguetta attiva a 2 px come il riquadro, le altre a 1 (ADR 0028). Il template
        // Fluent lo ha fisso a 1 sul suo Border interno, che non legge BorderThickness: si cambia li'.
        void TabBorders()
        {
            foreach (var tab in TabMain.Items.OfType<TabItem>())
                if (tab.Template?.FindName("Border", tab) is Border b)
                    b.BorderThickness = tab.IsSelected ? new Thickness(2, 2, 2, 0) : new Thickness(1, 1, 1, 0);
        }
        foreach (var tab in TabMain.Items.OfType<TabItem>()) tab.Loaded += (_, _) => TabBorders();
        // Solo il cambio di scheda: SelectionChanged sale anche dalle griglie dentro.
        TabMain.SelectionChanged += (_, e) => { if (e.OriginalSource == TabMain) TabBorders(); };

        // Colori dei bordi opachi, seguendo il tema (le due chiavi Color cambiano con lui).
        SetResourceReference(StrokeColorProperty, "ControlStrongStrokeColorDefault");
        SetResourceReference(BaseColorProperty, "SolidBackgroundFillColorBase");

        // Il log si aggiunge riga per riga, non si rilega tutto il testo a ogni riga.
        TxtLog.AppendText(vm.Log.Text);
        vm.Log.Appended += line => { TxtLog.AppendText(line); TxtLog.ScrollToEnd(); };
        vm.Log.Cleared += TxtLog.Clear;

        // Filtro di Installed sulla vista della griglia: le righe escluse restano nell'elenco.
        var installed = CollectionViewSource.GetDefaultView(vm.Installed.Items);
        installed.Filter = o => vm.Installed.Matches((PackageItem)o);
        vm.Installed.PropertyChanged += (_, e) => { if (e.PropertyName == nameof(InstalledViewModel.FilterText)) installed.Refresh(); };

        // Angoli arrotondati a pillola: il binario del template Fluent e' un rettangolo con 1 px di
        // margine, quindi il ritaglio segue lui e non il controllo.
        Progress.SizeChanged += (_, e) => Progress.Clip = new RectangleGeometry(
            new Rect(1, 1, Math.Max(0, e.NewSize.Width - 2), Math.Max(0, e.NewSize.Height - 2)), (e.NewSize.Height - 2) / 2, (e.NewSize.Height - 2) / 2);

        // Dopo ogni ridimensionamento a mano (trascinamento o doppio clic sul bordo) le colonne
        // elastiche tornano a '*' nelle proporzioni scelte: i bordi non si spostano e le colonne
        // fisse (spunta, Pin, Result) non escono dalla griglia.
        AddHandler(Thumb.DragCompletedEvent, new DragCompletedEventHandler((_, e) => RefitColumns(e.OriginalSource)), true);
        AddHandler(Control.MouseDoubleClickEvent, new MouseButtonEventHandler((_, e) => RefitColumns(e.OriginalSource)), true);

        AttachScrollBar(GridSearch, BarSearch);
        AttachScrollBar(GridInstalled, BarInstalled);
        AttachScrollBar(GridUpdates, BarUpdates);

        // Cornice di fuoco sulla riga (ADR 0028, punto 16), in tutte e tre le griglie. Anche sugli
        // eventi gia' gestiti: il DataGrid gestisce i suoi.
        var focusMoved = new KeyboardFocusChangedEventHandler((_, e) =>
            ShowRowFocus(e.NewFocus, InputManager.Current.MostRecentInputDevice is KeyboardDevice));
        AddHandler(Keyboard.GotKeyboardFocusEvent, focusMoved, true);
        AddHandler(Keyboard.LostKeyboardFocusEvent, focusMoved, true);

        SourceInitialized += (_, _) => AddRestartToSystemMenu();

        ContentRendered += async (_, _) =>
        {
            var ready = (DateTime.Now - Process.GetCurrentProcess().StartTime).TotalSeconds;
            vm.Log.Write($"Ready in {ready.ToString("0.0", CultureInfo.InvariantCulture)} s.");
            await vm.StartAsync();
        };
    }

    public MainViewModel ViewModel { get; }

    // I bordi di riquadro e linguette sono il tratto forte del tema in trasparenza: dove si
    // sovrappongono (la linguetta attiva sulla riga del riquadro) i colori si sommano e restano
    // punti chiari. Qui diventano gli stessi colori gia' fusi sullo sfondo della finestra, opachi.
    private static readonly DependencyProperty StrokeColorProperty = DependencyProperty.Register(
        "StrokeColor", typeof(Color), typeof(MainWindow), new PropertyMetadata(default(Color), (d, _) => ((MainWindow)d).SolidStrokes()));
    private static readonly DependencyProperty BaseColorProperty = DependencyProperty.Register(
        "BaseColor", typeof(Color), typeof(MainWindow), new PropertyMetadata(default(Color), (d, _) => ((MainWindow)d).SolidStrokes()));

    private void SolidStrokes()
    {
        var stroke = (Color)GetValue(StrokeColorProperty);
        var back = (Color)GetValue(BaseColorProperty);
        if (stroke.A == 0 || back.A == 0) return;
        SolidColorBrush Blend(double opacity)
        {
            var a = stroke.A / 255.0 * opacity;
            byte Mix(byte s, byte b) => (byte)Math.Round(b + (s - b) * a);
            var brush = new SolidColorBrush(Color.FromRgb(Mix(stroke.R, back.R), Mix(stroke.G, back.G), Mix(stroke.B, back.B)));
            brush.Freeze();
            return brush;
        }
        // Stesse opacita' di Styles.xaml (55% le aree e l'attiva, 25% le non attive).
        Resources["AreaStrokeBrush"] = Blend(0.55);
        Resources["TabViewSelectedItemBorderBrush"] = Blend(0.55);
        Resources["TabStrokeInactiveBrush"] = Blend(0.25);
    }

    // Pin solo se fra le righe evidenziate ce n'e' una senza pin, Remove pin solo se ce n'e' una
    // con: una voce che non farebbe nulla non si mostra.
    private void PinMenu_Opened(object sender, RoutedEventArgs e)
    {
        var menu = (ContextMenu)sender;
        var (pin, unpin) = PinChoices((menu.PlacementTarget as DataGrid)?.SelectedItems.OfType<PackageItem>() ?? []);
        foreach (var m in menu.Items.OfType<MenuItem>())
        {
            if (m.Tag is "pin") m.Visibility = pin ? Visibility.Visible : Visibility.Collapsed;
            else if (m.Tag is "unpin") m.Visibility = unpin ? Visibility.Visible : Visibility.Collapsed;
        }
    }

    internal static (bool Pin, bool Unpin) PinChoices(IEnumerable<PackageItem> highlighted)
    {
        var rows = highlighted.ToList();
        return (rows.Any(r => !r.Pinned), rows.Any(r => r.Pinned));
    }

    // Solo se l'evento viene da un'intestazione di colonna; dopo il layout, quando le larghezze
    // nuove sono quelle vere.
    private void RefitColumns(object source)
    {
        if (source is not DependencyObject d || FindAncestor<DataGridColumnHeader>(d) is null || FindAncestor<DataGrid>(d) is not { } grid) return;
        Dispatcher.BeginInvoke(DispatcherPriority.Loaded, () => Refit(grid));
    }

    internal static void Refit(DataGrid grid)
    {
        var flexible = grid.Columns.Where(c => c.CanUserResize).ToList();
        // Le fisse contano per la larghezza dichiarata: schiacciate, anche loro scendono a 20 px.
        var room = Descendants<ScrollViewer>(grid).FirstOrDefault()?.ViewportWidth
            - grid.Columns.Where(c => !c.CanUserResize).Sum(c => c.Width.IsAbsolute ? c.Width.Value : c.ActualWidth);
        // Doppio clic sul bordo: la colonna va ad Auto e, se non ci sta, il DataGrid schiaccia le
        // altre ai suoi 20 px minimi. Salvate cosi' come proporzioni, restavano schiacciate.
        if (flexible.Where(c => !c.Width.IsStar).ToList() is [var grown] && room > 0
            && (grown.Width.IsAuto || flexible.Sum(c => c.ActualWidth) > room + 0.5))
        {
            FitAround(grid, grown, flexible.Where(c => c != grown).ToList(), room.Value);
            return;
        }
        foreach (var c in flexible)
            c.Width = new DataGridLength(Math.Max(c.ActualWidth, c.MinWidth), DataGridLengthUnitType.Star);
    }

    // La colonna allargata tiene la sua larghezza; le altre si dividono il resto coi loro pesi '*',
    // ma nessuna sotto il proprio titolo. Se nemmeno cosi' ci sta, si accorcia quella allargata.
    private static void FitAround(DataGrid grid, DataGridColumn grown, List<DataGridColumn> others, double room)
    {
        var floor = others.ToDictionary(c => c, c => HeaderWidth(grid, c));
        var width = Math.Max(grown.MinWidth, Math.Min(grown.ActualWidth, room - floor.Values.Sum()));
        var share = new Dictionary<DataGridColumn, double>();
        var free = others.ToList();
        var rest = room - width;
        // Chi scenderebbe sotto il titolo si ferma li'; il resto si ridivide fra gli altri.
        while (free.Count > 0)
        {
            var weights = free.Sum(c => c.Width.Value);
            var below = free.Where(c => rest * c.Width.Value / weights < floor[c]).ToList();
            if (below.Count == 0) { foreach (var c in free) share[c] = rest * c.Width.Value / weights; break; }
            foreach (var c in below) { share[c] = floor[c]; rest -= floor[c]; free.Remove(c); }
        }
        grown.Width = new DataGridLength(width, DataGridLengthUnitType.Star);
        foreach (var c in others) c.Width = new DataGridLength(share[c], DataGridLengthUnitType.Star);
    }

    // Larghezza che il titolo chiede senza vincoli: lo spazio della freccia di ordinamento compreso.
    private static double HeaderWidth(DataGrid grid, DataGridColumn column)
    {
        if (Descendants<DataGridColumnHeader>(grid).FirstOrDefault(h => h.Column == column) is not { } header) return column.MinWidth;
        header.Measure(new Size(double.PositiveInfinity, double.PositiveInfinity));
        return Math.Max(header.DesiredSize.Width, column.MinWidth);
    }

    // La barra accanto alla griglia segue lo ScrollViewer del DataGrid (la sua e' nascosta) e lo
    // muove. Nascosta e non Collapsed quando non serve: il suo spazio resta, le colonne stanno ferme.
    private static void AttachScrollBar(DataGrid grid, ScrollBar bar)
    {
        ScrollViewer? attached = null;
        grid.Loaded += (_, _) =>
        {
            // Loaded torna a ogni cambio di scheda: lo ScrollViewer si aggancia una volta sola. Senza
            // righe la griglia e' Collapsed e il template non c'e' ancora: lo si applica qui.
            grid.ApplyTemplate();
            if (Descendants<ScrollViewer>(grid).FirstOrDefault() is not { } sv || sv == attached) return;
            attached = sv;
            void Sync()
            {
                bar.Maximum = sv.ScrollableHeight;
                bar.ViewportSize = sv.ViewportHeight;
                bar.LargeChange = Math.Max(1, sv.ViewportHeight);
                bar.Value = sv.VerticalOffset;
                bar.Visibility = sv.ScrollableHeight > 0 ? Visibility.Visible : Visibility.Hidden;
            }
            sv.ScrollChanged += (_, _) => Sync();
            bar.Scroll += (_, e) => sv.ScrollToVerticalOffset(e.NewValue);
            Sync();
        };
    }

    private RowFocusFrame? rowFocus;

    // La cornice va sulla riga col fuoco se ci si e' arrivati con la tastiera (Tab, frecce, anche
    // Ctrl+frecce, che non selezionano); un clic, o il fuoco fuori dalle griglie, la toglie.
    internal void ShowRowFocus(object? focus, bool keyboard)
    {
        var row = keyboard && focus is DependencyObject d ? FindAncestor<DataGridRow>(d) : null;
        if (row is not null && row == rowFocus?.AdornedElement) return;
        // Dal livello che la contiene: la riga puo' essere gia' uscita dall'albero.
        if (rowFocus is not null) (VisualTreeHelper.GetParent(rowFocus) as AdornerLayer)?.Remove(rowFocus);
        rowFocus = null;
        if (row is not null && AdornerLayer.GetAdornerLayer(row) is { } layer) layer.Add(rowFocus = new RowFocusFrame(row));
    }

    private static IEnumerable<T> Descendants<T>(DependencyObject parent) where T : DependencyObject
    {
        for (var i = 0; i < VisualTreeHelper.GetChildrenCount(parent); i++)
        {
            var c = VisualTreeHelper.GetChild(parent, i);
            if (c is T t) yield return t;
            foreach (var d in Descendants<T>(c)) yield return d;
        }
    }

    private static T? FindAncestor<T>(DependencyObject d) where T : DependencyObject
    {
        for (var p = d; p is not null; p = p is Visual or System.Windows.Media.Media3D.Visual3D ? VisualTreeHelper.GetParent(p) : LogicalTreeHelper.GetParent(p))
            if (p is T t) return t;
        return null;
    }

    // Restart as administrator anche nel menu della finestra (icona o Alt+Spazio, ADR 0024), solo
    // dove Settings lo offre; grigio mentre una coda lavora, come il pulsante.
    private const int WmSysCommand = 0x0112, WmInitMenuPopup = 0x0117, RestartElevatedId = 0x1000;

    private void AddRestartToSystemMenu()
    {
        var command = ViewModel.Settings.RestartElevatedCommand;
        if (!ViewModel.Settings.CanRestartElevated) return;
        var hwnd = new WindowInteropHelper(this).Handle;
        var menu = GetSystemMenu(hwnd, false);
        AppendMenuW(menu, 0x0800, 0, null);                                   // MF_SEPARATOR
        AppendMenuW(menu, 0, RestartElevatedId, "Restart as administrator");  // MF_STRING
        HwndSource.FromHwnd(hwnd).AddHook((nint _, int msg, nint wParam, nint _, ref bool handled) =>
        {
            if (msg == WmInitMenuPopup)
                EnableMenuItem(menu, RestartElevatedId, command.CanExecute(null) ? 0u : 1u);   // MF_ENABLED / MF_GRAYED
            else if (msg == WmSysCommand && (wParam & 0xFFF0) == RestartElevatedId)
            {
                if (command.CanExecute(null)) command.Execute(null);
                handled = true;
            }
            return 0;
        });
    }

    [DllImport("user32.dll")]
    private static extern nint GetSystemMenu(nint hwnd, bool revert);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern bool AppendMenuW(nint menu, uint flags, nint id, string? text);

    [DllImport("user32.dll")]
    private static extern int EnableMenuItem(nint menu, uint id, uint flags);

    // Velo sotto un dialogo (ADR 0020).
    internal void SetDim(bool on) => DialogDim.Visibility = on ? Visibility.Visible : Visibility.Collapsed;

    // Sulla FINESTRA e in tunneling: un DataGrid col fuoco si mangerebbe F5 e Ctrl+F.
    protected override void OnPreviewKeyDown(KeyEventArgs e)
    {
        base.OnPreviewKeyDown(e);
        if (e.Key == Key.F5)
        {
            ViewModel.State.Fire(ViewModel.RefreshCurrentAsync);
            e.Handled = true;
        }
        else if (e.Key == Key.F && Keyboard.Modifiers.HasFlag(ModifierKeys.Control))
        {
            ViewModel.SelectedTab = MainViewModel.InstallTab;
            // Dopo il cambio di scheda: prima il campo non e' ancora nell'albero visibile.
            Dispatcher.BeginInvoke(DispatcherPriority.Input, () => { TxtSearch.Focus(); TxtSearch.SelectAll(); });
            e.Handled = true;
        }
        else if (e.Key == Key.Space && Keyboard.Modifiers == ModifierKeys.None && ToggleRowCheck(e.OriginalSource))
            e.Handled = true;
    }

    // Spazio su una cella cambia la spunta della riga col fuoco (ADR 0028, punto 16), quella della
    // cornice, non per forza la selezionata. Passa dalla CheckBox: spenta mentre winget lavora o su
    // una riga con pin in Updates, non cambia. Sulla CheckBox col fuoco Spazio lo gestisce lei.
    internal static bool ToggleRowCheck(object source)
    {
        if (source is not DataGridCell cell || FindAncestor<DataGridRow>(cell) is not { } row) return false;
        if (Descendants<CheckBox>(row).FirstOrDefault() is { IsEnabled: true } check) check.IsChecked = check.IsChecked != true;
        return true;
    }
}
