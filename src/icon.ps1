<#
    icon.ps1 — disegna l'icona dell'app (scatola di cartone, prompt >_ timbrato sul fianco,
    badge blu di download) e scrive assets\icon.ico e assets\icon\icon-<n>.png.
    NON fa parte della build: l'output e' committato, e build.ps1 e il setup usano
    assets\icon.ico cosi' com'e'. Si rilancia solo per cambiare l'icona:
        powershell -NoProfile -ExecutionPolicy Bypass -File .\src\icon.ps1
    Perche' disegnata in codice e non con un editor o da un SVG: docs\adr\0017.
#>
$ErrorActionPreference = 'Stop'
# WPF vuole un thread STA: powershell.exe 5.1 lo e', pwsh 7 solo con -STA.
if ([Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') { throw 'Lanciare con powershell.exe (5.1) oppure pwsh -STA' }
Add-Type -AssemblyName PresentationCore, WindowsBase

$root = Split-Path -Parent $PSScriptRoot   # icon.ps1 sta in src\

# Le dimensioni del .ico sono la lista Microsoft per le app Win32: quelle che Windows chiede
# alle scale piu' comuni, le piu' grandi le ricava dal 256. Con un frame per ognuna non
# rimpicciolisce il 256, che fino a v1.11.0 era l'unico frame e a 16-48 px usciva sfocato.
$icoSizes = 16, 20, 24, 30, 32, 36, 40, 48, 60, 64, 72, 80, 96, 256
$pngSizes = 16, 24, 32, 48, 64, 128, 256, 512, 1024

# Tre livelli di dettaglio, ognuno sulla sua griglia (unita' = pixel alla dimensione nativa):
# sotto i 48 px il >_ intero non si legge, sotto i 24 nemmeno il solo >, e il badge cresce.
# Scatola: spigolo centrale C, mezza larghezza W, vertice alto T, spigoli verticali alti V.
# Isometria 2:1, quindi il rombo del coperchio e' alto quanto W: gli spigoli obliqui
# diventano scalini regolari di 2 pixel a ogni dimensione.
# Nastro: mezza larghezza TapeF (frazione dello spigolo), discesa sul fianco destro TapeDrop.
# Timbro: spezzata Stamp di tratto StampW e barretta Bar (x, y, w, h, raggio), in coordinate
# del fianco sinistro. Badge: centro X,Y, raggio R, stacco Cut; freccia da Y-A1 a Y+A2,
# ali HW, tratto SW.
$tiers = @(
    @{ Max = 20; Grid = 16; C = 8; W = 7; T = 1; V = 7; TapeF = 0.12; TapeDrop = 0
       Stamp = $null; StampW = 0; Bar = $null
       X = 11.5; Y = 11.5; R = 4.5; Cut = 5.5; A1 = 2; A2 = 2.5; HW = 2; SW = 1 }   # freccia centrata: con 3 e 1,5 stava 0,75 px sopra
    @{ Max = 40; Grid = 32; C = 15; W = 12; T = 3; V = 13; TapeF = 0.12; TapeDrop = 3.5
       Stamp = @(3, 6.5, 6, 9, 3, 11.5); StampW = 1.8; Bar = $null
       X = 24; Y = 24; R = 7; Cut = 8.5; A1 = 3.5; A2 = 2.7; HW = 2.7; SW = 2.1 }
    @{ Max = [int]::MaxValue; Grid = 256; C = 122; W = 96; T = 20; V = 108; TapeF = 0.115; TapeDrop = 34
       Stamp = @(18, 46, 40, 63, 18, 80); StampW = 10; Bar = @(46, 72, 24, 9, 2)
       X = 184; Y = 186; R = 52; Cut = 62; A1 = 24; A2 = 22; HW = 22; SW = 15 }
)

function New-Brush([string]$hex) {
    $b = New-Object Windows.Media.SolidColorBrush ([Windows.Media.ColorConverter]::ConvertFromString($hex))
    $b.Freeze()
    $b
}
# Colori di base: ogni dimensione li sfuma con New-Ramp, sulla sua geometria.
$lid      = '#EDBE80'   # coperchio
$leftSide = '#D9A15C'
$rightSide = '#BF853F'
$tape     = '#F7E2BC'
$tapeSide = '#DDB57A'   # il nastro che scende sul fianco destro, in ombra
$ink      = '#5A3A1A'   # il timbro >_
$blue     = '#0078D4'   # il blu dell'icona precedente
$white    = New-Brush '#FFFFFF'

# Luce dall'alto (ADR 0017): da $y0 a $y1 il colore va da +$up (mescolato al bianco) a -$down
# (mescolato al nero), passando dal colore pieno. Coordinate assolute, in pixel dell'icona.
function New-Ramp([string]$hex, [double]$y0, [double]$y1, [double]$up, [double]$down) {
    $c = [Windows.Media.ColorConverter]::ConvertFromString($hex)
    $mix = { param($t, $f) [Windows.Media.Color]::FromRgb(
        [byte][Math]::Round($c.R + ($t - $c.R) * $f), [byte][Math]::Round($c.G + ($t - $c.G) * $f), [byte][Math]::Round($c.B + ($t - $c.B) * $f)) }
    $stops = New-Object Windows.Media.GradientStopCollection
    $stops.Add((New-Object Windows.Media.GradientStop (& $mix 255 $up), 0))
    $stops.Add((New-Object Windows.Media.GradientStop $c, ($up / ($up + $down))))
    $stops.Add((New-Object Windows.Media.GradientStop (& $mix 0 $down), 1))
    $b = New-Object Windows.Media.LinearGradientBrush $stops, (New-Object Windows.Point 0, $y0), (New-Object Windows.Point 0, $y1)
    $b.MappingMode = 'Absolute'
    $b.Freeze()
    $b
}

function New-Pen($brush, [double]$width) {
    $p = New-Object Windows.Media.Pen $brush, $width
    $p.StartLineCap = 'Round'; $p.EndLineCap = 'Round'; $p.LineJoin = 'Round'
    $p.Freeze()
    $p
}

# Spezzata (aperta o chiusa) da coppie x,y. Costruita a mano e non con Geometry.Parse:
# con la cultura italiana ogni -f scriverebbe "1,5" al posto di "1.5".
function New-Shape([double[]]$xy, [bool]$closed = $true) {
    $g = New-Object Windows.Media.StreamGeometry
    $ctx = $g.Open()
    $ctx.BeginFigure((New-Object Windows.Point $xy[0], $xy[1]), $closed, $closed)
    for ($i = 2; $i -lt $xy.Count; $i += 2) {
        $ctx.LineTo((New-Object Windows.Point $xy[$i], $xy[$i + 1]), $true, $false)
    }
    $ctx.Close()
    $g.Freeze()
    $g
}

function Snap([double]$v) { [Math]::Round($v, [MidpointRounding]::AwayFromZero) }

# Ritorna il PNG (byte[]) dell'icona a $size pixel.
function New-IconPng([int]$size) {
    $t = $tiers | Where-Object { $size -le $_.Max } | Select-Object -First 1
    $k = $size / $t.Grid

    # Scatola agganciata ai pixel: spigoli verticali su pixel interi (larghezza pari, quindi
    # anche quello centrale), pendenza esatta 0,5.
    $c = Snap ($t.C * $k); $w = Snap ($t.W * $k); $h = $w / 2
    $l = $c - $w; $r = $c + $w
    $top = Snap ($t.T * $k); $v = Snap ($t.V * $k)
    $y1 = $top + $h            # spigoli alti dei fianchi
    $y2 = $top + 2 * $h        # spigolo centrale, il fronte del coperchio

    # Freccia nitida: con un tratto dispari l'asta sta su mezzo pixel, con uno pari su un
    # pixel intero. Il badge la segue, cosi' resta centrata.
    $sw = [Math]::Max(1, (Snap ($t.SW * $k)))
    if ($sw % 2) { $bx = [Math]::Floor($t.X * $k) + 0.5; $by = [Math]::Floor($t.Y * $k) + 0.5 }
    else         { $bx = Snap ($t.X * $k);               $by = Snap ($t.Y * $k) }

    # Sfumature sulla geometria di questa dimensione: la scatola dal vertice alto allo spigolo
    # in basso, il badge dal suo bordo alto a quello basso.
    $bottom = $y2 + $v
    $box = @{}
    foreach ($n in 'lid', 'leftSide', 'rightSide', 'tape', 'tapeSide') {
        $box[$n] = New-Ramp (Get-Variable $n -ValueOnly) $top $bottom 0.42 0.35
    }
    $badge = New-Ramp $blue ($by - $t.R * $k) ($by + $t.R * $k) 0.42 0.28

    $dv = New-Object Windows.Media.DrawingVisual
    $dc = $dv.RenderOpen()

    # Lo stacco trasparente attorno al badge: la scatola e' ritagliata lungo un cerchio.
    $canvas = New-Object Windows.Media.RectangleGeometry (New-Object Windows.Rect 0, 0, $size, $size)
    $hole = New-Object Windows.Media.EllipseGeometry (New-Object Windows.Point $bx, $by), ($t.Cut * $k), ($t.Cut * $k)
    $dc.PushClip((New-Object Windows.Media.CombinedGeometry ([Windows.Media.GeometryCombineMode]::Exclude), $canvas, $hole))

    # Prima la sagoma intera nel colore del fianco destro, poi coperchio e fianco sinistro:
    # disegnando le tre facce affiancate l'antialiasing lascerebbe una riga semitrasparente
    # lungo gli spigoli in comune.
    $dc.DrawGeometry($box.rightSide, $null, (New-Shape @($c, $top, $r, $y1, $r, ($y1 + $v), $c, ($y2 + $v), $l, ($y1 + $v), $l, $y1)))
    $dc.DrawGeometry($box.lid, $null, (New-Shape @($c, $top, $r, $y1, $c, $y2, $l, $y1)))
    $dc.DrawGeometry($box.leftSide, $null, (New-Shape @($l, $y1, $c, $y2, $c, ($y2 + $v), $l, ($y1 + $v))))

    # Nastro: dal centro dello spigolo posteriore sinistro al centro di quello anteriore
    # destro, poi giu' per un tratto sul fianco destro.
    $ox = $t.TapeF * $w; $oy = $t.TapeF * $h
    $ax = ($l + $c) / 2; $ay = $top + $h / 2
    $fx = ($r + $c) / 2; $fy = $top + 1.5 * $h
    $dc.DrawGeometry($box.tape, $null, (New-Shape @(($ax - $ox), ($ay + $oy), ($ax + $ox), ($ay - $oy), ($fx + $ox), ($fy - $oy), ($fx - $ox), ($fy + $oy))))
    if ($t.TapeDrop) {
        $d = $t.TapeDrop * $k
        $dc.DrawGeometry($box.tapeSide, $null, (New-Shape @(($fx - $ox), ($fy + $oy), ($fx + $ox), ($fy - $oy), ($fx + $ox), ($fy - $oy + $d), ($fx - $ox), ($fy + $oy + $d))))
    }

    # Timbro sul fianco sinistro: coordinate del fianco, inclinate di 0,5 come i suoi spigoli.
    if ($t.Stamp) {
        $dc.PushTransform((New-Object Windows.Media.MatrixTransform 1, 0.5, 0, 1, $l, $y1))
        $dc.PushTransform((New-Object Windows.Media.ScaleTransform $k, $k))
        $dc.DrawGeometry($null, (New-Pen (New-Brush $ink) $t.StampW), (New-Shape $t.Stamp $false))
        if ($t.Bar) {
            $b = $t.Bar
            $dc.DrawRoundedRectangle((New-Brush $ink), $null, (New-Object Windows.Rect $b[0], $b[1], $b[2], $b[3]), $b[4], $b[4])
        }
        $dc.Pop(); $dc.Pop()
    }
    $dc.Pop()

    $dc.DrawEllipse($badge, $null, (New-Object Windows.Point $bx, $by), ($t.R * $k), ($t.R * $k))
    $pen = New-Pen $white $sw
    $a1 = $t.A1 * $k; $a2 = $t.A2 * $k; $hw = $t.HW * $k
    $dc.DrawGeometry($null, $pen, (New-Shape @($bx, ($by - $a1), $bx, ($by + $a2)) $false))
    $dc.DrawGeometry($null, $pen, (New-Shape @(($bx - $hw), ($by + $a2 - $hw), $bx, ($by + $a2), ($bx + $hw), ($by + $a2 - $hw)) $false))
    $dc.Close()

    $bmp = New-Object Windows.Media.Imaging.RenderTargetBitmap $size, $size, 96, 96, ([Windows.Media.PixelFormats]::Pbgra32)
    $bmp.Render($dv)
    $enc = New-Object Windows.Media.Imaging.PngBitmapEncoder
    $enc.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bmp))
    $ms = New-Object IO.MemoryStream
    $enc.Save($ms)
    , $ms.ToArray()
}

