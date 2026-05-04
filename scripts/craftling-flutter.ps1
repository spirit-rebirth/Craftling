param(
  [string]$Device = "windows"
)

$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$appDir = Join-Path $repoRoot "apps\craftling_flutter"

if (-not (Test-Path -LiteralPath $appDir)) {
  throw "Craftling Flutter app not found at $appDir"
}

function Resolve-FlutterCommand {
  if ($env:CRAFTLING_FLUTTER_BIN) {
    if (Test-Path -LiteralPath $env:CRAFTLING_FLUTTER_BIN) {
      return $env:CRAFTLING_FLUTTER_BIN
    }
    throw "CRAFTLING_FLUTTER_BIN points to a missing file: $env:CRAFTLING_FLUTTER_BIN"
  }

  if ($env:FLUTTER_ROOT) {
    $fromRoot = Join-Path $env:FLUTTER_ROOT "bin\flutter.bat"
    if (Test-Path -LiteralPath $fromRoot) {
      return $fromRoot
    }
    throw "FLUTTER_ROOT does not contain bin\flutter.bat: $env:FLUTTER_ROOT"
  }

  $fromPath = Get-Command flutter -ErrorAction SilentlyContinue
  if ($fromPath) {
    return $fromPath.Source
  }

  throw "Flutter was not found. Add Flutter to PATH, or set CRAFTLING_FLUTTER_BIN / FLUTTER_ROOT."
}

$flutter = Resolve-FlutterCommand

Write-Host "Starting Craftling Flutter app from $appDir"
Write-Host "Flutter: $flutter"
Write-Host "Device:  $Device"

Push-Location $appDir
try {
  & $flutter pub get
  if ($LASTEXITCODE -ne $null -and $LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
  }

  & $flutter run -d $Device
  if ($LASTEXITCODE -ne $null -and $LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
  }
} finally {
  Pop-Location
}
