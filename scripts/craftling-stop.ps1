$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$craftlingRoot = Join-Path $repoRoot ".craftling"
$stateDir = Join-Path $craftlingRoot "state"
$configPath = Join-Path $stateDir "openclaw.json"

$env:OPENCLAW_PROFILE = "craftling-dev"
$env:OPENCLAW_STATE_DIR = $stateDir
$env:OPENCLAW_CONFIG_PATH = $configPath
$env:OPENCLAW_GATEWAY_PORT = "19001"

function Get-CraftlingListenerProcesses {
  Get-NetTCPConnection -LocalPort $ownedPorts -State Listen -ErrorAction SilentlyContinue |
    Where-Object { $_.OwningProcess -gt 0 } |
    Select-Object -ExpandProperty OwningProcess -Unique
}

function Wait-CraftlingPortsFree {
  param([int]$TimeoutMilliseconds = 5000)

  $deadline = [DateTime]::UtcNow.AddMilliseconds($TimeoutMilliseconds)
  do {
    $listeners = @(Get-CraftlingListenerProcesses)
    if ($listeners.Count -eq 0) {
      return $true
    }
    Start-Sleep -Milliseconds 200
  } while ([DateTime]::UtcNow -lt $deadline)

  return @(Get-CraftlingListenerProcesses).Count -eq 0
}

function Get-NodeProcessTreeRoots {
  param([int[]]$ListenerPids)

  $roots = @()
  foreach ($listenerPid in $ListenerPids) {
    $listener = Get-Process -Id $listenerPid -ErrorAction SilentlyContinue
    if ($listener -and $listener.ProcessName -eq "node") {
      $roots += [int]$listenerPid
    }

    $processInfo = Get-CimInstance Win32_Process -Filter "ProcessId=$listenerPid" -ErrorAction SilentlyContinue
    $parentPid = $processInfo.ParentProcessId
    if ($parentPid) {
      $parent = Get-Process -Id $parentPid -ErrorAction SilentlyContinue
      if ($parent -and $parent.ProcessName -eq "node") {
        $roots += [int]$parentPid
      }
    }
  }

  $roots | Select-Object -Unique
}

function Stop-ProcessTree {
  param([int[]]$ProcessIds)

  foreach ($processId in $ProcessIds) {
    $process = Get-Process -Id $processId -ErrorAction SilentlyContinue
    if (-not $process) {
      continue
    }

    & taskkill.exe /T /PID $processId | Out-Null
  }

  if (Wait-CraftlingPortsFree -TimeoutMilliseconds 3000) {
    return
  }

  foreach ($processId in $ProcessIds) {
    $process = Get-Process -Id $processId -ErrorAction SilentlyContinue
    if (-not $process) {
      continue
    }

    & taskkill.exe /F /T /PID $processId | Out-Null
  }
}

$ownedPorts = @(19001, 19003)
$stopExitCode = 0
& node (Join-Path $repoRoot "openclaw.mjs") --profile craftling-dev gateway stop @args
if ($LASTEXITCODE -ne $null) {
  $stopExitCode = $LASTEXITCODE
}

$listeners = @(Get-CraftlingListenerProcesses)

if ($listeners.Count -gt 0) {
  $nodeTreeRoots = @(Get-NodeProcessTreeRoots -ListenerPids $listeners)

  if ($nodeTreeRoots.Count -gt 0) {
    Write-Host "Stopping Craftling dev process tree root(s): $($nodeTreeRoots -join ', ')"
    Stop-ProcessTree -ProcessIds $nodeTreeRoots
    [void](Wait-CraftlingPortsFree -TimeoutMilliseconds 5000)
  }
}

$remainingListeners = @(
  Get-NetTCPConnection -LocalPort $ownedPorts -State Listen -ErrorAction SilentlyContinue |
    Where-Object { $_.OwningProcess -gt 0 }
)

if ($remainingListeners.Count -gt 0) {
  $details = ($remainingListeners | ForEach-Object {
    "$($_.LocalAddress):$($_.LocalPort) pid=$($_.OwningProcess)"
  }) -join "; "
  throw "Craftling Gateway ports are still busy after stop: $details"
}

if ($stopExitCode -ne 0) {
  Write-Host "Craftling dev Gateway ports released after OpenClaw stop returned exit code $stopExitCode."
}
