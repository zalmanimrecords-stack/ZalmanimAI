# Deploy latest code to PROD by SSHing to the VPS and running pull + docker compose.
# Run from repo root on your local machine.
# Uses key ~/.ssh/hostinger_vps and empty SSH config so it works even if your .ssh/config has permission issues.
#
# Optional: $env:PROD_REPO_PATH = "/root/ZalmanimAI"  # path on the VPS (default below)

$ErrorActionPreference = "Stop"
$repoPathOnVps = if ($env:PROD_REPO_PATH) { $env:PROD_REPO_PATH } else { "/root/ZalmanimAI" }
$sshKey = if ($env:LMUPDATE_SSH_KEY) { $env:LMUPDATE_SSH_KEY } else { Join-Path (Join-Path $env:USERPROFILE ".ssh") "hostinger_vps" }
$emptyConfig = (Resolve-Path (Join-Path (Join-Path $PSScriptRoot "..") "deploy\ssh_config_empty") -ErrorAction Stop).Path

if (-not (Test-Path -LiteralPath $sshKey)) {
    Write-Error "SSH key not found: $sshKey"
    exit 1
}

Write-Host "[deploy-prod-remote] Connecting to 187.124.22.93 and deploying from $repoPathOnVps ..."
# IMAGE_TAG on remote = date and time of deploy (e.g. 2025-03-14-1530); $(date ...) is evaluated on the VPS
# Escape [ ] for PowerShell; $IMAGE_TAG is sent to remote so bash expands it there
$remoteCmd = "cd $repoPathOnVps && export IMAGE_TAG=`$(date +%Y-%m-%d-%H%M) && export GIT_LAST_UPDATE=`$(date -u +'%Y-%m-%d %H:%M:%S UTC') && echo `"`[deploy`] Image tag: `$IMAGE_TAG`" && git pull && docker compose --env-file deploy/.env.production -f docker-compose.prod.yml up -d --build && docker compose --env-file deploy/.env.production -f docker-compose.prod.yml ps"
# BatchMode=yes: never prompt for passphrase; use key only (load key into ssh-agent first if it has a passphrase)
ssh -F $emptyConfig -i $sshKey -o BatchMode=yes -o ConnectTimeout=15 -o StrictHostKeyChecking=accept-new root@187.124.22.93 $remoteCmd
if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "Deploy failed. Check: key at $sshKey, repo on VPS at $repoPathOnVps (set `$env:PROD_REPO_PATH if different)." -ForegroundColor Yellow
    exit $LASTEXITCODE
}

Write-Host "[deploy-prod-remote] PROD update finished."
