#!/usr/bin/env pwsh
# Build a RELEASE APK against the pre-prod backend and install it to the
# first connected physical phone (wireless or USB). Emulators are skipped.
#
#   Usage:  powershell -ExecutionPolicy Bypass -File scripts\deploy-phone.ps1
#
# Wireless setup (Android 11+), once per phone:
#   Developer options -> Wireless debugging -> Pair device with pairing code
#   adb pair <ip:pairPort> <code>
#   adb connect <ip:connectPort>
param(
  [string]$SupabaseUrl = 'https://pdnrloftybrhuwefmrhp.supabase.co',
  [string]$SupabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InBkbnJsb2Z0eWJyaHV3ZWZtcmhwIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTIxNTU4NjAsImV4cCI6MjEwNzczMTg2MH0.nOggil9woLHuDbiLyk_HPXH1BF-CuDR2EL1pjtgU-S8'
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

Write-Host '==> Devices:' -ForegroundColor Cyan
& $adb devices

# Firebase client config is read from the (git-ignored) google-services.json so
# push notifications work. Without these dart-defines firebase_options.dart
# throws and push stays disabled.
$gsPath = Join-Path $root 'apps\mobile\android\app\google-services.json'
$firebaseDefines = @()
if (Test-Path $gsPath) {
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
  Write-Warning "google-services.json not found; building WITHOUT push (Firebase disabled)."
}

Write-Host '==> Building release APK...' -ForegroundColor Cyan
Push-Location (Join-Path $root 'apps\mobile')
try {
  & $flutter build apk --release `
    --dart-define=SUPABASE_URL=$SupabaseUrl `
    --dart-define=SUPABASE_ANON_KEY=$SupabaseAnonKey `
    @firebaseDefines
} finally {
  Pop-Location
}

$apk = Join-Path $root 'apps\mobile\build\app\outputs\flutter-apk\app-release.apk'
if (-not (Test-Path $apk)) { throw "APK not found: $apk" }

$phone = (& $adb devices) | Select-String -Pattern '\sdevice$' | Where-Object { $_ -notmatch 'emulator-' } | Select-Object -First 1
if (-not $phone) { throw 'No physical device connected (wireless debugging off / screen locked?).' }
$serial = ($phone -split '\s+')[0]

Write-Host "==> Installing to $serial ..." -ForegroundColor Cyan
& $adb -s $serial install -r $apk
Write-Host '==> Done. Launch TeachCross on the phone.' -ForegroundColor Green
