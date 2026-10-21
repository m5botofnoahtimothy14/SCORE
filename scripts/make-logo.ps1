#!/usr/bin/env pwsh
# Generates the TeachCross brand logo used by the mobile app
# (assets/images/logo.png) and any future icon surfaces.
#
#   powershell -ExecutionPolicy Bypass -File scripts\make-logo.ps1
param(
  [string]$OutPath = "apps\mobile\assets\images\logo.png",
  [int]$Size = 512
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$root = Split-Path $PSScriptRoot -Parent
$out = Join-Path $root $OutPath
$dir = Split-Path $out -Parent
if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }

$bmp = New-Object System.Drawing.Bitmap($Size, $Size)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAlias
$g.Clear([System.Drawing.Color]::Transparent)

# Brand gradient (brand-500 -> brand-700), matching app_theme.dart.
$rect = New-Object System.Drawing.Rectangle(0, 0, $Size, $Size)
$brush = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
  $rect,
  [System.Drawing.Color]::FromArgb(255, 53, 103, 246),
  [System.Drawing.Color]::FromArgb(255, 26, 55, 212),
  45.0
)

# Rounded square with a comfortable corner radius.
$radius = [int]($Size * 0.22)
$path = New-Object System.Drawing.Drawing2D.GraphicsPath
$d = $radius * 2
$path.AddArc(0, 0, $d, $d, 180, 90)
$path.AddArc($Size - $d, 0, $d, $d, 270, 90)
$path.AddArc($Size - $d, $Size - $d, $d, $d, 0, 90)
$path.AddArc(0, $Size - $d, $d, $d, 90, 90)
$path.CloseFigure()
$g.FillPath($brush, $path)

# Gloss highlight across the top third.
$gloss = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
  (New-Object System.Drawing.Rectangle(0, 0, $Size, [int]($Size * 0.45))),
  [System.Drawing.Color]::FromArgb(70, 255, 255, 255),
  [System.Drawing.Color]::FromArgb(0, 255, 255, 255),
  90.0
)
$clip = New-Object System.Drawing.Drawing2D.GraphicsPath
$clip.AddArc(0, 0, $d, $d, 180, 90)
$clip.AddArc($Size - $d, 0, $d, $d, 270, 90)
$clip.AddArc($Size - $d, $Size - $d, $d, $d, 0, 90)
$clip.AddArc(0, $Size - $d, $d, $d, 90, 90)
$clip.CloseFigure()
$g.SetClip($clip)
$g.FillRectangle($gloss, 0, 0, $Size, [int]($Size * 0.45))
$g.ResetClip()

# Wordmark: "T" with the "cross" bar, matching the app lockup.
$white = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
$barH = [int]($Size * 0.11)
$stemW = [int]($Size * 0.13)
$cx = [int]($Size / 2)

# Top bar
$g.FillRectangle($white, [int]($Size * 0.24), [int]($Size * 0.30), [int]($Size * 0.52), $barH)
# Vertical stem
$g.FillRectangle($white, $cx - [int]($stemW / 2), [int]($Size * 0.30), $stemW, [int]($Size * 0.40))
# Cross bar (the "cross" in TeachCross)
$g.FillRectangle($white, [int]($Size * 0.36), [int]($Size * 0.50), [int]($Size * 0.28), $barH)

$bmp.Save($out, [System.Drawing.Imaging.ImageFormat]::Png)

$g.Dispose(); $bmp.Dispose(); $brush.Dispose(); $gloss.Dispose(); $white.Dispose()
Write-Host "Wrote $out ($Size x $Size)"
