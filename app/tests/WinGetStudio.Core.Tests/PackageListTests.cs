using System.Text.Json.Nodes;
using WinGetStudio.Core;

namespace WinGetStudio.Core.Tests;

// File di export/import di winget (App.Backup.ps1 della 1.x): la forma Sources[] -> Packages[]
// si controlla prima di lanciare winget; il file ridotto dell'anteprima tiene per default solo
// Id, versione, canale e ambito, perche' gli argomenti salvati (--custom, --override)
// arriverebbero all'installer da un file che puo' venire da chiunque.
public sealed class PackageListTests : IDisposable
{
    private readonly string _dir = Directory.CreateTempSubdirectory("wgtest_").FullName;

    public void Dispose() => Directory.Delete(_dir, true);

    private string Write(string name, string json)
    {
        var path = Path.Combine(_dir, name);
        File.WriteAllText(path, json);
        return path;
    }

    [Theory]
    [InlineData("one-package", """{"Sources":[{"Packages":[{"PackageIdentifier":"FedeB2160.WinGetStudio"}]}]}""", 1)]
    [InlineData("two-sources", """{"Sources":[{"Packages":[{"PackageIdentifier":"A.A"}]},{"Packages":[{"PackageIdentifier":"B.B"},{"PackageIdentifier":"C.C"}]}]}""", 3)]
    [InlineData("empty-packages", """{"Sources":[{"Packages":[]}]}""", 0)]
    [InlineData("empty-sources", """{"Sources":[]}""", 0)]
    [InlineData("root-array", """[{"Sources":[{"Packages":[{"PackageIdentifier":"A.A"}]}]}]""", null)]
    [InlineData("malformed-json", """{"Sources":[""", null)]
    [InlineData("missing-sources", """{"hello":"world"}""", null)]
    [InlineData("sources-not-array", """{"Sources":{}}""", null)]
    [InlineData("missing-packages", """{"Sources":[{}]}""", null)]
    [InlineData("packages-not-array", """{"Sources":[{"Packages":{"PackageIdentifier":"A.A"}}]}""", null)]
    [InlineData("brackets [x]", """{"Sources":[{"Packages":[{"PackageIdentifier":"A.A"}]}]}""", 1)]
    public void Count(string name, string json, int? expected) =>
        Assert.Equal(expected, PackageList.Load(Write(name + ".json", json))?.Packages.Count);

    [Fact]
    public void MissingFileIsNull() => Assert.Null(PackageList.Load(Path.Combine(_dir, "missing.json")));

    private const string Preview = """
        {"$schema":"https://aka.ms/winget-packages.schema.2.0.json","CreationDate":"2026-10-14",
         "Sources":[
          {"SourceDetails":{"Name":"winget","Identifier":"Microsoft.Winget.Source_8wekyb3d8bbwe","Argument":"https://cdn.winget.microsoft.com/cache","Type":"Microsoft.PreIndexed.Package"},
           "Packages":[{"PackageIdentifier":"7zip.7zip"},{"PackageIdentifier":"Notepad++.Notepad++","Version":"8.9","Custom":"/NoUpdater"}]},
          {"SourceDetails":{"Name":"msstore","Identifier":"StoreEdgeFD","Argument":"https://storeedgefd.dsx.mp.microsoft.com/v9.0","Type":"Microsoft.Rest"},
           "Packages":[{"PackageIdentifier":"9NCBCSZSJRSB"}]}]}
        """;

    // Una riga per pacchetto nell'ordine del file: il sottoinsieme si sceglie per posizione,
    // perche' lo stesso Id puo' stare in due sorgenti.
    [Fact]
    public void PreviewRows()
    {
        var list = PackageList.Load(Write("preview.json", Preview))!;
        Assert.Equal(["7zip.7zip@winget", "Notepad++.Notepad++@winget", "9NCBCSZSJRSB@msstore"], list.Packages.Select(p => $"{p.Id}@{p.Source}"));
        Assert.Equal("8.9", list.Packages[1].Version);
        Assert.Equal(1, list.StoredArguments);
    }

    [Fact]
    public void SubsetKeepingStoredArgumentsDropsEmptySources()
    {
        var list = PackageList.Load(Write("preview.json", Preview))!;
        var sub = JsonNode.Parse(list.Subset([1], keepStoredArguments: true))!;

        var sources = sub["Sources"]!.AsArray();
        Assert.Equal("winget", Assert.Single(sources)!["SourceDetails"]!["Name"]!.GetValue<string>());
        var kept = Assert.Single(sources[0]!["Packages"]!.AsArray())!;
        Assert.Equal("/NoUpdater", kept["Custom"]!.GetValue<string>());
        Assert.Equal("8.9", kept["Version"]!.GetValue<string>());
        Assert.Equal("https://aka.ms/winget-packages.schema.2.0.json", sub["$schema"]!.GetValue<string>());
        // Il file letto non cambia.
        Assert.Equal(2, list.Root["Sources"]![0]!["Packages"]!.AsArray().Count);
    }

    // Per default solo le quattro proprieta' note, e solo quelle presenti: lo schema di winget
    // rifiuta un null.
    [Fact]
    public void SubsetByDefaultKeepsOnlyKnownProperties()
    {
        var list = PackageList.Load(Write("preview.json", Preview))!;
        var text = list.Subset([0, 1], keepStoredArguments: false);
        var packages = JsonNode.Parse(text)!["Sources"]![0]!["Packages"]!.AsArray();

        Assert.Equal(["PackageIdentifier", "PackageIdentifier+Version"],
            packages.Select(p => string.Join('+', p!.AsObject().Select(kv => kv.Key))));
        Assert.DoesNotContain("null", text);
        Assert.DoesNotContain("NoUpdater", text);
        Assert.NotNull(list.Root["Sources"]![0]!["Packages"]![1]!["Custom"]);
    }

    // Il file ridotto va in %TEMP% col prefisso che TempFiles spazza all'avvio, UTF-8 senza BOM.
    [Fact]
    public void WriteSubsetToTemp()
    {
        var list = PackageList.Load(Write("preview.json", Preview))!;
        var path = list.WriteSubset([0], keepStoredArguments: false, _dir);
        Assert.StartsWith(TempFiles.Prefix + "import_", Path.GetFileName(path));
        var bytes = File.ReadAllBytes(path);
        Assert.NotEqual(0xEF, bytes[0]);
        Assert.Single(PackageList.Load(path)!.Packages);
    }
}
