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
    private readonly DispatcherTimer _timer = new();

    public TrayIcon(MainViewModel vm, MainWindow window, Action exit)
    {
        _vm = vm;
        _window = window;
        _icons = DrawIcons();
        Menu = BuildMenu(exit);
        Update();
        vm.Tray.PropertyChanged += (_, _) => Update();
        vm.Tray.Notify += (title, text) =>
        {
            // Un fumetto senza testo lancia un'eccezione: il titolo diventa il testo.
            if (text.Length == 0) _icon.ShowBalloonTip(5000, "WinGet Studio", title, Forms.ToolTipIcon.None);
            else _icon.ShowBalloonTip(5000, title, text, Forms.ToolTipIcon.None);
        };
        _icon.BalloonTipClicked += (_, _) => ShowWindow(MainViewModel.UpdatesTab);
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
        _icon.Icon = _icons[_vm.Tray.Dot];
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

    // Il frame dell'icona alla misura dell'area di notifica (16 px al 100%), senza scalarlo: e' gia'
    // disegnato sulla griglia dei pixel (ADR 0017). Lo stato colora il badge, freccia compresa.
    internal static Dictionary<TrayDot, Drawing.Icon> DrawIcons()
    {
        var size = Forms.SystemInformation.SmallIconSize;
        // Col nome dell'assembly: vale anche quando l'Application e' quella dei test.
        using var stream = Application.GetResourceStream(new Uri("pack://application:,,,/WinGetStudio;component/Assets/icon.ico")).Stream;
        using var app = new Drawing.Icon(stream, size);
        using var frame = app.ToBitmap();
        Drawing.Color white = Drawing.Color.White, dark = Drawing.Color.FromArgb(0x1A, 0x1A, 0x1A);
        return new Dictionary<TrayDot, Drawing.Icon>
        {
            // Il blu del badge e' gia' quello dell'icona.
            [TrayDot.Idle] = Recolor(frame, Drawing.Color.FromArgb(0x00, 0x78, 0xD4), white),
            [TrayDot.Updates] = Recolor(frame, Drawing.Color.FromArgb(0x13, 0xA1, 0x0E), white),
            [TrayDot.Errors] = Recolor(frame, Drawing.Color.FromArgb(0xE8, 0x11, 0x23), white),
            // Sul giallo la freccia bianca non si legge: scura, come nei segnali di attenzione di Windows.
            [TrayDot.Busy] = Recolor(frame, Drawing.Color.FromArgb(0xFF, 0xB9, 0x00), dark),
        };
    }

    // I pixel del badge sono il blu 0078D4 mescolato al bianco della freccia: quanto blu c'e' si legge
    // dal rosso (0 nel blu, 255 nel bianco) e si rimescola coi colori nuovi. Il cartone (rosso alto,
    // blu basso) e la trasparenza non cambiano.
    private static Drawing.Icon Recolor(Drawing.Bitmap frame, Drawing.Color badge, Drawing.Color arrow)
    {
        using var bitmap = new Drawing.Bitmap(frame);
        for (var y = 0; y < bitmap.Height; y++)
            for (var x = 0; x < bitmap.Width; x++)
            {
                var p = bitmap.GetPixel(x, y);
                // Blu del badge, o bianco della freccia (nell'icona c'e' solo li').
                if (p.A == 0 || (p.B - p.R < 20 && Math.Min(p.R, Math.Min(p.G, p.B)) <= 200)) continue;
                var k = (255 - p.R) / 255f;
                int Mix(int a, int b) => (int)Math.Round(a * (1 - k) + b * k);
                bitmap.SetPixel(x, y, Drawing.Color.FromArgb(p.A, Mix(arrow.R, badge.R), Mix(arrow.G, badge.G), Mix(arrow.B, badge.B)));
            }
        return Drawing.Icon.FromHandle(bitmap.GetHicon());
    }

    public void Dispose()
    {
        _timer.Stop();
        _icon.Visible = false;
        _icon.Dispose();
        _sink?.Dispose();
        foreach (var i in _icons.Values)
        {
            DestroyIcon(i.Handle);
            i.Dispose();
        }
    }

    [DllImport("user32.dll")]
    private static extern bool SetForegroundWindow(nint hwnd);

    [DllImport("user32.dll")]
    private static extern bool DestroyIcon(nint icon);
}
