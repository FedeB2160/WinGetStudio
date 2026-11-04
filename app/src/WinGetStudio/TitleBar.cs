using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Interop;
using System.Windows.Media;

namespace WinGetStudio;

// Barra del titolo nel colore dell'app (ADR 0027), come l'app Impostazioni di Windows: un filo piu'
// chiara dello sfondo nel tema scuro, un filo piu' scura nel chiaro, anche quando Windows colora le
// barre con l'accento. Il bordo resta di Windows. Su Windows 10 l'attributo DWM non c'e': nessun effetto.
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

    internal static (Color Caption, Color Text) Colors(Color back)
    {
        var dark = (0.299 * back.R + 0.587 * back.G + 0.114 * back.B) / 255 < 0.5;
        byte Shift(byte c) => dark ? (byte)Math.Round(c + (255 - c) * 0.06) : (byte)Math.Round(c * 0.95);
        return (Color.FromRgb(Shift(back.R), Shift(back.G), Shift(back.B)), dark ? System.Windows.Media.Colors.White : System.Windows.Media.Colors.Black);
    }

    private static void Apply(Window window)
    {
        var back = (Color)window.GetValue(BackProperty);
        var hwnd = new WindowInteropHelper(window).Handle;
        if (back.A == 0 || hwnd == 0) return;
        var (caption, text) = Colors(back);
        Set(hwnd, DwmwaCaptionColor, caption);
        Set(hwnd, DwmwaTextColor, text);
    }

    private const int DwmwaCaptionColor = 35, DwmwaTextColor = 36;

    // COLORREF: 0x00BBGGRR. L'esito non conta: dove l'attributo non esiste resta la barra di sistema.
    private static void Set(nint hwnd, int attribute, Color c)
    {
        var colorRef = c.R | (c.G << 8) | (c.B << 16);
        _ = DwmSetWindowAttribute(hwnd, attribute, ref colorRef, sizeof(int));
    }

    [DllImport("dwmapi.dll")]
    private static extern int DwmSetWindowAttribute(nint hwnd, int attribute, ref int value, int size);
}
