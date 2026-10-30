using System.Net;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;
using System.Text;
using WinGetStudio.Core;

namespace WinGetStudio.Core.Tests;

// Self-update (ADR 0013, 0022, 0024) e setup di winget (ADR 0019): le regole pagate nella 1.x.
public class SelfUpdateTests
{
    [Theory]
    [InlineData("FedeB2160.WinGetStudio", true)]
    [InlineData(@"ARP\User\X64\FedeB2160.WinGetStudio__DefaultSource", true)]
    [InlineData("fedeb2160.wingetstudio", true)]
    [InlineData("FedeB2160.Other", false)]
    [InlineData("", false)]
    [InlineData(null, false)]
    public void SelfPackageMatchesByContainment(string? id, bool expected) => Assert.Equal(expected, SelfUpdate.IsSelfPackage(id));

    [Theory]
    [InlineData(null, null, InstallChannel.Source)]
    [InlineData(@"C:\Users\u\AppData\Local\Microsoft\WinGet\Packages\FedeB2160.WinGetStudio_x\WinGetStudio.exe", @"C:\Users\u\AppData\Local\Microsoft\WinGet\Packages\FedeB2160.WinGetStudio_x", InstallChannel.WinGetPortable)]
    [InlineData(@"C:\Program Files\WinGet Studio\WinGetStudio.exe", @"c:\program files\winget studio\", InstallChannel.Installed)]
    [InlineData(@"C:\Program Files\WinGet Studio\WinGetStudio.exe", @"C:\Program Files\WinGet Studio", InstallChannel.Installed)]
    // Una copia portable su una macchina che ha anche il setup resta portable.
    [InlineData(@"C:\Tools\WinGetStudio.exe", @"C:\Program Files\WinGet Studio", InstallChannel.Portable)]
    [InlineData(@"C:\Tools\WinGetStudio.exe", null, InstallChannel.Portable)]
    public void ChannelFollowsWhereTheExeIs(string? exe, string? location, InstallChannel expected) =>
        Assert.Equal(expected, SelfUpdate.Channel(exe, location));

    [Theory]
    [InlineData("1.10.0", "1.9.0", true)]
    [InlineData("v2.0.1", "2.0.0", true)]
    [InlineData("v2.0.0", "2.0.0", false)]
    [InlineData("1.12.0", "2.0.0", false)]
    [InlineData("nightly", "2.0.0", false)]
    public void VersionsCompareAsNumbers(string latest, string current, bool expected) => Assert.Equal(expected, GitHubReleases.IsNewer(latest, current));

    [Fact]
    public void ReleasePicksTheAssetByExactName()
    {
        const string json = """
            {"tag_name":"v2.1.0","assets":[
              {"name":"WinGetStudio_Setup.exe","browser_download_url":"https://x/setup","size":2048,"digest":"sha256:abcd"},
              {"name":"WinGetStudio.exe","browser_download_url":"https://x/exe","size":1024}]}
            """;
        var setup = GitHubReleases.Parse(json, SelfUpdate.SetupAssetName)!;
        Assert.Equal(("v2.1.0", "2.1.0", "https://x/setup", 2048L, "ABCD"), (setup.Tag, setup.Version, setup.Url, setup.Size, setup.Sha256));
        var exe = GitHubReleases.Parse(json, SelfUpdate.PortableAssetName)!;
        Assert.Equal(("https://x/exe", (string?)null), (exe.Url, exe.Sha256));
        // Release senza l'asset: torna, con Url vuoto, perche' il controllo manuale lo dica.
        var missing = GitHubReleases.Parse(json, "Other.exe")!;
        Assert.Equal(("v2.1.0", (string?)null), (missing.Tag, missing.Url));
        Assert.Null(GitHubReleases.Parse("{}", "x"));
    }

    // Il valore scritto nel codice e' la chiave del .cer del repo: l'exe non porta il file.
    [Fact]
    public void SignerKeyIsTheKeyOfTheRepositoryCertificate()
    {
        var dir = new DirectoryInfo(AppContext.BaseDirectory);
        while (dir is not null && !File.Exists(Path.Combine(dir.FullName, "assets", "WinGetStudio-codesign.cer"))) dir = dir.Parent;
        Assert.NotNull(dir);
        using var cert = X509CertificateLoader.LoadCertificateFromFile(Path.Combine(dir.FullName, "assets", "WinGetStudio-codesign.cer"));
        Assert.Equal(SelfUpdate.SignerKeySha256, Convert.ToHexString(SHA256.HashData(cert.GetPublicKey())));
        Assert.True(SelfUpdate.IsTrustedSigner(0, cert.GetPublicKey()));
        // CERT_E_UNTRUSTEDROOT: tutto verificato, radice self-signed non importata (ADR 0012).
        Assert.True(SelfUpdate.IsTrustedSigner(unchecked((int)0x800B0109), cert.GetPublicKey()));
        // Firma alterata, digest sbagliato, nessuna firma: rifiutati anche con la nostra chiave.
        foreach (var bad in new[] { 0x80096010, 0x800B0100, 0x80096004, 0x800B0101 })
            Assert.False(SelfUpdate.IsTrustedSigner(unchecked((int)bad), cert.GetPublicKey()));
        Assert.False(SelfUpdate.IsTrustedSigner(0, [1, 2, 3]));
        Assert.False(SelfUpdate.IsTrustedSigner(0, null));
    }

    // cmd.exe e' firmato da Microsoft via catalogo: per WinVerifyTrust sul file non e' firmato.
    [Fact]
    public void RealFilesWithoutOurSignatureAreRefused()
    {
        var cmd = SelfUpdate.CheckSignature(Path.Combine(Environment.SystemDirectory, "cmd.exe"));
        Assert.False(SelfUpdate.IsTrustedSigner(cmd.Result, cmd.PublicKey));
        var text = Path.GetTempFileName();
        try
        {
            File.WriteAllText(text, "not signed");
            var t = SelfUpdate.CheckSignature(text);
            Assert.NotEqual(0, t.Result);
            Assert.Null(t.PublicKey);
        }
        finally { File.Delete(text); }
    }

    [Fact]
    public async Task DownloadIsCheckedAndDiscarded()
    {
        var body = Encoding.ASCII.GetBytes("MZ fake exe");
        using var http = new HttpClient(new StaticHandler(body));
        var folder = Path.Combine(Path.GetTempPath(), $"wgt_test_{Guid.NewGuid():N}");
        try
        {
            var wrongHash = await SelfUpdate.DownloadVerifiedAsync(new Release("v9.0.0", "9.0.0", "WinGetStudio.exe", "https://x/exe", body.Length, "00"), folder, http);
            Assert.Equal(("checksum mismatch, the download was discarded", false), (wrongHash.Error, wrongHash.SignatureRejected));
            Assert.False(Directory.Exists(folder));

            // Hash giusto, firma assente: rifiutato lo stesso (ADR 0022).
            var unsigned = await SelfUpdate.DownloadVerifiedAsync(new Release("v9.0.0", "9.0.0", "WinGetStudio.exe", "https://x/exe", body.Length, Convert.ToHexString(SHA256.HashData(body))), folder, http);
            Assert.True(unsigned.SignatureRejected);
            Assert.Null(unsigned.File);
            Assert.False(Directory.Exists(folder));
        }
        finally { if (Directory.Exists(folder)) Directory.Delete(folder, true); }
    }

    // Il file verificato resta aperto in sola lettura: nessuno lo riscrive prima dell'avvio, ma
    // si legge e si copia (ADR 0024 punto 6).
    [Fact]
    public void VerifiedFileCannotBeRewrittenButCanBeCopied()
    {
        var dir = Directory.CreateTempSubdirectory("wgt_test_").FullName;
        try
        {
            var path = Path.Combine(dir, "a.exe");
            File.WriteAllText(path, "x");
            using (var f = new VerifiedFile(path, new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read)))
            {
                Assert.Throws<IOException>(() => File.WriteAllText(path, "y"));
                Assert.Throws<IOException>(() => File.Move(path, path + ".2"));
                File.Copy(path, Path.Combine(dir, "b.exe"));
            }
            File.WriteAllText(path, "y");
        }
        finally { Directory.Delete(dir, true); }
    }

    [Theory]
    [InlineData(true, null, null, true)]
    [InlineData(false, null, null, false)]
    [InlineData(true, 1, null, false)]
    [InlineData(true, null, 2, false)]
    [InlineData(true, 0, 4, true)]
    public void StoreUpdatesWinGetOnlyWhenFreeTo(bool hasStore, int? remove, int? autoDownload, bool expected) =>
        Assert.Equal(expected, WinGetSetup.StoreUpdatesWinGet(hasStore, remove, autoDownload));

    [Fact]
    public void DependenciesAreThoseOfThisArchitecture()
    {
        var dir = Directory.CreateTempSubdirectory("wgt_test_").FullName;
        try
        {
            foreach (var a in new[] { "x64", "arm64", "x86" })
            {
                Directory.CreateDirectory(Path.Combine(dir, "deep", a));
                File.WriteAllText(Path.Combine(dir, "deep", a, $"VCLibs_{a}.appx"), "");
            }
            Assert.Equal(["VCLibs_x64.appx"], WinGetSetup.DependencyFiles(dir, Architecture.X64).Select(Path.GetFileName));
            Assert.Equal(["VCLibs_arm64.appx"], WinGetSetup.DependencyFiles(dir, Architecture.Arm64).Select(Path.GetFileName));
            Assert.Throws<InvalidOperationException>(() => WinGetSetup.DependencyFiles(dir, Architecture.Wasm));
        }
        finally { Directory.Delete(dir, true); }
    }

    // Un nome utente con un apice (o un apice tipografico) non chiude la stringa PowerShell.
    [Fact]
    public void PowerShellPathsAreQuoted()
    {
        Assert.Equal("'C:\\Users\\O''Brien\\a.msixbundle'", WinGetSetup.PsQuote(@"C:\Users\O'Brien\a.msixbundle"));
        Assert.Equal("'a\u2019\u2019b'", WinGetSetup.PsQuote("a\u2019b"));
        Assert.Equal("Add-AppxPackage -Path 'b' -DependencyPath @('d1','d2') -DeferRegistrationWhenPackagesAreInUse",
            WinGetSetup.InstallScript("b", ["d1", "d2"]));
    }

    private sealed class StaticHandler(byte[] body) : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken) =>
            Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK) { Content = new ByteArrayContent(body) });
    }
}
