using System.Diagnostics;
using System.Text;
using WinGetStudio.Core;

namespace WinGetStudio.Core.Tests;

// Esecuzione senza cmd con output su file (ADR 0004, ADR 0025). Processi veri: cmd.exe qui e'
// il programma sotto prova, non una shell fra l'app e winget.
public class ProcessRunnerTests
{
    private static readonly string Cmd = Path.Combine(Environment.SystemDirectory, "cmd.exe");

    // Un figlio staccato eredita il handle dell'output e resta vivo: con una pipe l'EOF non
    // arriverebbe mai (gli spinner eterni della 1.x). L'attesa dipende dal solo processo.
    [Fact]
    public async Task ReturnsWhenTheProcessExitsNotWhenItsChildrenDo()
    {
        var before = Process.GetProcessesByName("PING").Select(p => p.Id).ToHashSet();
        var sw = Stopwatch.StartNew();
        var r = await new ProcessRunner().RunAsync(Cmd, ["/c", "start", "/b", "ping", "-n", "40", "127.0.0.1"]);
        sw.Stop();
        var children = Process.GetProcessesByName("PING").Where(p => !before.Contains(p.Id)).ToList();
        try
        {
            Assert.True(sw.Elapsed < TimeSpan.FromSeconds(15), $"returned after {sw.Elapsed}");
            Assert.Equal(0, r.ExitCode);
            // Se il figlio fosse gia' morto il test non proverebbe nulla.
            Assert.NotEmpty(children);
        }
        finally { foreach (var p in children) p.Kill(); }
    }

    // winget scrive UTF-8: le lettere accentate dei messaggi localizzati devono restare intatte.
    [Fact]
    public async Task OutputIsReadAsUtf8()
    {
        var file = Path.Combine(Path.GetTempPath(), $"wgtest_{Guid.NewGuid():N}.txt");
        File.WriteAllText(file, "Non è stato trovato alcun pacchetto. Èù", new UTF8Encoding(false));
        try
        {
            var r = await new ProcessRunner().RunAsync(Cmd, ["/c", "type", file]);
            Assert.Contains("Non è stato trovato alcun pacchetto. Èù", r.Output);
            Assert.DoesNotContain("Ã", r.Output);
        }
        finally { File.Delete(file); }
    }

    // winget esce con HRESULT negativi: 0x8A15007D = -1978335107.
    [Fact]
    public async Task NegativeExitCodeIsKept() =>
        Assert.Equal(-1978335107, (await new ProcessRunner().RunAsync(Cmd, ["/c", "exit", "-1978335107"])).ExitCode);

    [Fact]
    public async Task StdoutThenStderr()
    {
        var r = await new ProcessRunner().RunAsync(Cmd, ["/c", "echo out& echo err 1>&2"]);
        Assert.Equal("out\r\nerr", r.Output.TrimEnd());
    }

    [Fact]
    public async Task OutputFilesAreRemoved()
    {
        var before = Directory.GetFiles(Path.GetTempPath(), TempFiles.Prefix + "*").ToHashSet();
        await new ProcessRunner().RunAsync(Cmd, ["/c", "echo x"]);
        Assert.DoesNotContain(Directory.GetFiles(Path.GetTempPath(), TempFiles.Prefix + "*"), f => !before.Contains(f));
    }

    // Nessun timeout: gli installer lenti non si troncano, si segnala solo il tempo passato.
    [Fact]
    public async Task TickReportsElapsedTime()
    {
        var ticks = new List<TimeSpan>();
        await new ProcessRunner(TimeSpan.FromMilliseconds(200)).RunAsync(Cmd, ["/c", "ping -n 2 127.0.0.1 >nul"], ticks.Add);
        Assert.NotEmpty(ticks);
    }

    [Fact]
    public async Task MissingExecutableThrows() =>
        await Assert.ThrowsAnyAsync<System.ComponentModel.Win32Exception>(() =>
            new ProcessRunner().RunAsync(Path.Combine(Path.GetTempPath(), "missing-winget.exe"), ["--version"]));
}
