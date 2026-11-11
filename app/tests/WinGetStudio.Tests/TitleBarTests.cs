using System.Windows.Media;

namespace WinGetStudio.Tests;

// Barra del titolo (ADR 0027): un filo piu' chiara dello sfondo nel tema scuro, piu' scura nel chiaro.
public class TitleBarTests
{
    [Fact]
    public void DarkBackgroundGetsALighterBarAndWhiteText()
    {
        var (caption, text, dark) = TitleBar.Colors(Color.FromRgb(0x20, 0x20, 0x20));
        Assert.Equal(Color.FromRgb(0x2D, 0x2D, 0x2D), caption);
        Assert.Equal(Colors.White, text);
        Assert.True(dark);
    }

    [Fact]
    public void LightBackgroundGetsADarkerBarAndBlackText()
    {
        var (caption, text, dark) = TitleBar.Colors(Color.FromRgb(0xF3, 0xF3, 0xF3));
        Assert.Equal(Color.FromRgb(0xE7, 0xE7, 0xE7), caption);
        Assert.Equal(Colors.Black, text);
        Assert.False(dark);
    }

    // L'accento di Windows solo col tema System e l'interruttore di Windows acceso.
    [Theory]
    [InlineData(true, true, true)]
    [InlineData(true, false, false)]
    [InlineData(false, true, false)]
    [InlineData(false, false, false)]
    public void SystemAccentOnlyWithSystemThemeAndColorPrevalence(bool themeIsSystem, bool colorPrevalence, bool expected)
    {
        Assert.Equal(expected, TitleBar.UseSystemAccent(themeIsSystem, colorPrevalence));
    }
}
