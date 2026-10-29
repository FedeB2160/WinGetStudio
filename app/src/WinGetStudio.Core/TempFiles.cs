namespace WinGetStudio.Core;

// File di output di ProcessRunner rimasti in %TEMP%. ProcessRunner li cancella da solo, ma un
// installer che lascia un figlio staccato li tiene aperti e la cancellazione puo' fallire.
public static class TempFiles
{
    // Lo stesso prefisso della 1.x: le due versioni puliscono l'una i resti dell'altra.
    public const string Prefix = "wgt_";

    // Best effort: un file ancora in uso resta per il giro dopo.
    public static void Clear(string? directory = null)
    {
        directory ??= Path.GetTempPath();
        foreach (var f in Directory.GetFiles(directory, Prefix + "*"))
            try { File.Delete(f); } catch (IOException) { } catch (UnauthorizedAccessException) { }
        foreach (var d in Directory.GetDirectories(directory, Prefix + "*"))
            try { Directory.Delete(d, true); } catch (IOException) { } catch (UnauthorizedAccessException) { }
    }
}
