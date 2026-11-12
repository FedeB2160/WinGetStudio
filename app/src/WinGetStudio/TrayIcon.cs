using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Interop;
using System.Windows.Threading;
using WinGetStudio.ViewModels;
using Drawing = System.Drawing;
using Forms = System.Windows.Forms;

namespace WinGetStudio;

// L'icona nell'area di notifica (ADR 0030): NotifyIcon di WinForms, l'unico modo senza una
// dipendenza; il menu e' un ContextMenu di WPF, cosi' prende il tema Fluent come il resto.
internal sealed class TrayIcon : IDisposable
{
    private readonly MainViewModel _vm;
    private readonly MainWindow _window;
    private readonly Forms.NotifyIcon _icon = new();
    private readonly Dictionary<TrayDot, Drawing.Icon> _icons;
    private readonly Drawing.Icon[] _busy;
    private readonly DispatcherTimer _timer = new();
    // La freccia che scende al lavoro: 13 fotogrammi, un giro al secondo.
    private readonly DispatcherTimer _spin = new() { Interval = TimeSpan.FromSeconds(1.0 / BusyFrames) };
    private int _frame;

    public TrayIcon(MainViewModel vm, MainWindow window, Action exit)
    {
        _vm = vm;
        _window = window;
        // La misura si legge all'avvio (16 px al 100%): un cambio di scala con l'app aperta non si segue.
        var size = Forms.SystemInformation.SmallIconSize.Width;
        _busy = Enumerable.Range(1, BusyFrames).Select(n => LoadIcon($"busy-{n:D2}", size)).ToArray();
        _icons = new Dictionary<TrayDot, Drawing.Icon>
        {
            [TrayDot.Idle] = LoadIcon("idle", size),
            [TrayDot.Updates] = LoadIcon("updates", size),
            [TrayDot.Errors] = LoadIcon("errors", size),
            [TrayDot.Busy] = _busy[0],
        };
        _spin.Tick += (_, _) =>
        {
            _frame = (_frame + 1) % BusyFrames;
            _icon.Icon = _busy[_frame];
        };
        Menu = BuildMenu(exit);
        Update();
        vm.Tray.PropertyChanged += (_, _) => Update();
        vm.Tray.Notify += n =>
        {
            // Avvisi ed errori con l'icona di Windows; l'esito normale col solo logo dell'app.
            var icon = n.Kind switch { NoticeKind.Error => Forms.ToolTipIcon.Error, NoticeKind.Warning => Forms.ToolTipIcon.Warning, _ => Forms.ToolTipIcon.None };
            // Un fumetto senza testo lancia un'eccezione: il titolo diventa il testo.
            if (n.Text.Length == 0) _icon.ShowBalloonTip(5000, "WinGet Studio", n.Title, icon);
            else _icon.ShowBalloonTip(5000, n.Title, n.Text, icon);
        };
        // La scheda da cui nasce l'ultimo fumetto (null: quella aperta).
        _icon.BalloonTipClicked += (_, _) => ShowWindow(vm.Tray.LastNotice?.Tab);
        _icon.MouseDoubleClick += (_, e) => { if (e.Button == Forms.MouseButtons.Left) ShowWindow(null); };
        _icon.MouseUp += (_, e) => { if (e.Button == Forms.MouseButtons.Right) OpenMenu(); };

        // Controllo periodico: il view model decide se puo' partire (ADR 0003).
        _timer.Tick += (_, _) => vm.State.Fire(vm.Tray.BackgroundCheckAsync);
        vm.Settings.PropertyChanged += (_, e) => { if (e.PropertyName == nameof(SettingsViewModel.CheckEvery)) Schedule(); };
        Schedule();
        _icon.Visible = true;
    }

    internal ContextMenu Menu { get; }

    private HwndSource? _sink;

    private void Schedule()
    {
        _timer.Stop();
        if (_vm.Settings.CheckEvery is not { } every) return;
        _timer.Interval = every;
        _timer.Start();
    }

