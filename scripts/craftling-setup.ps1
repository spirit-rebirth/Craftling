$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$craftlingRoot = Join-Path $repoRoot ".craftling"
$stateDir = Join-Path $craftlingRoot "state"
$workspaceDir = Join-Path $craftlingRoot "workspace"
$logsDir = Join-Path $craftlingRoot "logs"
$tmpDir = Join-Path $craftlingRoot "tmp"
$configPath = Join-Path $stateDir "openclaw.json"
$logFile = Join-Path $logsDir "openclaw.log"

New-Item -ItemType Directory -Force -Path $stateDir, $workspaceDir, $logsDir, $tmpDir | Out-Null

$env:OPENCLAW_PROFILE = "craftling-dev"
$env:OPENCLAW_STATE_DIR = $stateDir
$env:OPENCLAW_CONFIG_PATH = $configPath
$env:OPENCLAW_GATEWAY_PORT = "19001"
$env:OPENCLAW_SKIP_CHANNELS = "1"

Write-Host "Craftling local state: $stateDir"
Write-Host "Craftling workspace:   $workspaceDir"
Write-Host "Craftling config:      $configPath"

node (Join-Path $repoRoot "openclaw.mjs") --profile craftling-dev onboard `
  --non-interactive `
  --accept-risk `
  --mode local `
  --auth-choice skip `
  --skip-channels `
  --skip-daemon `
  --skip-search `
  --skip-health `
  --no-install-daemon `
  --workspace $workspaceDir `
  --json

$config = Get-Content -Raw -Path $configPath | ConvertFrom-Json
if (-not $config.PSObject.Properties["logging"]) {
  $config | Add-Member -MemberType NoteProperty -Name logging -Value ([pscustomobject]@{})
}
if ($config.logging.PSObject.Properties["file"]) {
  $config.logging.file = $logFile
} else {
  $config.logging | Add-Member -MemberType NoteProperty -Name file -Value $logFile
}
$configJson = $config | ConvertTo-Json -Depth 100
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($configPath, $configJson + [Environment]::NewLine, $utf8NoBom)

Write-Host "Craftling log file:    $logFile"