$png = @{}
foreach ($s in ($icoSizes + $pngSizes | Sort-Object -Unique)) { $png[$s] = New-IconPng $s }

$dir = Join-Path $root 'assets\icon'
New-Item -ItemType Directory -Force -Path $dir | Out-Null
foreach ($s in $pngSizes) { [IO.File]::WriteAllBytes((Join-Path $dir "icon-$s.png"), $png[$s]) }

# .ico: header di 6 byte, una voce di 16 per frame, poi i PNG uno dopo l'altro.
# ponytail: frame tutti PNG. Windows li legge a ogni dimensione da Vista, e il 256 PNG di
# prima andava gia' bene a ps2exe e a Inno. Se un programma rifiuta i PNG piccoli, i frame
# fino a 48 px vanno scritti come BMP a 32 bit.
$ms = New-Object IO.MemoryStream
$bw = New-Object IO.BinaryWriter $ms
$bw.Write([uint16]0); $bw.Write([uint16]1); $bw.Write([uint16]$icoSizes.Count)
$offset = 6 + 16 * $icoSizes.Count
foreach ($s in $icoSizes) {
    $d = if ($s -ge 256) { 0 } else { $s }      # nel formato .ico 0 vuol dire 256
    $bw.Write([byte]$d); $bw.Write([byte]$d)
    $bw.Write([uint16]0)                         # colori in palette e byte riservato
    $bw.Write([uint16]1); $bw.Write([uint16]32)  # piani, bit per pixel
    $bw.Write([uint32]$png[$s].Length); $bw.Write([uint32]$offset)
    $offset += $png[$s].Length
}
foreach ($s in $icoSizes) { $bw.Write($png[$s]) }
$bw.Flush()
$ico = Join-Path $root 'assets\icon.ico'
[IO.File]::WriteAllBytes($ico, $ms.ToArray())
Write-Host "Scritti $ico ($($icoSizes.Count) dimensioni) e $($pngSizes.Count) PNG in $dir" -ForegroundColor Green
