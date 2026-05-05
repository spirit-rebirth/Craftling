$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$craftlingRoot = Join-Path $repoRoot ".craftling"
$stateDir = Join-Path $craftlingRoot "state"
$workspaceDir = Join-Path $craftlingRoot "workspace"
$logsDir = Join-Path $craftlingRoot "logs"
$tmpDir = Join-Path $craftlingRoot "tmp"
$configPath = Join-Path $stateDir "openclaw.json"
$logFile = Join-Path $logsDir "openclaw.log"
$productRoot = Join-Path $repoRoot "product\craftling"
$productSkillsDir = Join-Path $productRoot "workspace\skills"
$unrealAgentBridgePluginDir = Join-Path $productRoot "plugins\openclaw-unreal-agentbridge"
$unrealToolAllowList = @(
  "lobster",
  "unreal-agentbridge",
  "ue_health",
  "ue_list_actors",
  "ue_spawn_actor",
  "ue_delete_actor",
  "ue_modify_actor",
  "ue_pie_start",
  "ue_pie_stop",
  "ue_pie_status",
  "ue_world_query",
  "ue_logs_tail",
  "ue_test_status",
  "ue_test_results",
  "ue_build",
  "ue_editor_open"
)

function Set-JsonProperty {
  param(
    [Parameter(Mandatory = $true)] [object] $Object,
    [Parameter(Mandatory = $true)] [string] $Name,
    [Parameter(Mandatory = $true)] $Value
  )

  if ($Object.PSObject.Properties[$Name]) {
    $Object.PSObject.Properties[$Name].Value = $Value
  } else {
    $Object | Add-Member -MemberType NoteProperty -Name $Name -Value $Value
  }
}

function Set-JsonDefaultProperty {
  param(
    [Parameter(Mandatory = $true)] [object] $Object,
    [Parameter(Mandatory = $true)] [string] $Name,
    [Parameter(Mandatory = $true)] $Value
  )

  if (-not $Object.PSObject.Properties[$Name] -or $null -eq $Object.PSObject.Properties[$Name].Value -or $Object.PSObject.Properties[$Name].Value -eq "") {
    Set-JsonProperty -Object $Object -Name $Name -Value $Value
  }
}

function Ensure-JsonObject {
  param(
    [Parameter(Mandatory = $true)] [object] $Object,
    [Parameter(Mandatory = $true)] [string] $Name
  )

  if (-not $Object.PSObject.Properties[$Name] -or $null -eq $Object.PSObject.Properties[$Name].Value) {
    Set-JsonProperty -Object $Object -Name $Name -Value ([pscustomobject]@{})
  }

  return $Object.PSObject.Properties[$Name].Value
}

function Add-UniqueString {
  param(
    [AllowNull()] $Items,
    [Parameter(Mandatory = $true)] [string] $Value
  )

  $result = @()
  foreach ($item in @($Items)) {
    if ($null -ne $item -and [string]$item -ne "" -and $result -notcontains [string]$item) {
      $result += [string]$item
    }
  }
  if ($result -notcontains $Value) {
    $result += $Value
  }
  return @($result)
}

New-Item -ItemType Directory -Force -Path $stateDir, $workspaceDir, $logsDir, $tmpDir | Out-Null

$env:OPENCLAW_PROFILE = "craftling-dev"
$env:OPENCLAW_STATE_DIR = $stateDir
$env:OPENCLAW_CONFIG_PATH = $configPath
$env:OPENCLAW_GATEWAY_PORT = "19001"
$env:OPENCLAW_SKIP_CHANNELS = "1"

Write-Host "Craftling local state: $stateDir"
Write-Host "Craftling workspace:   $workspaceDir"
Write-Host "Craftling config:      $configPath"

if (Test-Path $configPath) {
  Write-Host "Existing Craftling config found; preserving local settings and merging fixed repo settings."
} else {
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
}

