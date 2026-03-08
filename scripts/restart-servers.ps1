# Restart backend servers only (no Flutter app).
# Use restart-system.ps1 to also launch the Windows client.

param(
    [switch]$Rebuild,
    [switch]$CleanVolumes
)

$ErrorActionPreference = "Stop"

$root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
Set-Location $root

function Assert-CommandExists {
    param([Parameter(Mandatory = $true)][string]$CommandName)

    if (-not (Get-Command $CommandName -ErrorAction SilentlyContinue)) {
        throw "Required command not found: $CommandName"
    }
}

function Invoke-Step {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][scriptblock]$Action
    )

    Write-Host "[STEP] $Name" -ForegroundColor Cyan
    & $Action
    Write-Host "[OK]   $Name" -ForegroundColor Green
}

Assert-CommandExists -CommandName "docker"

$downArgs = @()
if ($CleanVolumes) {
    $downArgs = @("--volumes", "--remove-orphans")
}
Invoke-Step -Name "Stopping existing containers" -Action {
    docker compose down @downArgs
}

Invoke-Step -Name "Starting backend stack" -Action {
    if ($Rebuild) {
        try {
            docker compose build
        }
        catch {
            Write-Host "[WARN] Build failed. Attempting image cleanup and retry..." -ForegroundColor Yellow
            docker image rm -f zalmanimai-api:latest 2>$null
            docker image rm -f zalmanimai-worker:latest 2>$null
            docker compose build
        }
        docker compose up -d
    }
    else {
        docker compose up -d
    }
}

Invoke-Step -Name "Checking API health" -Action {
    $maxAttempts = 20
    $attempt = 0
    $healthy = $false

    while (-not $healthy -and $attempt -lt $maxAttempts) {
        $attempt++
        try {
            $response = Invoke-RestMethod -Uri "http://localhost:8000/health" -TimeoutSec 5
            if ($response -and $response.status -eq "ok") {
                $healthy = $true
                break
            }
        }
        catch {
            Start-Sleep -Seconds 2
        }
    }

    if (-not $healthy) {
        throw "API health check failed after $maxAttempts attempts. Ensure Docker is running and ports 8000/5432 are free."
    }
}

Write-Host "`nServers restart completed." -ForegroundColor Green
Write-Host "API: http://localhost:8000" -ForegroundColor Yellow
Write-Host "MinIO Console: http://localhost:9001" -ForegroundColor Yellow
