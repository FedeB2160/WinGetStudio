using System.IO.Compression;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using Microsoft.Win32;

namespace WinGetStudio.Core;

// winget stesso (ADR 0019): installarlo quando manca, aggiornarlo dove non ci pensa lo Store.
public static class WinGetSetup
{
    public const string Repo = "microsoft/winget-cli";
    public const string BundleAsset = "Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle";
    public const string DependenciesAsset = "DesktopAppInstaller_Dependencies.zip";

    // Lo Store aggiorna App Installer da solo, a delta: se c'e' ed e' libero di farlo il pulsante
    // (oltre 300 MB da GitHub) non serve. Su un PC gestito puo' esserci con gli aggiornamenti
    // spenti (AutoDownload=2) o bloccato (RemoveWindowsStore=1).
    public static bool StoreUpdatesWinGet(bool hasStore, int? removeWindowsStore, int? autoDownload) =>
        hasStore && removeWindowsStore != 1 && autoDownload != 2;

    public static bool StoreUpdatesWinGet()
    {
        try
        {
            // I pacchetti registrati per QUESTO account: niente proiezione WinRT per una lettura.
            using var repo = Registry.CurrentUser.OpenSubKey(@"Software\Classes\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppModel\Repository\Packages");
            var hasStore = repo?.GetSubKeyNames().Any(n => n.StartsWith("Microsoft.WindowsStore_", StringComparison.OrdinalIgnoreCase)) == true;
            using var policy = Registry.LocalMachine.OpenSubKey(@"SOFTWARE\Policies\Microsoft\WindowsStore");
            return StoreUpdatesWinGet(hasStore, policy?.GetValue("RemoveWindowsStore") as int?, policy?.GetValue("AutoDownload") as int?);
        }
        catch (Exception e) when (e is System.Security.SecurityException or IOException or UnauthorizedAccessException) { return false; }
    }

    // Pacchetti di dipendenza per l'architettura di questo Windows: lo zip ha una cartella per
    // architettura, cercata a qualunque profondita' (la struttura e' gia' cambiata in passato).
    public static IReadOnlyList<string> DependencyFiles(string dir, Architecture arch)
    {
        var folder = arch switch { Architecture.X64 => "x64", Architecture.Arm64 => "arm64", Architecture.X86 => "x86", _ => null };
        var files = folder is null ? [] : Directory.GetFiles(dir, "*", SearchOption.AllDirectories)
            .Where(f => string.Equals(Path.GetFileName(Path.GetDirectoryName(f)), folder, StringComparison.OrdinalIgnoreCase)).ToList();
        if (files.Count == 0) throw new InvalidOperationException($"the winget release has no dependencies for architecture '{arch}'");
        return files;
    }

    // Stringa PowerShell fra apici singoli: si raddoppia l'apice, anche nelle varianti
    // tipografiche che PowerShell tratta come apici.
    public static string PsQuote(string s)
    {
        var b = new StringBuilder("'");
        foreach (var c in s) { if (c is '\'' or '‘' or '’' or '‚' or '‛') b.Append(c); b.Append(c); }
        return b.Append('\'').ToString();
    }

    // Add-AppxPackage per QUESTO account. Registrazione rinviata e non chiusura forzata: un
    // winget aperto in un terminale passa alla versione nuova quando si chiude.
    public static string InstallScript(string bundle, IEnumerable<string> dependencies) =>
        $"Add-AppxPackage -Path {PsQuote(bundle)} -DependencyPath @({string.Join(",", dependencies.Select(PsQuote))}) -DeferRegistrationWhenPackagesAreInUse";

    // Procedura Microsoft per un App Installer presente ma non registrato per l'account.
    public const string RegisterScript = "Add-AppxPackage -RegisterByFamilyName -MainPackage Microsoft.DesktopAppInstaller_8wekyb3d8bbwe";

    // Installa (register: prima prova a registrare quello di Windows, secondi e nessun download)
    // o aggiorna winget. null se riuscito, altrimenti il motivo.
    public static async Task<string?> InstallAsync(bool register, Action<string> log, IProcessRunner? runner = null, HttpClient? http = null)
    {
        runner ??= new ProcessRunner();
        if (register)
        {
            log("   Registering the App Installer that comes with Windows...");
            // Se non c'e' fallisce, e si passa al download.
            await RunPowerShellAsync(runner, RegisterScript);
            if (WinGetCli.FindWinGet() is not null) return null;
        }
        // Prefisso wgt_: se il processo muore a meta', la cartella la spazza TempFiles.Clear.
        var dir = Path.Combine(Path.GetTempPath(), TempFiles.Prefix + "winget");
        try
        {
            Directory.CreateDirectory(dir);
            var files = new List<string>();
            foreach (var asset in new[] { BundleAsset, DependenciesAsset })
            {
                var rel = await GitHubReleases.GetLatestAsync(Repo, asset, http);
                // Senza checksum non si scarica nemmeno.
                if (rel?.Url is null || rel.Sha256 is null) return $"the latest winget release on GitHub has no verifiable {asset}";
                log($"   Downloading {asset} ({rel.Size / (1024 * 1024)} MB, winget {rel.Tag})...");
                var dest = Path.Combine(dir, asset);
                File.Delete(dest);
                await GitHubReleases.DownloadAsync(rel.Url, dest, http);
                log($"   Verifying {asset}...");
                await using (var read = File.OpenRead(dest))
                    if (Convert.ToHexString(await SHA256.HashDataAsync(read)) != rel.Sha256) return $"checksum mismatch for {asset}: the download was discarded";
                files.Add(dest);
            }
            log("   Unpacking the dependencies...");
            var deps = Path.Combine(dir, "deps");
            ZipFile.ExtractToDirectory(files[1], deps, true);
            log("   Installing App Installer...");
            var r = await RunPowerShellAsync(runner, InstallScript(files[0], DependencyFiles(deps, RuntimeInformation.OSArchitecture)));
            return r.ExitCode == 0 ? null : $"Add-AppxPackage failed: {string.Join(' ', WinGetTable.OutputTail(r.Output))}";
        }
        catch (Exception e) when (e is HttpRequestException or TaskCanceledException or IOException or UnauthorizedAccessException or InvalidDataException or InvalidOperationException)
        {
            return e.Message;
        }
        finally
        {
            try { Directory.Delete(dir, true); } catch (IOException) { } catch (UnauthorizedAccessException) { }
        }
    }

    // Add-AppxPackage esiste solo come cmdlet: Windows PowerShell per percorso completo, script in
    // -EncodedCommand (nessuna quotatura sulla riga di comando), uscita 1 su qualunque errore.
    private static Task<ProcessResult> RunPowerShellAsync(IProcessRunner runner, string script)
    {
        var full = $"$ErrorActionPreference = 'Stop'; try {{ {script} }} catch {{ [Console]::Error.WriteLine($_.Exception.Message); exit 1 }}";
        var exe = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), @"WindowsPowerShell\v1.0\powershell.exe");
        return runner.RunAsync(exe, ["-NoProfile", "-NonInteractive", "-EncodedCommand", Convert.ToBase64String(Encoding.Unicode.GetBytes(full))]);
    }
}
