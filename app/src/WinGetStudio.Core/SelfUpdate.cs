using System.ComponentModel;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;
using Microsoft.Win32;

namespace WinGetStudio.Core;

// Come e' arrivata qui questa copia, quindi come si aggiorna (ADR 0013):
//   Source         build di sviluppo (non single-file): niente self-update, si usa git
//   WinGetPortable pacchetto portable di winget: solo winget upgrade
//   Installed      installata col setup: si aggiorna col setup
//   Portable       exe copiato a mano: si rinomina e si sostituisce
public enum InstallChannel { Source, WinGetPortable, Installed, Portable }

// Il file scaricato e verificato, tenuto aperto in sola lettura fino all'avvio (ADR 0024 punto
// 6): nessuno puo' riscriverlo, rinominarlo o cancellarlo fra la verifica e l'esecuzione.
public sealed class VerifiedFile(string path, FileStream handle) : IDisposable
{
    public string Path { get; } = path;
    public void Dispose() => handle.Dispose();
}

public sealed record DownloadResult(VerifiedFile? File, string? Error, bool SignatureRejected = false);

public static partial class SelfUpdate
{
    public const string Repo = "FedeB2160/WinGetStudio";
    // Id nel catalogo winget: l'app si tiene fuori dalla propria lista Updates.
    public const string SelfPackageId = "FedeB2160.WinGetStudio";
    // Voce di disinstallazione del setup (installer\WinGetStudio.iss), nella vista a 32 bit.
    public const string InnoAppId = "{80A0A054-6278-4145-AD5A-2B3C4853019F}";
    public const string SetupAssetName = "WinGetStudio_Setup.exe";
    public const string PortableAssetName = "WinGetStudio.exe";

    // SHA-256 della CHIAVE PUBBLICA di assets\WinGetStudio-codesign.cer (ADR 0022): la chiave e non
    // il thumbprint, cosi' il rinnovo del 2031 con la stessa chiave non chiude fuori nessuno. Lo
    // stesso valore della 1.x; un test lo confronta col file.
    public const string SignerKeySha256 = "C585E5232F0901A3F204EA86B85D30A25ABE0F4833463462A3BDBA59AC753CAA";

    private const int CertEUntrustedRoot = unchecked((int)0x800B0109);

    // Per CONTENUTO: dal catalogo l'Id e' "FedeB2160.WinGetStudio", da un manifest locale winget
    // registra "ARP\User\X64\FedeB2160.WinGetStudio__DefaultSource".
    public static bool IsSelfPackage(string? id) => id?.Contains(SelfPackageId, StringComparison.OrdinalIgnoreCase) == true;

    // exePath null: build di sviluppo. installLocation: InstallLocation del setup, o null.
    public static InstallChannel Channel(string? exePath, string? installLocation)
    {
        if (string.IsNullOrEmpty(exePath)) return InstallChannel.Source;
        if (exePath.Contains(@"\Microsoft\WinGet\Packages\", StringComparison.OrdinalIgnoreCase)) return InstallChannel.WinGetPortable;
        // Cartelle a confronto, non "esiste una voce di disinstallazione": una copia portable su
        // una macchina che ha anche il setup resta portable.
        if (!string.IsNullOrEmpty(installLocation) &&
            string.Equals(System.IO.Path.GetDirectoryName(exePath)?.TrimEnd('\\'), installLocation.TrimEnd('\\'), StringComparison.OrdinalIgnoreCase))
            return InstallChannel.Installed;
        return InstallChannel.Portable;
    }

    // Vista Registry32 esplicita: il setup e' x86 e scrive in WOW6432Node, l'app gira a 64 bit.
    public static string? InstalledLocation()
    {
        try
        {
            using var hklm = RegistryKey.OpenBaseKey(RegistryHive.LocalMachine, RegistryView.Registry32);
            using var k = hklm.OpenSubKey($@"SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\{InnoAppId}_is1");
            return k?.GetValue("InstallLocation") as string;
        }
        catch (Exception e) when (e is System.Security.SecurityException or IOException or UnauthorizedAccessException) { return null; }
    }

    // Cartella del download (ADR 0024 punto 6): l'app non e' elevata e non puo' creare la
    // cartella protetta della 1.x. La protezione la da' il handle tenuto aperto.
    public static string UpdateFolder =>
        System.IO.Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "WinGetStudio", "update");

    // Il file e' firmato con la NOSTRA chiave? result: HRESULT di WinVerifyTrust. Valida (0) dove
    // il .cer e' fra le radici attendibili, CERT_E_UNTRUSTEDROOT altrove (radice self-signed): tutte
    // e due, e solo con la nostra chiave. Ogni altro esito no (firma alterata, nessuna firma...).
    public static bool IsTrustedSigner(int result, byte[]? publicKey) =>
        (result == 0 || result == CertEUntrustedRoot) && publicKey is not null &&
        Convert.ToHexString(SHA256.HashData(publicKey)) == SignerKeySha256;

    // WinVerifyTrust e chiave pubblica del firmatario (null se non firmato).
    public static (int Result, byte[]? PublicKey) CheckSignature(string path)
    {
        byte[]? key = null;
        try
        {
#pragma warning disable SYSLIB0057 // nessun sostituto per il firmatario di un file firmato
            using var cert = X509Certificate.CreateFromSignedFile(path);
#pragma warning restore SYSLIB0057
            key = cert.GetPublicKey();
        }
        catch (CryptographicException) { }
        return (WinVerifyTrust(path), key);
    }

    // Scarica l'asset in UpdateFolder, lo apre in sola lettura e lo verifica: SHA-256 pubblicato
    // (se c'e') e firmatario, sempre. Il file torna aperto; ogni rifiuto lo cancella.
    public static async Task<DownloadResult> DownloadVerifiedAsync(Release release, string? folder = null, HttpClient? http = null)
    {
        folder ??= UpdateFolder;
        var path = System.IO.Path.Combine(folder, release.Name);
        FileStream? handle = null;
        try
        {
            ClearFolder(folder);
            Directory.CreateDirectory(folder);
            await GitHubReleases.DownloadAsync(release.Url!, path, http);
            handle = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read);
            var hash = Convert.ToHexString(await SHA256.HashDataAsync(handle));
            if (release.Sha256 is { } expected && hash != expected.ToUpperInvariant())
                return Reject("checksum mismatch, the download was discarded");
            var (result, key) = CheckSignature(path);
            if (!IsTrustedSigner(result, key))
                return Reject($"the download does not carry the WinGet Studio signature (0x{result:X8}), it was discarded", true);
            return new DownloadResult(new VerifiedFile(path, handle), null);
        }
        catch (Exception e) when (e is HttpRequestException or TaskCanceledException or IOException or UnauthorizedAccessException)
        {
            return Reject(e.Message);
        }

        DownloadResult Reject(string why, bool signature = false)
        {
            handle?.Dispose();
            ClearFolder(folder);
            return new DownloadResult(null, why, signature);
        }
    }

