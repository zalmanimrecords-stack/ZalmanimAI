[CmdletBinding()]
param(
  [switch]$SkipClient,
  [switch]$SkipArtistPortal,
  [switch]$SkipServer
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot

function Invoke-Step {
  param(
    [string]$Name,
    [scriptblock]$Action
  )

  Write-Host ""
  Write-Host "==> $Name" -ForegroundColor Cyan
  & $Action
}

function Get-PythonCommand {
  if (Get-Command py -ErrorAction SilentlyContinue) {
    return @("py", "-m")
  }
  if (Get-Command python -ErrorAction SilentlyContinue) {
    return @("python", "-m")
  }
  throw "Python is required to run server tests. Install Python 3 and retry."
}

if (-not $SkipClient) {
  Push-Location (Join-Path $root "apps/client")
  try {
    Invoke-Step "Flutter analyze (client)" { flutter analyze }
    Invoke-Step "Flutter test (client)" { flutter test }
  } finally {
    Pop-Location
  }
}

if (-not $SkipArtistPortal) {
  Push-Location (Join-Path $root "apps/artist_portal")
  try {
    Invoke-Step "Flutter analyze (artist portal)" { flutter analyze }
    Invoke-Step "Flutter test (artist portal)" { flutter test }
  } finally {
    Pop-Location
  }
}

if (-not $SkipServer) {
  $python = Get-PythonCommand
  Push-Location (Join-Path $root "apps/server")
  try {
    Invoke-Step "Pytest (server)" {
      & $python[0] $python[1] pytest
    }
  } finally {
    Pop-Location
  }
}

Write-Host ""
Write-Host "All requested pre-release checks passed." -ForegroundColor Green
