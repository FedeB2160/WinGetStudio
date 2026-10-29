using WinGetStudio.Core;

namespace WinGetStudio.Core.Tests;

// Un installer che lascia un figlio staccato tiene aperti i file di output: la cancellazione
// fallisce e i file restano. Si tolgono all'avvio, quando nessuno li tiene piu'.
public class TempFilesTests
{
    [Fact]
    public void ClearRemovesOnlyLeftovers()
    {
        var dir = Directory.CreateTempSubdirectory("wgtest_").FullName;
        try
        {
            var stale = Path.Combine(dir, TempFiles.Prefix + "1.out");
            var keep = Path.Combine(dir, "wgtkeep.txt");
            var staleDir = Path.Combine(dir, TempFiles.Prefix + "download");
            File.WriteAllText(stale, "x");
            File.WriteAllText(keep, "x");
            Directory.CreateDirectory(Path.Combine(staleDir, "deps"));
            File.WriteAllText(Path.Combine(staleDir, "deps", "x.appx"), "x");

            TempFiles.Clear(dir);

            Assert.False(File.Exists(stale));
            Assert.False(Directory.Exists(staleDir));
            Assert.True(File.Exists(keep));
        }
        finally { Directory.Delete(dir, true); }
    }

    [Fact]
    public void FileInUseStaysForNextTime()
    {
        var dir = Directory.CreateTempSubdirectory("wgtest_").FullName;
        try
        {
            var busy = Path.Combine(dir, TempFiles.Prefix + "busy.out");
            using (File.Open(busy, FileMode.Create, FileAccess.Write, FileShare.None))
                TempFiles.Clear(dir);
            Assert.True(File.Exists(busy));
        }
        finally { Directory.Delete(dir, true); }
    }
}
