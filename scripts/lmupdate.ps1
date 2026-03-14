# lmupdate: Push all latest changes to GitHub, then update the DEV server.
# Run from repo root: .\scripts\lmupdate.ps1
# Uses SSH key so no password is prompted (BatchMode=yes).
# Optional: $env:LMUPDATE_COMMIT_MSG = "Your message"
# Optional: $env:LMUPDATE_SSH_KEY = "C:\Users\...\.ssh\your_key"  # for both git push and deploy (default: ~/.ssh/hostinger_vps)
# Optional: $env:PROD_REPO_PATH = "/path/on/vps"  (default /root/ZalmanimAI)
# Optional: $env:LMUPDATE_SKIP_DEPLOY = "1" to push only (no server update)

$ErrorActionPreference = "Stop"
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$sshKey = if ($env:LMUPDATE_SSH_KEY) { $env:LMUPDATE_SSH_KEY } else { Join-Path (Join-Path $env:USERPROFILE ".ssh") "hostinger_vps" }

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
    # Use SSH key and BatchMode=yes so git push never prompts for password
    $env:GIT_SSH_COMMAND = "ssh -o BatchMode=yes -i `"$sshKey`""
    git push
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[lmupdate] Push failed." -ForegroundColor Red
        exit $LASTEXITCODE
    }
    Write-Host "[lmupdate] GitHub push done." -ForegroundColor Green

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
