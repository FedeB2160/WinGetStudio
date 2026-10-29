using WinGetStudio.Core;

namespace WinGetStudio.Core.Tests;

// Tabella corretta in v1.13 (PR #31): nomi da "winget error <codice>" su 1.29.380.
// Fino alla 1.12 la lista era sfasata di uno: un'installazione non riuscita o annullata
// risultava un avviso, e un "gia' installato" un errore.
public class ExitCodesTests
{
    [Theory]
    [InlineData(0, OperationStatus.Ok)]
    [InlineData(unchecked((int)0x8A150109), OperationStatus.Warning)] // INSTALL_REBOOT_REQUIRED_TO_FINISH
    [InlineData(unchecked((int)0x8A15010B), OperationStatus.Warning)] // INSTALL_REBOOT_INITIATED
    [InlineData(unchecked((int)0x8A15010D), OperationStatus.Warning)] // INSTALL_ALREADY_INSTALLED
    [InlineData(3010, OperationStatus.Warning)]                       // ERROR_SUCCESS_REBOOT_REQUIRED
    [InlineData(1641, OperationStatus.Warning)]                       // ERROR_SUCCESS_REBOOT_INITIATED
    [InlineData(unchecked((int)0x8A150108), OperationStatus.Error)]   // INSTALL_CONTACT_SUPPORT
    [InlineData(unchecked((int)0x8A15010A), OperationStatus.Error)]   // INSTALL_REBOOT_REQUIRED_FOR_INSTALL
    [InlineData(unchecked((int)0x8A15010C), OperationStatus.Error)]   // INSTALL_CANCELLED_BY_USER
    [InlineData(1, OperationStatus.Error)]
    [InlineData(-1, OperationStatus.Error)]
    public void Classify(int code, OperationStatus expected) =>
        Assert.Equal(expected, ExitCodes.Classify(code));
}
