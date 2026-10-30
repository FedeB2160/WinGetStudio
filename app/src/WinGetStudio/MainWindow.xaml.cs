using System.Diagnostics;
using System.Globalization;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Data;
using System.Windows.Input;
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

        ContentRendered += async (_, _) =>
        {
            var ready = (DateTime.Now - Process.GetCurrentProcess().StartTime).TotalSeconds;
            vm.Log.Write($"Ready in {ready.ToString("0.0", CultureInfo.InvariantCulture)} s.");
            await vm.StartAsync();
        };
    }

    public MainViewModel ViewModel { get; }

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
        foreach (var c in grid.Columns.Where(c => c.CanUserResize))
            c.Width = new DataGridLength(Math.Max(c.ActualWidth, c.MinWidth), DataGridLengthUnitType.Star);
    }

    private static T? FindAncestor<T>(DependencyObject d) where T : DependencyObject
    {
        for (var p = d; p is not null; p = p is Visual or System.Windows.Media.Media3D.Visual3D ? VisualTreeHelper.GetParent(p) : LogicalTreeHelper.GetParent(p))
            if (p is T t) return t;
        return null;
    }

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
    }
}
