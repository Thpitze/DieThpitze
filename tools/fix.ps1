# tools/fix.ps1
# thpitze_main: general reset / multi-fix script (Windows)
#
# One canonical "something is stuck -> reset" entrypoint that we can extend over time.
# Add new fixes as new functions and register them in $FixPipeline.
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File .\tools\fix.ps1
#   powershell -ExecutionPolicy Bypass -File .\tools\fix.ps1 -WhatIf
#   powershell -ExecutionPolicy Bypass -File .\tools\fix.ps1 -SkipId flutter_build_lock,pub_cache
#   powershell -ExecutionPolicy Bypass -File .\tools\fix.ps1 -OnlyId flutter_build_lock
#
# Notes:
#   - Default behavior is safe + targeted (build lock, pub cache repair, clean+get).
#   - This script does NOT modify git state.

[CmdletBinding(SupportsShouldProcess = $true)]
param(
  [string[]]$SkipId = @(),
  [string[]]$OnlyId = @()
)

$ErrorActionPreference = "Stop"

function Write-Section([string]$title) {
  Write-Host ""
  Write-Host "== $title ==" -ForegroundColor Cyan
}

function Get-RepoRoot {
  return (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
}

function Test-ShouldRunFix([string]$id) {
  if ($OnlyId.Count -gt 0) {
    return $OnlyId -contains $id
  }
  return -not ($SkipId -contains $id)
}

function Invoke-FixStep([string]$id, [string]$title, [scriptblock]$action) {
  if (-not (Test-ShouldRunFix $id)) {
    Write-Host "Skipping fix: $id"
    return
  }
  Write-Section "$title  [$id]"
  & $action
}

function Invoke-ExternalCommand {
  [CmdletBinding(SupportsShouldProcess = $true)]
  param(
    [Parameter(Mandatory = $true)][string]$Exe,
    [Parameter(Mandatory = $true)][string[]]$CommandArgs
  )

  $cmd = "$Exe " + ($CommandArgs -join " ")
  if ($PSCmdlet.ShouldProcess($cmd)) {
    & $Exe @CommandArgs | Out-Host
  } else {
    Write-Host "WhatIf: $cmd"
  }
}

function Stop-LockingProcesses {
  [CmdletBinding(SupportsShouldProcess = $true)]
  param()

  Write-Section "Stop common locking processes"
  $procNames = @("flutter_tester", "dart", "dartaotruntime", "gen_snapshot")

  foreach ($p in $procNames) {
    Get-Process -Name $p -ErrorAction SilentlyContinue | ForEach-Object {
      $msg = "Stop-Process $($_.Name) (Id=$($_.Id))"
      if ($PSCmdlet.ShouldProcess($msg)) {
        Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
      } else {
        Write-Host "WhatIf: $msg"
      }
    }
  }

  Start-Sleep -Milliseconds 300
}

function Clear-FileAttributesRecursive {
  [CmdletBinding(SupportsShouldProcess = $true)]
  param(
    [Parameter(Mandatory = $true)][string]$Path
  )

  if (-not (Test-Path $Path)) { return }

  $cmd = "attrib -R `"$Path`" /S /D"
  if ($PSCmdlet.ShouldProcess($cmd)) {
    cmd /c $cmd | Out-Null
  } else {
    Write-Host "WhatIf: $cmd"
  }
}

function Repair-OwnershipAndAcls {
  [CmdletBinding(SupportsShouldProcess = $true)]
  param(
    [Parameter(Mandatory = $true)][string]$Path
  )

  if (-not (Test-Path $Path)) { return }

  $cmd1 = "takeown /F `"$Path`" /R /D Y"
  $cmd2 = "icacls `"$Path`" /grant $env:USERNAME:(OI)(CI)F /T /C"

  if ($PSCmdlet.ShouldProcess($cmd1)) { cmd /c $cmd1 | Out-Null } else { Write-Host "WhatIf: $cmd1" }
  if ($PSCmdlet.ShouldProcess($cmd2)) { cmd /c $cmd2 | Out-Null } else { Write-Host "WhatIf: $cmd2" }
}

function Remove-DirectoryForce {
  [CmdletBinding(SupportsShouldProcess = $true)]
  param(
    [Parameter(Mandatory = $true)][string]$Path
  )

  if (-not (Test-Path $Path)) { return }

  Clear-FileAttributesRecursive -Path $Path

  try {
    if ($PSCmdlet.ShouldProcess("Remove-Item $Path")) {
      Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
    } else {
      Write-Host "WhatIf: Remove-Item -Recurse -Force $Path"
    }
  } catch {
    Write-Host "Remove failed: $Path"
    Write-Host "Attempting ownership/ACL repair..."
    Repair-OwnershipAndAcls -Path $Path
    Clear-FileAttributesRecursive -Path $Path

    if ($PSCmdlet.ShouldProcess("Remove-Item $Path (retry)")) {
      Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
    } else {
      Write-Host "WhatIf: Remove-Item -Recurse -Force $Path (retry)"
    }
  }
}

# -----------------------------
# Fix steps (extend here)
# -----------------------------

function Invoke-FixFlutterBuildLock {
  $root = Get-RepoRoot
  Set-Location $root

  Stop-LockingProcesses

  $unitAssets = Join-Path $root "build\unit_test_assets"
  $buildDir   = Join-Path $root "build"

  if (Test-Path $unitAssets) {
    Write-Host "Removing build\unit_test_assets..."
    Remove-DirectoryForce -Path $unitAssets
  }

  if (Test-Path $buildDir) {
    Write-Host "Removing build..."
    Remove-DirectoryForce -Path $buildDir
  }
}

function Invoke-FixPubCacheRepair {
  Write-Section "flutter pub cache repair"
  Invoke-ExternalCommand -Exe "flutter" -CommandArgs @("pub", "cache", "repair")
}

function Invoke-FixFlutterCleanAndGet {
  $root = Get-RepoRoot
  Set-Location $root

  Write-Section "flutter clean"
  Invoke-ExternalCommand -Exe "flutter" -CommandArgs @("clean")

  Write-Section "flutter pub get"
  Invoke-ExternalCommand -Exe "flutter" -CommandArgs @("pub", "get")
}

function Invoke-FixSmokeCheck {
  Write-Section "Toolchain versions"
  Invoke-ExternalCommand -Exe "flutter" -CommandArgs @("--version")
  Invoke-ExternalCommand -Exe "dart" -CommandArgs @("--version")
}

# ---------------------------------
# Pipeline registry (authoritative)
# ---------------------------------
# To add a new fix:
#   1) create an Invoke-FixXYZ function above
#   2) add one entry here
$FixPipeline = @(
  @{ id = "smoke";              title = "Smoke check";                 action = { Invoke-FixSmokeCheck } },
  @{ id = "flutter_build_lock"; title = "Reset Flutter build lock";    action = { Invoke-FixFlutterBuildLock } },
  @{ id = "pub_cache";          title = "Repair pub cache";            action = { Invoke-FixPubCacheRepair } },
  @{ id = "clean_get";          title = "flutter clean + pub get";     action = { Invoke-FixFlutterCleanAndGet } }
)

# -----------------------------
# Main
# -----------------------------
Write-Section "thpitze_main reset/fix pipeline"
Write-Host "Repo: $(Get-RepoRoot)"
if ($OnlyId.Count -gt 0) { Write-Host "OnlyId: $($OnlyId -join ', ')" }
if ($SkipId.Count -gt 0) { Write-Host "SkipId: $($SkipId -join ', ')" }
if ($WhatIfPreference) { Write-Host "Mode: WhatIf (no changes)" }

foreach ($step in $FixPipeline) {
  Invoke-FixStep -id $step.id -title $step.title -action $step.action
}

Write-Section "Done"
Write-Host "Next: try your command again, e.g. 'flutter test'"
