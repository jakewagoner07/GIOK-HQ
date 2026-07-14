# =====================================================================
# Build-GiokIcon.ps1  -  regenerate giok.ico from giok-logo.png
# ---------------------------------------------------------------------
# The Windows shortcut / taskbar icon (giok.ico) is a GENERATED artifact built
# from the official brand PNG (giok-logo.png). It is committed to the repo so a
# checkout is self-contained, but if the logo ever changes, re-run this script to
# rebuild the multi-size .ico - do not hand-edit giok.ico.
#
# It writes a real multi-size icon (16/24/32/48/64/128/256 px) so every Windows
# surface - taskbar, Alt+Tab, Start Menu, Explorer - gets a crisp frame instead of
# a single 256px frame down-scaled to soft 16-48px. Each frame is stored as PNG
# (the standard for modern .ico), which Windows 10/11 render natively.
#
#   .\Build-GiokIcon.ps1                 # rebuild giok.ico next to giok-logo.png
#   .\Build-GiokIcon.ps1 -Source x.png -Out y.ico
#
# Pure build tooling: touches no app logic, storage, or runtime data.
# =====================================================================

param(
    [string]$Source,
    [string]$Out,
    [int[]]$Sizes = @(16, 24, 32, 48, 64, 128, 256)
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $Source) { $Source = Join-Path $here 'giok-logo.png' }
if (-not $Out)    { $Out    = Join-Path $here 'giok.ico' }
if (-not (Test-Path $Source)) { throw "Source artwork not found: $Source" }

$src = [System.Drawing.Image]::FromFile($Source)
try {
    # Render each size to a PNG blob (high-quality resample).
    $frames = foreach ($s in ($Sizes | Sort-Object)) {
        $bmp = New-Object System.Drawing.Bitmap $s, $s
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $g.PixelOffsetMode   = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $g.SmoothingMode     = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
        $g.DrawImage($src, 0, 0, $s, $s)
        $g.Dispose()
        $ms = New-Object System.IO.MemoryStream
        $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
        $bmp.Dispose()
        [pscustomobject]@{ Size = $s; Bytes = $ms.ToArray() }
    }
}
finally { $src.Dispose() }

# Assemble the ICO container: ICONDIR header + one ICONDIRENTRY per frame + PNG blobs.
# (Note: the stream var must NOT be named $out - that collides case-insensitively with
#  the [string]$Out param, whose type constraint would coerce the stream to a string.)
$icoStream = New-Object System.IO.MemoryStream
$bw = New-Object System.IO.BinaryWriter -ArgumentList $icoStream
$count = $frames.Count
$bw.Write([uint16]0)       # reserved
$bw.Write([uint16]1)       # type = 1 (icon)
$bw.Write([uint16]$count)  # image count

# Frame blobs start after the 6-byte header + 16 bytes per directory entry.
$offset = 6 + (16 * $count)
foreach ($f in $frames) {
    $dim = if ($f.Size -ge 256) { 0 } else { $f.Size }   # 0 means 256 in the ICO spec
    $bw.Write([byte]$dim)          # width
    $bw.Write([byte]$dim)          # height
    $bw.Write([byte]0)             # palette count (0 = no palette)
    $bw.Write([byte]0)             # reserved
    $bw.Write([uint16]1)           # color planes
    $bw.Write([uint16]32)          # bits per pixel
    $bw.Write([uint32]$f.Bytes.Length)  # bytes in this frame
    $bw.Write([uint32]$offset)     # offset to this frame's data
    $offset += $f.Bytes.Length
}
foreach ($f in $frames) { $bw.Write($f.Bytes) }
$bw.Flush()
[System.IO.File]::WriteAllBytes($Out, $icoStream.ToArray())
$bw.Dispose(); $icoStream.Dispose()

Write-Host ("Wrote {0} ({1} frames: {2}) from {3}" -f $Out, $count, (($frames.Size) -join '/'), $Source)
