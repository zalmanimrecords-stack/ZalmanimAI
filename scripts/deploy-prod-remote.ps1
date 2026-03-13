# Deploy latest code to PROD by SSHing to the VPS and running pull + docker compose.
# Run from repo root on your local machine.
# Uses key ~/.ssh/hostinger_vps and empty SSH config so it works even if your .ssh/config has permission issues.
#
# Optional: $env:PROD_REPO_PATH = "/root/ZalmanimAI"  # path on the VPS (default below)

$ErrorActionPreference = "Stop"
$repoPathOnVps = if ($env:PROD_REPO_PATH) { $env:PROD_REPO_PATH } else { "/root/ZalmanimAI" }
$sshKey = Join-Path (Join-Path $env:USERPROFILE ".ssh") "hostinger_vps"
$emptyConfig = (Resolve-Path (Join-Path (Join-Path $PSScriptRoot "..") "deploy\ssh_config_empty") -ErrorAction Stop).Path

if (-not (Test-Path -LiteralPath $sshKey)) {
    Write-Error "SSH key not found: $sshKey"
    exit 1
}

Write-Host "[deploy-prod-remote] Connecting to 187.124.22.93 and deploying from $repoPathOnVps ..."
$remoteCmd = "cd $repoPathOnVps && git pull && docker compose --env-file deploy/.env.production -f docker-compose.prod.yml up -d --build && docker compose --env-file deploy/.env.production -f docker-compose.prod.yml ps"
ssh -F $emptyConfig -i $sshKey -o ConnectTimeout=15 -o StrictHostKeyChecking=accept-new root@187.124.22.93 $remoteCmd
if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "Deploy failed. Check: key at $sshKey, repo on VPS at $repoPathOnVps (set `$env:PROD_REPO_PATH if different)." -ForegroundColor Yellow
    exit $LASTEXITCODE
}

Write-Host "[deploy-prod-remote] PROD update finished."
