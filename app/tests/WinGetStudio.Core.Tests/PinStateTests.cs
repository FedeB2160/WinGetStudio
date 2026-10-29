using WinGetStudio.Core;

namespace WinGetStudio.Core.Tests;

// Pin bloccanti (ADR 0007): winget e' la fonte di verita', i pinnati restano fuori dalla coda
// qualunque sia il tipo di pin, e si mettono in coda solo le righe che cambiano stato.
public class PinStateTests
{
    private static readonly PackageRow A = new("App A", "A.A", "1.0");
    private static readonly PackageRow B = new("App B", "B.B", "1.0");

    private static ReadResult<string> Read(bool success, params string[] ids) => new(success, success ? ids : [], success ? 0 : 1, "");

    // Una lettura fallita tiene l'ultima lista buona: mostrare le righe "senza pin" sarebbe
    // un'affermazione che winget non ha fatto.
    [Fact]
    public void FailedReadKeepsTheLastGoodList()
    {
        var pins = new PinState();
        pins.Apply(Read(true, "A.A"));
        pins.Apply(Read(false));
        Assert.True(pins.IsPinned("A.A"));
        pins.Apply(Read(true));
        Assert.False(pins.IsPinned("A.A"));
    }

    // Ripinnare un pinnato fa uscire winget con un errore, segnato in rosso nella colonna Result.
    [Fact]
    public void OnlyRowsThatChangeState()
    {
        var pins = new PinState();
        pins.Apply(Read(true, "A.A"));
        Assert.Equal([B], pins.Changing([A, B], pin: true));
        Assert.Equal([A], pins.Changing([A, B], pin: false));
    }

    [Fact]
    public void PinnedRowsStayOutOfTheUpdateQueue()
    {
        var pins = new PinState();
        pins.Apply(Read(true, "A.A"));
        Assert.Equal([B], pins.ExcludePinned([A, B], out var message));
        Assert.Equal("Skipping 1 pinned package: remove the pin to update it.", message);

        pins.Apply(Read(true, "A.A", "B.B"));
        Assert.Empty(pins.ExcludePinned([A, B], out message));
        Assert.Equal("Skipping 2 pinned packages: remove the pin to update them.", message);

        pins.Apply(Read(true));
        pins.ExcludePinned([A], out message);
        Assert.Null(message);
    }
}
