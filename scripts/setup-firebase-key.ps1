#!/usr/bin/env pwsh
# Wires a Firebase service-account key into the Supabase edge functions.
#
#   powershell -ExecutionPolicy Bypass -File scripts\setup-firebase-key.ps1 `
#       -AdminSdkJson "C:\path\to\teachcross-38f29-firebase-adminsdk-xxxx.json" `
#       [-VisionApiKey "AIza..."]
#
# The key is validated against Google's token endpoint BEFORE it is stored,
# so a stale or mismatched key can never be silently written to the backend.
#
# It also sets GOOGLE_CLOUD_VISION_API_KEY when supplied, which turns on the
# Cloud Vision SafeSearch image classifier.
param(
  [Parameter(Mandatory = $true)]
  [string]$AdminSdkJson,

  [string]$VisionApiKey = '',

  # FCM HTTP v1 accepts the project number or the project id; the number is
  # what the Google Cloud console shows, so it is the default.
  [string]$FcmProjectId = ''
)

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent

if (-not (Test-Path -LiteralPath $AdminSdkJson)) {
  throw "Not found: $AdminSdkJson"
}

$j = Get-Content -LiteralPath $AdminSdkJson -Raw | ConvertFrom-Json
$clientEmail = $j.client_email
$privateKey  = $j.private_key
if (-not $clientEmail -or -not $privateKey) {
  throw "That file does not look like a Firebase Admin SDK key (missing client_email / private_key)."
}
if ($privateKey -notmatch 'BEGIN PRIVATE KEY') {
  throw 'The private_key field is not a PEM block.'
}

# ── Validate the key against Google ──────────────────────────────
# The PEM is written to a temp file so .NET can load it; the JWT is then
# signed with it and exchanged for an access token. If the key has been
# revoked in Google Cloud this fails here, before anything is stored.
Write-Host '==> Validating the key with Google...' -ForegroundColor Cyan
$tmpPem = Join-Path $env:TEMP ('tc-key-' + [guid]::NewGuid().ToString('N') + '.pem')
$tmpKey = Join-Path $env:TEMP ('tc-key-' + [guid]::NewGuid().ToString('N') + '.p12')

try {
  # Normalise to real newlines and write the PEM.
  $normalised = $privateKey -replace "`r`n", "`n"
  [System.IO.File]::WriteAllText($tmpPem, $normalised)

  # The JWT is signed with .NET so no external tooling is needed.
  $b64url = {
    param([string]$s)
    [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($s)).
      TrimEnd('=').Replace('+', '-').Replace('/', '_')
  }
  $now = [int][double]::Parse((Get-Date -UFormat %s))
  $header  = & $b64url '{"alg":"RS256","typ":"JWT"}'
  $claims  = & $b64url ("{`"iss`":`"$clientEmail`",`"scope`":`"https://www.googleapis.com/auth/firebase.messaging`",`"aud`":`"https://oauth2.googleapis.com/token`",`"iat`":$now,`"exp`":$($now + 3600)}")
  $signingInput = "$header.$claims"

  $rsa = [System.Security.Cryptography.RSA]::Create()
  $rsa.ImportFromPem($normalised)
  $sig = $rsa.SignData([Text.Encoding]::UTF8.GetBytes($signingInput), [Security.Cryptography.HashAlgorithmName]::SHA256, [Security.Cryptography.RSASignaturePadding]::Pkcs1)
  $sigB64 = [Convert]::ToBase64String($sig).TrimEnd('=').Replace('+', '-').Replace('/', '_')
  $jwt = "$signingInput.$sigB64"

  $tokenRes = Invoke-RestMethod -Method Post -Uri 'https://oauth2.googleapis.com/token' `
    -ContentType 'application/x-www-form-urlencoded' `
    -Body @{ grant_type = 'urn:ietf:params:oauth:grant-type:jwt-bearer'; assertion = $jwt }
  if (-not $tokenRes.access_token) { throw 'Google did not return an access token.' }
  Write-Host "    OK - Google accepted the key for $clientEmail" -ForegroundColor Green
} catch {
  throw "Google rejected this key: $($_.Exception.Message). Generate a NEW service-account key in Google Cloud (Firebase project -> Service accounts -> Generate new private key) and run this script again."
} finally {
  Remove-Item -LiteralPath $tmpPem, $tmpKey -Force -ErrorAction SilentlyContinue
}

# ── Store the secrets ────────────────────────────────────────────
# The private key is a multi-line PEM. It is stored as ONE argument with
# literal \n escapes: a dotenv file would truncate it at the first newline,
# and the edge function unescapes it on the way in.
$escapedKey = $normalised -replace "`n", '\n'
$projectId = if ($FcmProjectId) { $FcmProjectId } else { $j.project_number }

Write-Host '==> Setting Supabase edge-function secrets...' -ForegroundColor Cyan
$args = @(
  "FCM_PROJECT_ID=$projectId",
  "FCM_CLIENT_EMAIL=$clientEmail",
  "FCM_PRIVATE_KEY=$escapedKey"
)
if ($VisionApiKey) {
  $args += "GOOGLE_CLOUD_VISION_API_KEY=$VisionApiKey"
  Write-Host '    GOOGLE_CLOUD_VISION_API_KEY included (Cloud Vision SafeSearch enabled).' -ForegroundColor Cyan
}

Push-Location $root
try {
  & npx supabase secrets set @args
  if ($LASTEXITCODE -ne 0) { throw "supabase secrets set failed (exit $LASTEXITCODE)" }
} finally {
  Pop-Location
}

Write-Host ''
Write-Host 'Done. The FCM push pipeline and the Cloud Vision image classifier are now live.' -ForegroundColor Green
Write-Host 'Rebuild the mobile app so the client Firebase config matches:' -ForegroundColor Cyan
Write-Host '    powershell -ExecutionPolicy Bypass -File scripts\deploy-phone.ps1' -ForegroundColor Cyan