    // Canale Portable: il file in esecuzione non si sovrascrive ma si rinomina. COPIA e non
    // spostamento: la copia prende l'ACL della cartella dell'exe. Poi parte il nuovo exe.
    // null se riuscito, altrimenti il motivo (e l'exe vecchio torna al suo posto).
    public static string? ReplaceAndRestart(VerifiedFile file, string exePath)
    {
        var old = exePath + ".old";
        try
        {
            File.Move(exePath, old, true);
            File.Copy(file.Path, exePath, true);
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException)
        {
            if (!File.Exists(exePath) && File.Exists(old))
                try { File.Move(old, exePath); } catch (IOException) { } catch (UnauthorizedAccessException) { }
            return e.Message;
        }
        try { Process.Start(new ProcessStartInfo(exePath) { UseShellExecute = false })?.Dispose(); }
        catch (Win32Exception e) { return $"updated, but the new version did not start: {e.Message}"; }
        return null;
    }

    // Canale Installed: il setup chiude l'app (Restart Manager), la sostituisce e la riapre.
    // ShellExecute: il manifest del setup chiede l'UAC, CreateProcess fallirebbe con 740.
    public static string? StartSetup(VerifiedFile file, string logPath)
    {
        try
        {
            Process.Start(new ProcessStartInfo(file.Path, $"/SILENT /CLOSEAPPLICATIONS /relaunch=1 \"/LOG={logPath}\"") { UseShellExecute = true })?.Dispose();
            return null;
        }
        catch (Win32Exception e) when (e.NativeErrorCode == 1223) { return "the administrator prompt was declined"; }
        catch (Win32Exception e) { return e.Message; }
    }

    // All'avvio: il .old dell'aggiornamento precedente e la cartella del download. Best effort.
    public static void ClearLeftovers(string? exePath)
    {
        if (exePath is not null)
            try { File.Delete(exePath + ".old"); } catch (IOException) { } catch (UnauthorizedAccessException) { }
        ClearFolder(UpdateFolder);
    }

    private static void ClearFolder(string folder)
    {
        try { if (Directory.Exists(folder)) Directory.Delete(folder, true); }
        catch (IOException) { } catch (UnauthorizedAccessException) { }
    }

    // WinVerifyTrust senza UI, senza controllo di revoca e senza rete: la radice self-signed non
    // ha nulla da controllare (ADR 0022). NON lo stato di una libreria di livello piu' alto: una
    // firma alterata deve dare un codice diverso da quella buona.
    private static unsafe int WinVerifyTrust(string path)
    {
        fixed (char* p = path)
        {
            var file = new WintrustFileInfo { cbStruct = (uint)sizeof(WintrustFileInfo), pcwszFilePath = p };
            var data = new WintrustData
            {
                cbStruct = (uint)sizeof(WintrustData),
                dwUIChoice = 2,         // WTD_UI_NONE
                dwUnionChoice = 1,      // WTD_CHOICE_FILE
                pFile = &file,
                dwProvFlags = 0x1010,   // WTD_REVOCATION_CHECK_NONE | WTD_CACHE_ONLY_URL_RETRIEVAL
            };
            var action = new Guid("00AAC56B-CD44-11d0-8CC2-00C04FC295EE"); // WINTRUST_ACTION_GENERIC_VERIFY_V2
            return WinVerifyTrustNative(0, &action, &data);
        }
    }

    [LibraryImport("wintrust.dll", EntryPoint = "WinVerifyTrust")]
    private static unsafe partial int WinVerifyTrustNative(nint hwnd, Guid* action, WintrustData* data);

    private unsafe struct WintrustFileInfo
    {
        public uint cbStruct;
        public char* pcwszFilePath;
        public nint hFile, pgKnownSubject;
    }

    private unsafe struct WintrustData
    {
        public uint cbStruct;
        public nint pPolicyCallbackData, pSIPClientData;
        public uint dwUIChoice, fdwRevocationChecks, dwUnionChoice;
        public WintrustFileInfo* pFile;
        public uint dwStateAction;
        public nint hWVTStateData, pwszURLReference;
        public uint dwProvFlags, dwUIContext;
        public nint pSignatureSettings;
    }
}
