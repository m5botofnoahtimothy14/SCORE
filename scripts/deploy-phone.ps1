#!/usr/bin/env pwsh
# Build a RELEASE APK against the live backend and install it to the first
# connected physical phone (wireless or USB). Emulators are skipped.
#
#   Usage:  powershell -ExecutionPolicy Bypass -File scripts\deploy-phone.ps1
#
# Backend coordinates are read from apps\admin\.env.local so the app and the
# admin console can never drift apart. Override with -SupabaseUrl /
# -SupabaseAnonKey if needed.
#
# Wireless setup (Android 11+), once per phone:
#   Developer options -> Wireless debugging -> Pair device with pairing code
#   adb pair <ip:pairPort> <code>
#   adb connect <ip:connectPort>
param(
  [string]$SupabaseUrl = '',
  [string]$SupabaseAnonKey = '',
  [switch]$SkipInstall
)

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$flutter = 'D:\dev\flutter\bin\flutter.bat'
$adb = 'D:\dev\android-sdk\platform-tools\adb.exe'

$env:JAVA_HOME = 'D:\dev\jdk17'
$env:ANDROID_SDK_ROOT = 'D:\dev\android-sdk'
$env:ANDROID_USER_HOME = 'D:\dev\.android'
$env:GRADLE_USER_HOME = 'D:\dev\.gradle'
$env:PUB_CACHE = 'D:\dev\pub-cache'

# -- Backend coordinates --------------------------------------------
$envFile = Join-Path $root 'apps\admin\.env.local'
if ((-not $SupabaseUrl) -or (-not $SupabaseAnonKey)) {
  if (-not (Test-Path -LiteralPath $envFile)) {
    throw "Missing $envFile - cannot resolve the Supabase URL/anon key."
  }
  foreach ($line in Get-Content -LiteralPath $envFile) {
    if ($line -match '^([A-Z0-9_]+)=(.*)$') {
      $k = $Matches[1]
      $v = $Matches[2].Trim().Trim('"')
      if ($k -eq 'NEXT_PUBLIC_SUPABASE_URL' -and (-not $SupabaseUrl)) { $SupabaseUrl = $v }
      if ($k -eq 'NEXT_PUBLIC_SUPABASE_ANON_KEY' -and (-not $SupabaseAnonKey)) { $SupabaseAnonKey = $v }
    }
  }
}
if (-not $SupabaseUrl -or -not $SupabaseAnonKey) {
  throw 'Could not resolve NEXT_PUBLIC_SUPABASE_URL / NEXT_PUBLIC_SUPABASE_ANON_KEY.'
}
Write-Host "==> Backend: $SupabaseUrl" -ForegroundColor Cyan

Write-Host '==> Devices:' -ForegroundColor Cyan
& $adb devices

# -- Firebase client config -----------------------------------------
# Read from the (git-ignored) google-services.json so push notifications
# work. Without these dart-defines firebase_options.dart throws and push
# stays disabled.
$gsPath = Join-Path $root 'apps\mobile\android\app\google-services.json'
$firebaseDefines = @()
if (Test-Path -LiteralPath $gsPath) {
  $gs = Get-Content -LiteralPath $gsPath -Raw | ConvertFrom-Json
  $client = $gs.client | Select-Object -First 1
  $firebaseDefines = @(
    "--dart-define=FIREBASE_API_KEY=$($client.api_key[0].current_key)",
    "--dart-define=FIREBASE_APP_ID=$($client.client_info.mobilesdk_app_id)",
    "--dart-define=FIREBASE_SENDER_ID=$($gs.project_info.project_number)",
    "--dart-define=FIREBASE_PROJECT_ID=$($gs.project_info.project_id)"
  )
  Write-Host "==> Firebase: project $($gs.project_info.project_id)" -ForegroundColor Cyan
} else {
  Write-Warning 'google-services.json not found; building WITHOUT push (Firebase disabled).'
}

# -- Release signing -------------------------------------------------
$keyProps = Join-Path $root 'apps\mobile\android\key.properties'
if (Test-Path -LiteralPath $keyProps) {
  Write-Host '==> Release signing: key.properties present (release key)' -ForegroundColor Cyan
} else {
  Write-Warning 'key.properties missing - the APK will be signed with the debug key and CANNOT be published.'
}

Write-Host '==> Building release APK...' -ForegroundColor Cyan
Push-Location (Join-Path $root 'apps\mobile')
try {
  & $flutter build apk --release `
    --dart-define=SUPABASE_URL=$SupabaseUrl `
    --dart-define=SUPABASE_ANON_KEY=$SupabaseAnonKey `
    @firebaseDefines
  if ($LASTEXITCODE -ne 0) { throw "flutter build apk failed (exit $LASTEXITCODE)" }
} finally {
  Pop-Location
}

$apk = Join-Path $root 'apps\mobile\build\app\outputs\flutter-apk\app-release.apk'
if (-not (Test-Path -LiteralPath $apk)) { throw "APK not found: $apk" }
$sizeMb = [math]::Round((Get-Item -LiteralPath $apk).Length / 1MB, 1)
Write-Host "==> APK: $apk ($sizeMb MB)" -ForegroundColor Cyan

if ($SkipInstall) { Write-Host '==> Build only (-SkipInstall).'; exit 0 }

$phone = (& $adb devices) | Select-String -Pattern '\sdevice$' | Where-Object { $_ -notmatch 'emulator-' } | Select-Object -First 1
if (-not $phone) { throw 'No physical device connected (wireless debugging off / screen locked?).' }
$serial = ($phone -split '\s+')[0]

Write-Host "==> Installing to $serial ..." -ForegroundColor Cyan
& $adb -s $serial install -r $apk
if ($LASTEXITCODE -ne 0) { throw "adb install failed (exit $LASTEXITCODE)" }

Write-Host '==> Launching TeachCross...' -ForegroundColor Cyan
& $adb -s $serial shell monkey -p com.teachcross.app -c android.intent.category.LAUNCHER 1 | Out-Null
Write-Host '==> Done.' -ForegroundColor Green
