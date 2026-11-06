using WinGetStudio.ViewModels;

namespace WinGetStudio.Tests;

// Dettagli letti per posizione (ADR 0021): etichetta e valore al primo ": ", mai per nome
// dell'etichetta, che winget traduce. Testo vero di winget in italiano, accorciato.
public class PackageDetailsTests
{
    [Fact]
    public void ParsesShowOutputByPosition()
    {
        var d = PackageDetails.Parse("7-Zip",
            "Trovato 7-Zip [7zip.7zip]\r\nVersione: 26.05\r\nURL editore: https://7-zip.org/\r\nTag:\r\n  7zfiles\r\n  archive\r\n" +
            "Note sulla versione:\r\n  - Some bugs were fixed.\r\nProgramma di installazione:\r\n  Tipo di programma di installazione: wix\r\n  Data di rilascio: 2026-10-21")!;

        var part = Assert.Single(d.Parts);
        Assert.Equal("Trovato 7-Zip [7zip.7zip]", part.Heading);
        Assert.Equal(
        [
            new DetailsRow("Versione", "26.05"),
            new DetailsRow("URL editore", "https://7-zip.org/"),
            new DetailsRow("Tag", "7zfiles\narchive"),
            new DetailsRow("Note sulla versione", "- Some bugs were fixed."),
            new DetailsRow("Programma di installazione", "Tipo di programma di installazione: wix\nData di rilascio: 2026-10-21"),
        ], part.Rows);
    }

    [Fact]
    public void TwoPartsAtTheEmptyLine()
    {
        var d = PackageDetails.Parse("7-Zip",
            "7-Zip 26.05 (x64) [7zip.7zip]\r\nVersione: 26.05\r\nAmbito installazione: Machine\r\n\r\nTrovato 7-Zip [7zip.7zip]\r\nVersione: 26.05")!;

        Assert.Equal(["7-Zip 26.05 (x64) [7zip.7zip]", "Trovato 7-Zip [7zip.7zip]"], d.Parts.Select(p => p.Heading));
        Assert.Equal(2, d.Parts[0].Rows.Count);
    }

    // Un nome col ": " resta il titolo della parte, non diventa un'etichetta.
    [Fact]
    public void OpeningLineIsAlwaysTheHeading()
    {
        var part = Assert.Single(PackageDetails.Parse("Foo: Bar", "Found Foo: Bar [F.B]\r\nVersion: 1")!.Parts);
        Assert.Equal("Found Foo: Bar [F.B]", part.Heading);
        Assert.Equal([new DetailsRow("Version", "1")], part.Rows);
    }

    [Fact]
    public void LineWithoutLabelSpansTheRow()
    {
        var part = Assert.Single(PackageDetails.Parse("X", "Found X [x]\r\nVersion: 1\r\nA note")!.Parts);
        Assert.Equal(new DetailsRow("", "A note"), part.Rows[1]);
    }

    // Nessuna riga "etichetta: valore" (un errore, un winget vecchio): il testo si mostra com'e'.
    [Theory]
    [InlineData("No installed package found matching input criteria.")]
    [InlineData("")]
    [InlineData("winget returned no details for this package.")]
    public void TextWithoutLabelsIsNull(string text) => Assert.Null(PackageDetails.Parse("X", text));
}
