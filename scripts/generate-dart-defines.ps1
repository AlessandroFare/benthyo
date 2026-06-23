# Regenerates apps/mobile/dart_defines.local.json from benthyo/.env
# and optionally refreshes keys from `supabase status`.
param(
  [string]$EnvFile = (Join-Path (Join-Path $PSScriptRoot "..") ".env"),
  [switch]$FromSupabaseStatus
)

$mobileDir = Join-Path (Join-Path $PSScriptRoot "..") "apps\mobile"
$output = Join-Path $mobileDir "dart_defines.local.json"

if (-not (Test-Path $EnvFile)) {
  Write-Error "Missing $EnvFile. Copy .env.example to .env first."
  exit 1
}

$vars = @{}
Get-Content $EnvFile | ForEach-Object {
  if ($_ -match '^\s*#' -or $_ -notmatch '=') { return }
  $name, $value = $_ -split '=', 2
  $vars[$name.Trim()] = $value.Trim()
}

$url = $vars['SUPABASE_URL']
$key = $vars['SUPABASE_ANON_KEY']
if (-not $key) { $key = $vars['SUPABASE_PUBLISHABLE_KEY'] }
$api = $vars['API_URL']
if (-not $api) { $api = 'http://localhost:3000/api/v1' }

if ($FromSupabaseStatus) {
  $statusJson = supabase status --output json 2>$null
  if ($LASTEXITCODE -eq 0 -and $statusJson) {
    $status = $statusJson | ConvertFrom-Json
    if ($status.API_URL) { $url = $status.API_URL }
    if ($status.ANON_KEY) { $key = $status.ANON_KEY }
  }
}

if (-not $url -or -not $key) {
  Write-Error ".env must define SUPABASE_URL and SUPABASE_ANON_KEY."
  exit 1
}

if ($url -match '127\.0\.0\.1|localhost' -and $key -match '^sb_publishable_') {
  Write-Warning "Local URL with publishable key is OK, but JWT anon key from 'supabase status' is preferred."
  Write-Warning "Re-run with -FromSupabaseStatus to inject ANON_KEY automatically."
}

if ($url -match 'supabase\.co' -and $key -match '^sb_publishable_ACJWl') {
  Write-Error "Cloud URL with LOCAL publishable key detected. Use keys from the Supabase dashboard for project $url"
  exit 1
}

$json = @{
  SUPABASE_URL = $url
  SUPABASE_PUBLISHABLE_KEY = $key
  API_URL = $api
} | ConvertTo-Json

Set-Content -Path $output -Value $json -Encoding utf8
Write-Host "Wrote $output"
Write-Host "  SUPABASE_URL = $url"
Write-Host "  key prefix   = $($key.Substring(0, [Math]::Min(20, $key.Length)))..."
Write-Host ""
Write-Host "Next:"
Write-Host "  cd apps/mobile"
Write-Host "  flutter run -d edge --dart-define-from-file=dart_defines.local.json"