    private void Update()
    {
        var dot = _vm.Tray.Dot;
        if (Animates(dot, SystemParameters.ClientAreaAnimation))
        {
            // Anche il tooltip passa di qui: l'animazione gia' in corso non riparte da capo.
            if (!_spin.IsEnabled)
            {
                _frame = 0;
                _icon.Icon = _busy[0];
                _spin.Start();
            }
        }
        else
        {
            // Prima si ferma: nessun fotogramma arriva dopo l'icona del nuovo stato.
            _spin.Stop();
            _icon.Icon = _icons[dot];
        }
        // NotifyIcon.Text accetta al massimo 127 caratteri.
        var tip = _vm.Tray.ToolTip;
        _icon.Text = tip.Length > 127 ? tip[..127] : tip;
    }

    private ContextMenu BuildMenu(Action exit)
    {
        MenuItem Item(string header, Action click)
        {
            var m = new MenuItem { Header = header };
            m.Click += (_, _) => click();
            return m;
        }
        return new ContextMenu
        {
            Items =
            {
                Item("Install", () => ShowWindow(MainViewModel.InstallTab)),
                Item("Installed", () => ShowWindow(MainViewModel.InstalledTab)),
                Item("Updates", () => ShowWindow(MainViewModel.UpdatesTab)),
                new Separator(),
                Item("Check for updates", () => _vm.State.Fire(_vm.Tray.CheckNowAsync)),
                new Separator(),
                Item("Settings", () => { if (ShowWindow(null)) _vm.OpenSettingsCommand.Execute(null); }),
                Item("About", () => { if (ShowWindow(null)) _vm.OpenAboutCommand.Execute(null); }),
                new Separator(),
                // "Exit" e non "Close": con Close to tray la X della finestra non chiude l'app.
                Item("Exit", exit),
            },
        };
    }

    // In primo piano: senza, il menu non si chiude cliccando altrove (Shell_NotifyIcon). Una finestra
    // invisibile tutta sua: con la principale, questa salirebbe sopra le altre e l'app risulterebbe
    // attiva, e le notifiche tacerebbero.
    private void OpenMenu()
    {
        _sink ??= new HwndSource(new HwndSourceParameters("WinGetStudioTray") { Width = 0, Height = 0, WindowStyle = unchecked((int)0x80000000) });   // WS_POPUP, mai mostrata
        SetForegroundWindow(_sink.Handle);
        Menu.Placement = PlacementMode.MousePoint;
        Menu.IsOpen = true;
    }

    // Mostra la finestra, sulla scheda chiesta. Con Settings o un dialogo aperti porta in primo
    // piano quello e risponde false: una seconda pagina modale sopra la prima non serve.
    private bool ShowWindow(int? tab)
    {
        if (tab is { } t) _vm.SelectedTab = t;
        _window.Show();
        if (_window.WindowState == WindowState.Minimized) _window.WindowState = WindowState.Normal;
        var modal = _window.OwnedWindows.OfType<Window>().LastOrDefault(w => w.IsVisible);
        (modal ?? _window).Activate();
        return modal is null;
    }

    internal const int BusyFrames = 13;

    // Le icone sono disegnate da src\icon.ps1, sfumate e gia' nei colori dello stato (ADR 0030),
    // a ogni misura dal 100% al 200%: si prende quella dell'area di notifica, senza scalarla.
    // Col nome dell'assembly: vale anche quando l'Application e' quella dei test.
    internal static Drawing.Icon LoadIcon(string name, int size)
    {
        using var stream = Application.GetResourceStream(new Uri($"pack://application:,,,/WinGetStudio;component/Assets/tray/{name}.ico")).Stream;
        return new Drawing.Icon(stream, size, size);
    }

    // La freccia scende solo al lavoro, e mai con gli effetti di animazione di Windows spenti.
    internal static bool Animates(TrayDot dot, bool animationsOn) => dot == TrayDot.Busy && animationsOn;

    public void Dispose()
    {
        _timer.Stop();
        _spin.Stop();
        _icon.Visible = false;
        _icon.Dispose();
        _sink?.Dispose();
        foreach (var i in _icons.Values.Concat(_busy).Distinct()) i.Dispose();
    }

    [DllImport("user32.dll")]
    private static extern bool SetForegroundWindow(nint hwnd);
}
