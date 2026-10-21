#!/usr/bin/env pwsh
# Generates the TeachCross launcher icons for Android and iOS from the brand
# mark (the "T" with the cross bar on the brand gradient).
#
#   powershell -ExecutionPolicy Bypass -File scripts\make-app-icons.ps1
#
# Android icons are written to apps\mobile\android\app\src\main\res\mipmap-*\.
# iOS icons are written to the AppIcon.appiconset folder, driven by its
# Contents.json so every declared slot is filled.
param(
  [string]$AndroidRes = 'apps\mobile\android\app\src\main\res',
  [string]$IosIconSet = 'apps\mobile\ios\Runner\Assets.xcassets\AppIcon.appiconset'
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$root = Split-Path $PSScriptRoot -Parent

# ── Brand ─────────────────────────────────────────────────────────
$brandStart = [System.Drawing.Color]::FromArgb(255, 53, 103, 246)   # brand-500
$brandEnd   = [System.Drawing.Color]::FromArgb(255, 26, 55, 212)    # brand-700
$markColor  = [System.Drawing.Color]::White

# Draws the brand mark (rounded gradient tile + white T/cross glyph) at the
# requested size. $fullBleed omits the rounded corners for iOS, where the
# system masks the icon itself.
function New-BrandIcon([int]$Size, [bool]$FullBleed) {
  $bmp = New-Object System.Drawing.Bitmap($Size, $Size)
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
  $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAlias
  $g.Clear([System.Drawing.Color]::Transparent)

  $rect = New-Object System.Drawing.Rectangle(0, 0, $Size, $Size)
  $brush = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
    $rect, $brandStart, $brandEnd, 45.0
  )

  if ($FullBleed) {
    $g.FillRectangle($brush, 0, 0, $Size, $Size)
  } else {
    $radius = [int]($Size * 0.22)
    $d = $radius * 2
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $path.AddArc(0, 0, $d, $d, 180, 90)
    $path.AddArc($Size - $d, 0, $d, $d, 270, 90)
    $path.AddArc($Size - $d, $Size - $d, $d, $d, 0, 90)
    $path.AddArc(0, $Size - $d, $d, $d, 90, 90)
    $path.CloseFigure()
    $g.FillPath($brush, $path)
  }

  # Gloss highlight across the top 45%.
  $gloss = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
    (New-Object System.Drawing.Rectangle(0, 0, $Size, [int]($Size * 0.45))),
    [System.Drawing.Color]::FromArgb(64, 255, 255, 255),
    [System.Drawing.Color]::FromArgb(0, 255, 255, 255),
    90.0
  )
  $g.FillRectangle($gloss, 0, 0, $Size, [int]($Size * 0.45))

  # The glyph: a "T" whose stem carries a cross bar.
  $white = New-Object System.Drawing.SolidBrush($markColor)
  $barH = [int]($Size * 0.115)
  $stemW = [int]($Size * 0.135)
  $cx = [int]($Size / 2)

  $g.FillRectangle($white, [int]($Size * 0.24), [int]($Size * 0.29), [int]($Size * 0.52), $barH)
  $g.FillRectangle($white, $cx - [int]($stemW / 2), [int]($Size * 0.29), $stemW, [int]($Size * 0.42))
  $g.FillRectangle($white, [int]($Size * 0.35), [int]($Size * 0.50), [int]($Size * 0.30), $barH)

  $g.Dispose(); $brush.Dispose(); $gloss.Dispose(); $white.Dispose()
  return $bmp
}

function Write-Icon([string]$Path, [int]$Size, [bool]$FullBleed) {
  $dir = Split-Path $Path -Parent
  if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
  $bmp = New-BrandIcon -Size $Size -FullBleed $FullBleed
  $bmp.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
  $bmp.Dispose()
  Write-Host ("  {0,-58} {1}x{1}" -f (Split-Path $Path -Leaf), $Size)
}

# ── Android ──────────────────────────────────────────────────────
Write-Host '==> Android launcher icons' -ForegroundColor Cyan
$androidSizes = @{
  'mipmap-mdpi'    = 48
  'mipmap-hdpi'    = 72
  'mipmap-xhdpi'   = 96
  'mipmap-xxhdpi'  = 144
  'mipmap-xxxhdpi' = 192
}
foreach ($folder in $androidSizes.Keys) {
  $dir = Join-Path $root (Join-Path $AndroidRes $folder)
  Write-Icon (Join-Path $dir 'ic_launcher.png') $androidSizes[$folder] $false
}

# Android adaptive icon (API 26+): a vector foreground over a brand colour
# background. A vector scales to every density, so it never pixelates.
Write-Host '==> Android adaptive icon' -ForegroundColor Cyan
$adaptiveDir = Join-Path $root (Join-Path $AndroidRes 'mipmap-anydpi-v26')
$drawableDir = Join-Path $root (Join-Path $AndroidRes 'drawable')
$valuesDir   = Join-Path $root (Join-Path $AndroidRes 'values')
foreach ($d in @($adaptiveDir, $drawableDir, $valuesDir)) {
  if (-not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
}

$foreground = @'
<?xml version="1.0" encoding="utf-8"?>
<!-- TeachCross adaptive-icon foreground: the "T" with the cross bar.
     Artwork sits inside the 66dp safe zone of the 108dp canvas. -->
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="108dp"
    android:height="108dp"
    android:viewportWidth="108"
    android:viewportHeight="108">
  <path android:fillColor="#FFFFFFFF" android:pathData="M25.9,31.3 H82.1 V43.7 H25.9 Z" />
  <path android:fillColor="#FFFFFFFF" android:pathData="M46.7,31.3 H61.3 V76.7 H46.7 Z" />
  <path android:fillColor="#FFFFFFFF" android:pathData="M37.8,54 H70.2 V66.4 H37.8 Z" />
</vector>
'@
Set-Content -LiteralPath (Join-Path $drawableDir 'ic_launcher_foreground.xml') -Value $foreground -Encoding utf8

$adaptive = @'
<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background" />
    <foreground android:drawable="@drawable/ic_launcher_foreground" />
    <monochrome android:drawable="@drawable/ic_launcher_foreground" />
</adaptive-icon>
'@
Set-Content -LiteralPath (Join-Path $adaptiveDir 'ic_launcher.xml') -Value $adaptive -Encoding utf8

$colors = @'
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="ic_launcher_background">#3567F6</color>
</resources>
'@
Set-Content -LiteralPath (Join-Path $valuesDir 'ic_launcher_colors.xml') -Value $colors -Encoding utf8
Write-Host '  mipmap-anydpi-v26/ic_launcher.xml, drawable/ic_launcher_foreground.xml, values/ic_launcher_colors.xml'

# ── iOS ──────────────────────────────────────────────────────────
Write-Host '==> iOS app icons' -ForegroundColor Cyan
$iconSetDir = Join-Path $root $IosIconSet
$contents = Get-Content -LiteralPath (Join-Path $iconSetDir 'Contents.json') -Raw | ConvertFrom-Json
foreach ($image in $contents.images) {
  if (-not $image.filename) { continue }
  $base = $image.size -split 'x' | Select-Object -First 1
  $scale = [double]($image.scale -replace 'x', '')
  $px = [int]([double]$base * $scale)
  # iOS masks the corners itself, so the artwork is full-bleed square.
  Write-Icon (Join-Path $iconSetDir $image.filename) $px $true
}

Write-Host 'Done.' -ForegroundColor Green
