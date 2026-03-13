# Show what commit you're on locally vs what origin has (what the server gets with git pull).
# Run from repo root. If Local and Origin differ, push first then deploy.

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot\..

$branch = git branch --show-current
$localLine = git log -1 --oneline
$originRef = "origin/$branch"
$hasOrigin = git rev-parse $originRef 2>$null
$originLine = if ($hasOrigin) { git log -1 --oneline $originRef } else { "(no $originRef)" }

Write-Host "Branch:  $branch"
Write-Host "Local:   $localLine"
Write-Host "Origin:  $originLine"
Write-Host ""

if ($hasOrigin) {
    $localHash = git rev-parse HEAD
    $originHash = git rev-parse $originRef
    if ($localHash -eq $originHash) {
        Write-Host "OK: Local and origin match. Server gets this after deploy." -ForegroundColor Green
    } else {
        $ahead = (git rev-list --count $originRef..HEAD 2>$null) -or 0
        $behind = (git rev-list --count HEAD..$originRef 2>$null) -or 0
        if ($ahead -gt 0) { Write-Host "Push needed: $ahead commit(s) not on origin. Run: git push origin $branch" -ForegroundColor Yellow }
        if ($behind -gt 0) { Write-Host "Pull needed: origin is $behind commit(s) ahead." -ForegroundColor Yellow }
    }
}
Write-Host ""
Write-Host "To update server: .\scripts\deploy-prod-remote.ps1"