$config = Get-Content -Raw -Path $configPath | ConvertFrom-Json
if (-not $config.PSObject.Properties["logging"]) {
  $config | Add-Member -MemberType NoteProperty -Name logging -Value ([pscustomobject]@{})
}
if ($config.logging.PSObject.Properties["file"]) {
  $config.logging.file = $logFile
} else {
  $config.logging | Add-Member -MemberType NoteProperty -Name file -Value $logFile
}

$skills = Ensure-JsonObject -Object $config -Name "skills"
$skillsLoad = Ensure-JsonObject -Object $skills -Name "load"
$extraSkillDirs = @()
if ($skillsLoad.PSObject.Properties["extraDirs"]) {
  $extraSkillDirs = @($skillsLoad.extraDirs)
}
$extraSkillDirs = @(Add-UniqueString -Items $extraSkillDirs -Value $productSkillsDir)
Set-JsonProperty -Object $skillsLoad -Name "extraDirs" -Value $extraSkillDirs

$plugins = Ensure-JsonObject -Object $config -Name "plugins"
$pluginsLoad = Ensure-JsonObject -Object $plugins -Name "load"
$pluginPaths = @()
if ($pluginsLoad.PSObject.Properties["paths"]) {
  $pluginPaths = @($pluginsLoad.paths)
}
$pluginPaths = @(Add-UniqueString -Items $pluginPaths -Value $unrealAgentBridgePluginDir)
Set-JsonProperty -Object $pluginsLoad -Name "paths" -Value $pluginPaths

$pluginEntries = Ensure-JsonObject -Object $plugins -Name "entries"
$lobsterEntry = Ensure-JsonObject -Object $pluginEntries -Name "lobster"
Set-JsonProperty -Object $lobsterEntry -Name "enabled" -Value $true

$unrealAgentBridgeEntry = Ensure-JsonObject -Object $pluginEntries -Name "unreal-agentbridge"
Set-JsonProperty -Object $unrealAgentBridgeEntry -Name "enabled" -Value $true
$unrealAgentBridgeConfig = Ensure-JsonObject -Object $unrealAgentBridgeEntry -Name "config"
Set-JsonDefaultProperty -Object $unrealAgentBridgeConfig -Name "baseUrl" -Value "http://127.0.0.1:8080"
Set-JsonDefaultProperty -Object $unrealAgentBridgeConfig -Name "defaultBuildPlatform" -Value "Win64"
Set-JsonDefaultProperty -Object $unrealAgentBridgeConfig -Name "defaultBuildConfiguration" -Value "Development"

$agents = Ensure-JsonObject -Object $config -Name "agents"
$agentDefaults = Ensure-JsonObject -Object $agents -Name "defaults"
Set-JsonProperty -Object $agentDefaults -Name "skipBootstrap" -Value $true

$agentList = @()
if ($agents.PSObject.Properties["list"] -and $null -ne $agents.list) {
  $agentList = @($agents.list)
}
$mainAgent = $agentList | Where-Object { $_.id -eq "main" } | Select-Object -First 1
if (-not $mainAgent) {
  $mainAgent = [pscustomobject]@{ id = "main"; tools = [pscustomobject]@{} }
  $agentList += $mainAgent
}
$mainAgentTools = Ensure-JsonObject -Object $mainAgent -Name "tools"
$alsoAllow = @()
if ($mainAgentTools.PSObject.Properties["alsoAllow"]) {
  $alsoAllow = @($mainAgentTools.alsoAllow)
}
foreach ($toolName in $unrealToolAllowList) {
  $alsoAllow = @(Add-UniqueString -Items $alsoAllow -Value $toolName)
}
Set-JsonProperty -Object $mainAgentTools -Name "alsoAllow" -Value $alsoAllow
Set-JsonProperty -Object $agents -Name "list" -Value @($agentList)

$configJson = $config | ConvertTo-Json -Depth 100
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($configPath, $configJson + [Environment]::NewLine, $utf8NoBom)

Write-Host "Craftling log file:    $logFile"
Write-Host "Craftling skills:      $productSkillsDir"
Write-Host "Craftling UE plugin:   $unrealAgentBridgePluginDir"
Write-Host "UE machine paths are intentionally left for the Craftling app settings."
