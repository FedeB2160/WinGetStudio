using System.Diagnostics;
using System.Globalization;
using System.Windows;
using System.Windows.Data;
using System.Windows.Input;
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

        ContentRendered += async (_, _) =>
        {
            var ready = (DateTime.Now - Process.GetCurrentProcess().StartTime).TotalSeconds;
            vm.Log.Write($"Ready in {ready.ToString("0.0", CultureInfo.InvariantCulture)} s.");
            await vm.StartAsync();
        };
    }

    public MainViewModel ViewModel { get; }

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
