using WinGetStudio.Core;
using WinGetStudio.ViewModels;

namespace WinGetStudio.Tests;

// Dettagli letti per posizione (ADR 0021): etichetta e valore al primo ": ", mai per nome
// dell'etichetta, che winget traduce. Testo vero di winget in italiano, accorciato.
public class PackageDetailsTests
{
    private const string Show =
        "Trovato 7-Zip [7zip.7zip]\r\nVersione: 26.05\r\nURL editore: https://7-zip.org/\r\nTag:\r\n  7zfiles\r\n  archive\r\n" +
        "Note sulla versione:\r\n  - Some bugs were fixed.\r\n  - Faster.\r\nProgramma di installazione:\r\n  Tipo di programma di installazione: wix\r\n  Data di rilascio: 2026-10-21";

    private const string List =
        "7-Zip 26.05 (x64) [7zip.7zip]\r\nVersione: 26.05\r\nAmbito installazione: Machine\r\nAggiornamenti disponibili:\r\n  winget [26.06]";

    [Fact]
    public void ParsesShowOutputByPosition()
    {
        var d = PackageDetails.Parse("7-Zip", "7zip.7zip", new DetailsReads("", Show), "winget")!;

        Assert.Equal(("7-Zip", "7zip.7zip"), (d.Name, d.Id));
        var part = Assert.Single(d.Parts);
        // La riga d'apertura di winget non si mostra: nome e Id stanno gia' nel titolo.
        Assert.Equal("Catalog (winget)", part.Title);
        Assert.Equal(
        [
            new DetailsRow("Versione", "26.05"),
            new DetailsRow("URL editore", "https://7-zip.org/"),
            // Parole senza spazi una per riga (i tag): in fila, con le virgole.
            new DetailsRow("Tag", "7zfiles, archive"),
            new DetailsRow("Note sulla versione", "- Some bugs were fixed.\n- Faster."),
            // Un gruppo di coppie (l'installer): il titolo, poi le sue righe rientrate.
            new DetailsRow("Programma di installazione", ""),
            new DetailsRow("Tipo di programma di installazione", "wix", Nested: true),
            new DetailsRow("Data di rilascio", "2026-10-21", Nested: true),
        ], part.Rows);
    }

    // Prima il catalogo (cos'e' il pacchetto), poi cio' che e' installato (dove e come).
    [Fact]
    public void CatalogComesBeforeInstalled()
    {
        var d = PackageDetails.Parse("7-Zip", "7zip.7zip", new DetailsReads(List, Show), "winget")!;

        Assert.Equal(["Catalog (winget)", "Installed"], d.Parts.Select(p => p.Title));
        Assert.Equal(
        [
            new DetailsRow("Versione", "26.05"),
            new DetailsRow("Ambito installazione", "Machine"),
            new DetailsRow("Aggiornamenti disponibili", "winget [26.06]"),
        ], d.Parts[1].Rows);
    }

    // Un nome col ": " resta nella riga d'apertura, che non diventa un'etichetta.
    [Fact]
    public void OpeningLineIsNeverALabel()
    {
        var part = Assert.Single(PackageDetails.Parse("Foo: Bar", "F.B", new DetailsReads("", "Found Foo: Bar [F.B]\r\nVersion: 1"), "winget")!.Parts);
        Assert.Equal([new DetailsRow("Version", "1")], part.Rows);
    }

    [Fact]
    public void LineWithoutLabelSpansTheRow()
    {
        var part = Assert.Single(PackageDetails.Parse("X", "x", new DetailsReads("Found X [x]\r\nVersion: 1\r\nA note", ""), null)!.Parts);
        Assert.Equal(new DetailsRow("", "A note"), part.Rows[1]);
    }

    // Nessuna riga "etichetta: valore" (un errore, un winget vecchio): il testo si mostra com'e'.
    [Theory]
    [InlineData("No installed package found matching input criteria.")]
    [InlineData("")]
    [InlineData("winget returned no details for this package.")]
    public void TextWithoutLabelsIsNull(string text) => Assert.Null(PackageDetails.Parse("X", "x", new DetailsReads(text, text), "winget"));
}
