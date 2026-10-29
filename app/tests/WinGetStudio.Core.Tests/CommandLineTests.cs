using System.Runtime.InteropServices;
using WinGetStudio.Core;

namespace WinGetStudio.Core.Tests;

// Argomenti senza shell (ADR 0025): ogni elemento deve arrivare a winget identico, qualunque
// carattere contenga. Si verifica col parser di Windows stesso.
public partial class CommandLineTests
{
    [Theory]
    [InlineData("search")]
    [InlineData("a b")]
    [InlineData("say \"hi\"")]
    [InlineData("x&y")]
    [InlineData("%PATH%")]
    [InlineData("!PATH!")]
    [InlineData(@"ARP\Machine\X64\Android Studio")]
    [InlineData(@"C:\dir with space\")]
    [InlineData(@"a\\""b")]
    [InlineData("")]
    [InlineData("{9D3F0A1C-1234-4C2B-9E3A-0123456789AB}")]
    public void RoundTripsThroughTheWindowsParser(string arg)
    {
        var parsed = Parse("winget.exe " + CommandLine.Join(["first", arg, "last"]));
        Assert.Equal(["winget.exe", "first", arg, "last"], parsed);
    }

    [Fact]
    public void PlainTokensStayUnquoted() =>
        Assert.Equal("search 7zip.7zip --source winget", CommandLine.Join(["search", "7zip.7zip", "--source", "winget"]));

    // Stessa quotatura della 1.x (Invoke-WinGetRead).
    [Fact]
    public void QuotesLikeOneX() =>
        Assert.Equal("search \"a b\" \"say \\\"hi\\\"\" \"x&y\"", CommandLine.Join(["search", "a b", "say \"hi\"", "x&y"]));

    private static string[] Parse(string commandLine)
    {
        var argv = CommandLineToArgvW(commandLine, out var count);
        try
        {
            return Enumerable.Range(0, count).Select(i => Marshal.PtrToStringUni(Marshal.ReadIntPtr(argv, i * IntPtr.Size))!).ToArray();
        }
        finally { LocalFree(argv); }
    }

    [LibraryImport("shell32.dll", StringMarshalling = StringMarshalling.Utf16)]
    private static partial IntPtr CommandLineToArgvW(string lpCmdLine, out int pNumArgs);

    [LibraryImport("kernel32.dll")]
    private static partial IntPtr LocalFree(IntPtr hMem);
}
