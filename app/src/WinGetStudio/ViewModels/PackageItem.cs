using CommunityToolkit.Mvvm.ComponentModel;
using WinGetStudio.Core;

namespace WinGetStudio.ViewModels;

// Esito della riga nella colonna Result: Running mentre winget lavora, poi il glifo.
public enum RowStatus { None, Running, Ok, Warning, Error }

// Riga di una griglia: i dati di winget piu' cio' che la UI cambia (spunta, pin, esito), con
// notifica a WPF (il motivo di WgtRow nella 1.x, ADR 0009).
public sealed partial class PackageItem : ObservableObject
{
    public PackageItem(PackageRow row)
    {
        Row = row;
        StatusDetail = "";
    }

    public PackageRow Row { get; }
    public string Name => Row.Name;
    public string Id => Row.Id;
    public string Version => Row.Version;
    public string Available => Row.Available;
    public string Source => Row.Source;

    [ObservableProperty] public partial bool Selected { get; set; }
    [ObservableProperty] public partial bool Pinned { get; set; }
    [ObservableProperty] public partial RowStatus Status { get; set; }
    [ObservableProperty] public partial string StatusDetail { get; set; }

    // null = in corso (il rowChanged di PackageQueue).
    public void SetOutcome(PackageOutcome? outcome)
    {
        Status = outcome?.Status switch
        {
            null => RowStatus.Running,
            OperationStatus.Ok => RowStatus.Ok,
            OperationStatus.Warning => RowStatus.Warning,
            _ => RowStatus.Error,
        };
        StatusDetail = outcome?.Detail ?? "In progress...";
    }
}
