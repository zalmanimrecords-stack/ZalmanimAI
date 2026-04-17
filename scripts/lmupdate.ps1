# lmupdate: Push all latest changes to GitHub, then update the PROD server.
# Run from repo root: .\scripts\lmupdate.ps1
# Git push uses your SSH config (e.g. ~/.ssh/config: github.com -> id_ed25519_github).
# Deploy to VPS uses Resolve-HostingerSshKey.ps1: LMUPDATE_SSH_KEY, else hostinger_vps, else hostinger_vps_codex.
# Optional: $env:LMUPDATE_COMMIT_MSG = "Your message"
# Optional: $env:LMUPDATE_SSH_KEY = "C:\Users\...\.ssh\your_key"  # for deploy only (VPS)
# Optional: $env:PROD_REPO_PATH = "/path/on/vps"  (default /root/ZalmanimAI)
# Optional: $env:LMUPDATE_SKIP_DEPLOY = "1" to push only (no server update)

$ErrorActionPreference = "Stop"
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
. (Join-Path $PSScriptRoot "Resolve-HostingerSshKey.ps1")
$sshKey = Get-HostingerSshKeyPath
if (-not $sshKey) {
    Write-Error "No Hostinger SSH private key found. Use hostinger_vps or hostinger_vps_codex under $($env:USERPROFILE)\.ssh\, or set LMUPDATE_SSH_KEY."
    exit 1
}

Push-Location $repoRoot
try {
    Write-Host "[lmupdate] Step 1: Git status" -ForegroundColor Cyan
    $status = git status --porcelain
    $hasChanges = $status -ne $null -and $status.Count -gt 0

    if ($hasChanges) {
        git add -A
        $msg = if ($env:LMUPDATE_COMMIT_MSG) { $env:LMUPDATE_COMMIT_MSG } else { "Update" }
        Write-Host "[lmupdate] Committing and pushing to GitHub..." -ForegroundColor Cyan
        git commit -m "$msg"
        if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    } else {
        Write-Host "[lmupdate] No local changes to commit." -ForegroundColor Gray
    }

    Write-Host "[lmupdate] Pushing to GitHub..." -ForegroundColor Cyan
    # Use default SSH config (e.g. github.com -> id_ed25519_github) so push has write access.
    # Do not set GIT_SSH_COMMAND here; deploy-prod-remote.ps1 uses hostinger_vps only for the VPS.
    git push
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[lmupdate] Push failed." -ForegroundColor Red
        exit $LASTEXITCODE
    }
    Write-Host "[lmupdate] GitHub push done." -ForegroundColor Green
    Write-Host "[lmupdate] VPS SSH key: $sshKey" -ForegroundColor Gray

    if ($env:LMUPDATE_SKIP_DEPLOY -eq "1") {
        Write-Host "[lmupdate] Skipping server update (LMUPDATE_SKIP_DEPLOY=1)." -ForegroundColor Yellow
        exit 0
    }

    Write-Host "[lmupdate] Step 2: Updating DEV server..." -ForegroundColor Cyan
    & (Join-Path $PSScriptRoot "deploy-prod-remote.ps1")
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    Write-Host "[lmupdate] All done." -ForegroundColor Green
} finally {
    Pop-Location
}
