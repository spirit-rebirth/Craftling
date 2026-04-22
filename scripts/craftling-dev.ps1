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

Write-Host "Starting Craftling dev Gateway on ws://127.0.0.1:19001"
Write-Host "State:     $stateDir"
Write-Host "Workspace: $workspaceDir"
Write-Host "Log file:  $logFile"

$previousErrorActionPreference = $ErrorActionPreference
$ErrorActionPreference = "Continue"
try {
  & node (Join-Path $repoRoot "openclaw.mjs") --profile craftling-dev gateway --verbose @args 2>&1 |
    Tee-Object -FilePath $logFile -Append
  if ($LASTEXITCODE -ne $null -and $LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
  }
} finally {
  $ErrorActionPreference = $previousErrorActionPreference
}
