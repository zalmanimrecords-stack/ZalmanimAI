# Deploy latest code to PROD by SSHing to the VPS and running pull + docker compose.
# Run from repo root on your local machine.
# Uses key ~/.ssh/hostinger_vps and empty SSH config so it works even if your .ssh/config has permission issues.
#
# Optional: $env:PROD_REPO_PATH = "/root/ZalmanimAI"  # path on the VPS (default below)

$ErrorActionPreference = "Stop"
$repoPathOnVps = if ($env:PROD_REPO_PATH) { $env:PROD_REPO_PATH } else { "/root/ZalmanimAI" }
$sshKey = if ($env:LMUPDATE_SSH_KEY) { $env:LMUPDATE_SSH_KEY } else { Join-Path (Join-Path $env:USERPROFILE ".ssh") "hostinger_vps" }
$scriptPath = if ($PSCommandPath) {
    $PSCommandPath
} elseif ($MyInvocation.MyCommand.Path) {
    $MyInvocation.MyCommand.Path
} else {
    throw "Could not determine script path."
}
$scriptDir = Split-Path -Parent $scriptPath
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $scriptDir "..") -ErrorAction Stop).Path
$emptyConfig = (Resolve-Path -LiteralPath (Join-Path $repoRoot "deploy\ssh_config_empty") -ErrorAction Stop).Path

if (-not (Test-Path -LiteralPath $sshKey)) {
    Write-Error "SSH key not found: $sshKey"
    exit 1
}

Write-Host "[deploy-prod-remote] Connecting to 187.124.22.93 and deploying from $repoPathOnVps ..."
# IMAGE_TAG on remote = date and time of deploy (e.g. 2025-03-14-1530); $(date ...) is evaluated on the VPS
# Escape [ ] for PowerShell; $IMAGE_TAG is sent to remote so bash expands it there
# On VPS: bump build version (deploy/build_number is gitignored), then pull and build
$remoteCmd = "cd $repoPathOnVps && export IMAGE_TAG=`$(date +%Y-%m-%d-%H%M) && export GIT_LAST_UPDATE=`$(date -u +'%Y-%m-%d %H:%M:%S UTC') && ( [ -f deploy/build_number ] && export BUILD_NUMBER=`$((`$(cat deploy/build_number)+1)) || export BUILD_NUMBER=1 ) && echo `$BUILD_NUMBER > deploy/build_number && echo '[deploy] Image tag:' `$IMAGE_TAG 'version:' `$BUILD_NUMBER && git pull && docker compose --env-file deploy/.env.production -f docker-compose.prod.yml up -d --build && docker compose --env-file deploy/.env.production -f docker-compose.prod.yml ps"
# Use key explicitly (quoted for Windows paths). If key has a passphrase, ssh will prompt once, or run ssh-add first for no prompt.
& ssh -F $emptyConfig -i "$sshKey" -o ConnectTimeout=15 -o StrictHostKeyChecking=accept-new root@187.124.22.93 $remoteCmd
if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "Deploy failed. Check: key at $sshKey, repo on VPS at $repoPathOnVps (set `$env:PROD_REPO_PATH if different)." -ForegroundColor Yellow
    Write-Host "If the key has a passphrase, run once: ssh-add `"$sshKey`" then run this script again." -ForegroundColor Gray
    Write-Host "Ensure the VPS has your public key in /root/.ssh/authorized_keys." -ForegroundColor Gray
    exit $LASTEXITCODE
}

Write-Host "[deploy-prod-remote] PROD update finished."
