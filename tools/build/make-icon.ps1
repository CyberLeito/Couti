# Render the geometric Couti mark from INSTALL/tool/couti.svg into Windows ICO.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$frames = @()
foreach ($size in @(16, 32, 48, 64, 128, 256)) {
    $bitmap = [Drawing.Bitmap]::new($size, $size)
    $graphics = [Drawing.Graphics]::FromImage($bitmap)
    $graphics.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $graphics.ScaleTransform($size / 64.0, $size / 64.0)
    $background = [Drawing.SolidBrush]::new([Drawing.ColorTranslator]::FromHtml('#101827'))
    $outline = [Drawing.Drawing2D.GraphicsPath]::new()
    $outline.AddArc(0, 0, 28, 28, 180, 90)
    $outline.AddArc(36, 0, 28, 28, 270, 90)
    $outline.AddArc(36, 36, 28, 28, 0, 90)
    $outline.AddArc(0, 36, 28, 28, 90, 90)
    $outline.CloseFigure()
    $graphics.FillPath($background, $outline)
    $pen = [Drawing.Pen]::new([Drawing.ColorTranslator]::FromHtml('#38bdf8'), 9)
    $pen.StartCap = [Drawing.Drawing2D.LineCap]::Round
    $pen.EndCap = [Drawing.Drawing2D.LineCap]::Round
    $graphics.DrawArc($pen, 13, 13, 38, 38, 45, 270)
    $stream = [IO.MemoryStream]::new()
    $bitmap.Save($stream, [Drawing.Imaging.ImageFormat]::Png)
    $frames += ,@($size, $stream.ToArray())
    $stream.Dispose(); $pen.Dispose(); $outline.Dispose(); $background.Dispose()
    $graphics.Dispose(); $bitmap.Dispose()
}
$target = Join-Path $repo 'Ventoy2Disk/Ventoy2Disk/Res/couti.ico'
$file = [IO.File]::Create($target)
$writer = [IO.BinaryWriter]::new($file)
$writer.Write([uint16]0); $writer.Write([uint16]1); $writer.Write([uint16]$frames.Count)
$offset = 6 + 16 * $frames.Count
foreach ($frame in $frames) {
    $dim = if ($frame[0] -eq 256) { 0 } else { $frame[0] }
    $writer.Write([byte]$dim); $writer.Write([byte]$dim)
    $writer.Write([uint16]0); $writer.Write([uint16]1); $writer.Write([uint16]32)
    $writer.Write([uint32]$frame[1].Length); $writer.Write([uint32]$offset)
    $offset += $frame[1].Length
}
foreach ($frame in $frames) { $writer.Write([byte[]]$frame[1]) }
$writer.Dispose()
Write-Output "Created $target"
