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
  if ($LASTEXITCODE -ne 0) {
    throw "$Name failed with exit code $LASTEXITCODE."
  }
}

function Get-PythonCommand {
  if (Get-Command py -ErrorAction SilentlyContinue) {
    try {
      & py -m pytest --version *> $null
    } catch {
      $global:LASTEXITCODE = 1
    }
    if ($LASTEXITCODE -eq 0) {
      return @{
        Mode = "Local"
        Command = @("py", "-m")
      }
    }
  }
  if (Get-Command python -ErrorAction SilentlyContinue) {
    try {
      & python -m pytest --version *> $null
    } catch {
      $global:LASTEXITCODE = 1
    }
    if ($LASTEXITCODE -eq 0) {
      return @{
        Mode = "Local"
        Command = @("python", "-m")
      }
    }
  }
  if (Get-Command "C:\Program Files\Docker\Docker\resources\bin\docker.exe" -ErrorAction SilentlyContinue) {
    return @{
      Mode = "Docker"
      Command = @("C:\Program Files\Docker\Docker\resources\bin\docker.exe")
    }
  }
  throw "Server tests require Python 3 or Docker."
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
  if ($python.Mode -eq "Local") {
    Push-Location (Join-Path $root "apps/server")
    try {
      Invoke-Step "Pytest (server)" {
        & $python.Command[0] $python.Command[1] pytest
      }
    } finally {
      Pop-Location
    }
  } else {
    Invoke-Step "Pytest (server via Docker)" {
      & $python.Command[0] run --rm `
        -v "${root}:/work" `
        -w /work/apps/server `
        -e PYTHONPATH=/work/apps/server `
        python:3.12-slim `
        bash -lc "pip install -r requirements-dev.txt >/tmp/pip.log && pytest -q"
    }
  }
}

Write-Host ""
Write-Host "All requested pre-release checks passed." -ForegroundColor Green
