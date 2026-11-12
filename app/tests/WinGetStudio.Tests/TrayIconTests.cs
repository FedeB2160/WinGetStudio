using WinGetStudio.ViewModels;

namespace WinGetStudio.Tests;

// Le icone dell'area di notifica generate da src\icon.ps1 (ADR 0030): ogni stato e ogni
// fotogramma alla misura che Windows chiede, e la freccia che scende solo al lavoro.
public class TrayIconTests
{
    // Il protocollo pack: lo registra WPF al primo uso; qui nessuna Application lo ha ancora fatto.
    public TrayIconTests() => _ = System.IO.Packaging.PackUriHelper.UriSchemePack;

    public static readonly string[] Names =
        ["idle", "updates", "errors", .. Enumerable.Range(1, TrayIcon.BusyFrames).Select(n => $"busy-{n:D2}")];

    [Theory]
    [InlineData(16)]
    [InlineData(20)]
    [InlineData(24)]
    [InlineData(32)]
    public void EveryTrayIconHasTheSize(int size)
    {
        foreach (var name in Names)
        {
            using var icon = TrayIcon.LoadIcon(name, size);
            Assert.Equal(size, icon.Width);
        }
    }

    [Theory]
    [InlineData(TrayDot.Idle, true)]
    [InlineData(TrayDot.Idle, false)]
    [InlineData(TrayDot.Updates, true)]
    [InlineData(TrayDot.Updates, false)]
    [InlineData(TrayDot.Errors, true)]
    [InlineData(TrayDot.Errors, false)]
    [InlineData(TrayDot.Busy, true)]
    [InlineData(TrayDot.Busy, false)]
    public void OnlyBusyAnimatesAndOnlyWithAnimationsOn(TrayDot dot, bool on) =>
        Assert.Equal(dot == TrayDot.Busy && on, TrayIcon.Animates(dot, on));
}
