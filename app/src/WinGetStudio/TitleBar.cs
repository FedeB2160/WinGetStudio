using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Interop;
using System.Windows.Media;

namespace WinGetStudio;

// Barra del titolo nel colore dell'app (ADR 0027), come l'app Impostazioni di Windows: un filo piu'
// chiara dello sfondo nel tema scuro, un filo piu' scura nel chiaro, anche quando Windows colora le
// barre con l'accento. Il bordo resta di Windows. Su Windows 10 i colori DWM non ci sono: la barra
// segue solo la modalita' scura (attributo 20), chiara o scura come lo sfondo.
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

    internal static (Color Caption, Color Text, bool Dark) Colors(Color back)
    {
        var dark = (0.299 * back.R + 0.587 * back.G + 0.114 * back.B) / 255 < 0.5;
        byte Shift(byte c) => dark ? (byte)Math.Round(c + (255 - c) * 0.06) : (byte)Math.Round(c * 0.95);
        return (Color.FromRgb(Shift(back.R), Shift(back.G), Shift(back.B)), dark ? System.Windows.Media.Colors.White : System.Windows.Media.Colors.Black, dark);
    }

    private static void Apply(Window window)
    {
        var back = (Color)window.GetValue(BackProperty);
        var hwnd = new WindowInteropHelper(window).Handle;
        if (back.A == 0 || hwnd == 0) return;
        var (caption, text, dark) = Colors(back);
        // Prima dei colori: su Windows 11 vincono 35/36, su Windows 10 resta solo questo.
        var mode = dark ? 1 : 0;
        _ = DwmSetWindowAttribute(hwnd, DwmwaUseImmersiveDarkMode, ref mode, sizeof(int));
        Set(hwnd, DwmwaCaptionColor, caption);
        Set(hwnd, DwmwaTextColor, text);
    }

    // 20 da Windows 10 2004; prima era 19 (non gestito: il riferimento e' la 22H2).
    private const int DwmwaUseImmersiveDarkMode = 20, DwmwaCaptionColor = 35, DwmwaTextColor = 36;

    // COLORREF: 0x00BBGGRR. L'esito non conta: dove l'attributo non esiste resta la barra di sistema.
    private static void Set(nint hwnd, int attribute, Color c)
    {
        var colorRef = c.R | (c.G << 8) | (c.B << 16);
        _ = DwmSetWindowAttribute(hwnd, attribute, ref colorRef, sizeof(int));
    }

    [DllImport("dwmapi.dll")]
    private static extern int DwmSetWindowAttribute(nint hwnd, int attribute, ref int value, int size);
}
