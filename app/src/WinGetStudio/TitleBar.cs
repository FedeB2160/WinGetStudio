using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Interop;
using System.Windows.Media;
using Microsoft.Win32;

namespace WinGetStudio;

// Barra del titolo (ADR 0027). Light e Dark: nel colore dell'app, come l'app Impostazioni di Windows,
// un filo piu' chiara dello sfondo nel tema scuro, un filo piu' scura nel chiaro, anche quando Windows
// colora le barre con l'accento; il bordo resta di Windows. System: se in Windows e' attivo "Mostra il
// colore principale sulle barre dei titoli e sui bordi delle finestre", barra, testo e bordo tornano a
// Windows, che li disegna con l'accento; se no come Light/Dark. Su Windows 10 i colori DWM non ci sono:
// la barra segue solo la modalita' scura (attributo 20), e con l'interruttore attivo resta l'accento.
internal static class TitleBar
{
    // Lo sfondo della finestra del tema corrente: cambia col tema, e col tema si ricolora la barra.
    private static readonly DependencyProperty BackProperty = DependencyProperty.RegisterAttached(
        "TitleBarBack", typeof(Color), typeof(TitleBar), new PropertyMetadata(default(Color), (d, _) => Apply((Window)d)));

    public static void Follow(Window window)
    {
        window.SetResourceReference(BackProperty, "SolidBackgroundFillColorBase");
        window.SourceInitialized += (_, _) => Apply(window);
    }

    // Da System a Light lo sfondo puo' restare uguale, e l'interruttore di Windows non tocca lo sfondo:
    // in quei casi l'aggancio alla risorsa non scatta e si riapplica a mano.
    public static void ApplyAll()
    {
        foreach (var window in Application.Current.Windows.OfType<Window>()) Apply(window);
    }

    internal static (Color Caption, Color Text, bool Dark) Colors(Color back)
    {
        var dark = (0.299 * back.R + 0.587 * back.G + 0.114 * back.B) / 255 < 0.5;
        byte Shift(byte c) => dark ? (byte)Math.Round(c + (255 - c) * 0.06) : (byte)Math.Round(c * 0.95);
        return (Color.FromRgb(Shift(back.R), Shift(back.G), Shift(back.B)), dark ? System.Windows.Media.Colors.White : System.Windows.Media.Colors.Black, dark);
    }

    internal static bool UseSystemAccent(bool themeIsSystem, bool colorPrevalence) => themeIsSystem && colorPrevalence;

    private static void Apply(Window window)
    {
        var back = (Color)window.GetValue(BackProperty);
        var hwnd = new WindowInteropHelper(window).Handle;
        if (back.A == 0 || hwnd == 0) return;
        var (caption, text, dark) = Colors(back);
        // Prima dei colori: su Windows 11 vincono 35/36, su Windows 10 resta solo questo.
        var mode = dark ? 1 : 0;
        _ = DwmSetWindowAttribute(hwnd, DwmwaUseImmersiveDarkMode, ref mode, sizeof(int));
        if (UseSystemAccent(Application.Current.ThemeMode == ThemeMode.System, ColorPrevalence()))
        {
            // DWMWA_COLOR_DEFAULT: Windows ridisegna da se' l'accento, finestra inattiva compresa.
            var systemColor = DwmwaColorDefault;
            foreach (var attribute in new[] { DwmwaBorderColor, DwmwaCaptionColor, DwmwaTextColor })
                _ = DwmSetWindowAttribute(hwnd, attribute, ref systemColor, sizeof(int));
            return;
        }
        Set(hwnd, DwmwaCaptionColor, caption);
        Set(hwnd, DwmwaTextColor, text);
    }

    // L'interruttore di Windows; assente o illeggibile vale spento.
    private static bool ColorPrevalence()
    {
        try
        {
            return Registry.GetValue(@"HKEY_CURRENT_USER\Software\Microsoft\Windows\DWM", "ColorPrevalence", 0) is int value && value == 1;
        }
        catch (Exception)
        {
            return false;
        }
    }

    // 20 da Windows 10 2004; prima era 19 (non gestito: il riferimento e' la 22H2).
    private const int DwmwaUseImmersiveDarkMode = 20, DwmwaBorderColor = 34, DwmwaCaptionColor = 35, DwmwaTextColor = 36;
    private const int DwmwaColorDefault = unchecked((int)0xFFFFFFFF);

    // COLORREF: 0x00BBGGRR. L'esito non conta: dove l'attributo non esiste resta la barra di sistema.
    private static void Set(nint hwnd, int attribute, Color c)
    {
        var colorRef = c.R | (c.G << 8) | (c.B << 16);
        _ = DwmSetWindowAttribute(hwnd, attribute, ref colorRef, sizeof(int));
    }

    [DllImport("dwmapi.dll")]
    private static extern int DwmSetWindowAttribute(nint hwnd, int attribute, ref int value, int size);
}
