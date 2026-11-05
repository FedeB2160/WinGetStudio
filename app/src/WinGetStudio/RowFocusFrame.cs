using System.Windows;
using System.Windows.Documents;
using System.Windows.Media;

namespace WinGetStudio;

// Cornice di fuoco da tastiera su tutta la riga di una griglia (ADR 0028, punto 16). Un adorner e
// non il bordo della riga: non occupa spazio, quindi la riga resta di 28 px e le celle allineate ai
// titoli; e' disegnata dentro la riga, mai oltre il bordo della griglia. La mette MainWindow.
internal sealed class RowFocusFrame : Adorner
{
    private static readonly DependencyProperty StrokeProperty = DependencyProperty.Register(
        "Stroke", typeof(Brush), typeof(RowFocusFrame), new FrameworkPropertyMetadata(null, FrameworkPropertyMetadataOptions.AffectsRender));

    public RowFocusFrame(UIElement row) : base(row)
    {
        IsHitTestVisible = false;
        // Il tratto esterno della cornice di fuoco Fluent: quasi opaco, si vede anche sul blu della
        // riga selezionata (quello traslucido degli altri controlli li' scende a 2:1). Segue il tema.
        SetResourceReference(StrokeProperty, "FocusStrokeColorOuterBrush");
    }

    protected override void OnRender(DrawingContext dc)
    {
        // 2 px centrati sul rettangolo: rientrato di 1, il tratto copre proprio i bordi della riga.
        var size = AdornedElement.RenderSize;
        if (GetValue(StrokeProperty) is Brush brush && size.Width > 2 && size.Height > 2)
            dc.DrawRectangle(null, new Pen(brush, 2), new Rect(1, 1, size.Width - 2, size.Height - 2));
    }
}
