param(
    [switch]$Rebuild,
    [switch]$CleanVolumes,
    [switch]$NoFlutter,
    [switch]$NoArtistPortal,
    [switch]$NoBrowser,
    [string]$FlutterDevice = "web-server",
    [string]$FlutterTarget = "lib/main.dart",
    [string]$WebHost = "127.0.0.1",
    [int]$WebPort = 3000,
    [int]$ArtistPortalPort = 3001
)

$ErrorActionPreference = "Stop"

$root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
Set-Location $root

# Ports used by the dev system: Admin (3000), Artist portal (3001), API (8000), Postgres (5432).
# Cleaning them before start avoids "address already in use" when a previous run left a process bound.
$PortsToClean = @(3000, 3001, 8000, 5432)

function Stop-ProcessesOnPort {
    param([Parameter(Mandatory = $true)][int]$Port)

    $pids = @()
    try {
        $output = netstat -ano 2>$null
        foreach ($line in $output) {
            # Match lines like "TCP    127.0.0.1:3000    ...    LISTENING    25612"
            if ($line -match ":$Port\s+" -and $line -match "LISTENING\s+(\d+)\s*$") {
                $pidVal = [int]$Matches[1]
                if ($pidVal -gt 0) { $pids += $pidVal }
            }
        }
    }
    catch {
        return
    }

    $pids = $pids | Sort-Object -Unique
    foreach ($pidVal in $pids) {
        try {
            $proc = Get-Process -Id $pidVal -ErrorAction SilentlyContinue
            if ($proc) {
                Write-Host "  Killing process $pidVal ($($proc.ProcessName)) on port $Port" -ForegroundColor Gray
            }
            Stop-Process -Id $pidVal -Force -ErrorAction SilentlyContinue
        }
        catch {
            # Ignore; process may already be gone
        }
    }
}

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

Invoke-Step -Name "Cleaning dev ports (3000, 3001, 8000, 5432)" -Action {
    foreach ($p in $PortsToClean) {
        Stop-ProcessesOnPort -Port $p
    }
    Start-Sleep -Milliseconds 500
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
    $maxAttempts = 45
    $attempt = 0
    $healthy = $false
    $lastError = $null

    while (-not $healthy -and $attempt -lt $maxAttempts) {
        $attempt++
        try {
            $response = Invoke-RestMethod -Uri "http://127.0.0.1:8000/health" -TimeoutSec 5
            if ($response -and $response.status -eq "ok") {
                $healthy = $true
                break
            }
        }
        catch {
            $lastError = $_
            if ($attempt -eq 1 -or $attempt % 5 -eq 0) {
                Write-Host "  Waiting for API... attempt $attempt/$maxAttempts" -ForegroundColor Gray
            }
            Start-Sleep -Seconds 2
        }
    }

    if (-not $healthy) {
        $msg = "API health check failed after $maxAttempts attempts. Ensure Docker is running and ports 8000/5432 are free."
        if ($lastError) {
            $msg += " Last error: $($lastError.Exception.Message)"
        }
        throw $msg
    }
}

if (-not $NoFlutter) {
    Assert-CommandExists -CommandName "flutter"

    Invoke-Step -Name "Preparing Flutter dependencies" -Action {
        Push-Location (Join-Path $root "apps/client")
        try {
            flutter pub get
        }
        finally {
            Pop-Location
        }
    }

    Invoke-Step -Name "Launching admin app (flutter run -d $FlutterDevice)" -Action {
        $clientDir = Join-Path $root "apps\client"
        $cmd = "Set-Location -LiteralPath '$clientDir'; flutter run -d $FlutterDevice --target $FlutterTarget"
        if ($FlutterDevice -eq "web-server") {
            $cmd += " --web-hostname $WebHost --web-port $WebPort"
        }
        Start-Process -FilePath "powershell.exe" -ArgumentList "-NoExit", "-Command", $cmd | Out-Null
    }

    if ($FlutterDevice -eq "web-server" -and -not $NoBrowser) {
        Invoke-Step -Name "Opening browser for Flutter web app" -Action {
            $maxAttempts = 30
            $attempt = 0
            $webUrl = "http://${WebHost}:${WebPort}"
            $ready = $false

            while (-not $ready -and $attempt -lt $maxAttempts) {
                $attempt++
                try {
                    $response = Invoke-WebRequest -Uri $webUrl -TimeoutSec 5 -UseBasicParsing
                    if ($response.StatusCode -ge 200 -and $response.StatusCode -lt 500) {
                        $ready = $true
                        break
                    }
                }
                catch {
                    Start-Sleep -Seconds 2
                }
            }

            if (-not $ready) {
                throw "Flutter web server did not become ready on $webUrl."
            }

            Start-Process $webUrl | Out-Null
        }
    }
}

if (-not $NoFlutter -and -not $NoArtistPortal) {
    Assert-CommandExists -CommandName "flutter"

    Invoke-Step -Name "Preparing Artist Portal dependencies" -Action {
        Push-Location (Join-Path $root "apps/artist_portal")
        try {
            flutter pub get
        }
        finally {
            Pop-Location
        }
    }

    Invoke-Step -Name "Launching Artist Portal (flutter run -d $FlutterDevice)" -Action {
        $portalDir = Join-Path $root "apps\artist_portal"
        $cmd = "Set-Location -LiteralPath '$portalDir'; flutter run -d $FlutterDevice --target lib/main.dart"
        if ($FlutterDevice -eq "web-server") {
            $cmd += " --web-hostname $WebHost --web-port $ArtistPortalPort"
        }
        Start-Process -FilePath "powershell.exe" -ArgumentList "-NoExit", "-Command", $cmd | Out-Null
    }

    if ($FlutterDevice -eq "web-server" -and -not $NoBrowser) {
        Invoke-Step -Name "Opening browser for Artist Portal" -Action {
            $maxAttempts = 30
            $attempt = 0
            $portalUrl = "http://${WebHost}:${ArtistPortalPort}"
            $ready = $false

            while (-not $ready -and $attempt -lt $maxAttempts) {
                $attempt++
                try {
                    $response = Invoke-WebRequest -Uri $portalUrl -TimeoutSec 5 -UseBasicParsing
                    if ($response.StatusCode -ge 200 -and $response.StatusCode -lt 500) {
                        $ready = $true
                        break
                    }
                }
                catch {
                    Start-Sleep -Seconds 2
                }
            }

            if (-not $ready) {
                throw "Artist Portal web server did not become ready on $portalUrl."
            }

            Start-Process $portalUrl | Out-Null
        }
    }
}

Write-Host "`nSystem restart completed." -ForegroundColor Green
Write-Host "API: http://localhost:8000" -ForegroundColor Yellow
Write-Host "MinIO Console: http://localhost:9001" -ForegroundColor Yellow
if (-not $NoFlutter) {
    if ($FlutterDevice -eq "web-server") {
        Write-Host "Admin app: $([string]::Format('http://{0}:{1}', $WebHost, $WebPort))" -ForegroundColor Yellow
    }
    else {
        Write-Host "Admin app: Flutter client launched in new window (flutter run -d $FlutterDevice)" -ForegroundColor Yellow
    }
}
if (-not $NoArtistPortal) {
    if ($FlutterDevice -eq "web-server") {
        Write-Host "Artist portal: $([string]::Format('http://{0}:{1}', $WebHost, $ArtistPortalPort))" -ForegroundColor Yellow
    }
    else {
        Write-Host "Artist portal: Flutter client launched in new window" -ForegroundColor Yellow
    }
}
