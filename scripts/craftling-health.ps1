$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$craftlingRoot = Join-Path $repoRoot ".craftling"
$stateDir = Join-Path $craftlingRoot "state"
$configPath = Join-Path $stateDir "openclaw.json"

$env:OPENCLAW_PROFILE = "craftling-dev"
$env:OPENCLAW_STATE_DIR = $stateDir
$env:OPENCLAW_CONFIG_PATH = $configPath
$env:OPENCLAW_GATEWAY_PORT = "19001"
$env:OPENCLAW_SKIP_CHANNELS = "1"

node (Join-Path $repoRoot "openclaw.mjs") --profile craftling-dev health --json @args
