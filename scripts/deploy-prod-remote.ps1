# Deploy latest code to PROD by SSHing to the VPS and running pull + docker compose.
# Run from repo root on your local machine.
# Uses Resolve-HostingerSshKey.ps1 and empty SSH config so it works even if .ssh/config has permission issues.
#
# Optional environment:
#   $env:PROD_REPO_PATH          — path on the VPS (default: /root/labelops-lm). Hostinger bundle often uses /docker/labelops-lm
#   $env:LMUPDATE_SSH_KEY       — explicit private key path
#   $env:LMUPDATE_SKIP_GIT = "1" — skip git pull / build_number (deployment-only dir without a clone)
#   $env:LMUPDATE_COMPOSE_FILE   — default docker-compose.prod.yml; use docker-compose.yml for flat VPS dirs
#   $env:LMUPDATE_ENV_FILE       — default deploy/.env.production; use .env or NONE (omit --env-file; compose loads .env in cwd)
#   $env:LMUPDATE_REMOTE_SERVICES_BUILD   — space-separated services for `docker compose build` (default: web api worker)
#   $env:LMUPDATE_REMOTE_SERVICES_RESTART — space-separated services for `docker compose restart` (default: api worker web)

$ErrorActionPreference = "Stop"
$repoPathOnVps = if ($env:PROD_REPO_PATH) { $env:PROD_REPO_PATH } else { "/root/labelops-lm" }
$composeFile = if ($env:LMUPDATE_COMPOSE_FILE) { $env:LMUPDATE_COMPOSE_FILE } else { "docker-compose.prod.yml" }
$skipGit = $env:LMUPDATE_SKIP_GIT -eq "1"

$envFileArg = ""
if ($env:LMUPDATE_ENV_FILE -eq "NONE") {
    $envFileArg = ""
} elseif ($null -ne $env:LMUPDATE_ENV_FILE -and $env:LMUPDATE_ENV_FILE -ne "") {
    $envFileArg = "--env-file $($env:LMUPDATE_ENV_FILE)"
} else {
    $envFileArg = "--env-file deploy/.env.production"
}

$dc = "docker compose $envFileArg -f $composeFile".Trim() -replace '\s+', ' '

$servicesBuild = if ($env:LMUPDATE_REMOTE_SERVICES_BUILD) { $env:LMUPDATE_REMOTE_SERVICES_BUILD } else { "web api worker" }
$servicesRestart = if ($env:LMUPDATE_REMOTE_SERVICES_RESTART) { $env:LMUPDATE_REMOTE_SERVICES_RESTART } else { "api worker web" }

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

. (Join-Path $scriptDir "Resolve-HostingerSshKey.ps1")
$sshKey = Get-HostingerSshKeyPath
if (-not $sshKey) {
    Write-Error "No Hostinger SSH private key found under $($env:USERPROFILE)\.ssh\. Use hostinger_vps or hostinger_vps_codex, or set LMUPDATE_SSH_KEY to your key path."
    exit 1
}

Write-Host "[deploy-prod-remote] Using SSH key: $sshKey"
Write-Host "[deploy-prod-remote] Compose: $dc"
Write-Host "[deploy-prod-remote] Build services: $servicesBuild | Restart: $servicesRestart"
Write-Host "[deploy-prod-remote] Connecting to 187.124.22.93 and deploying from $repoPathOnVps ..."

if ($skipGit) {
    $remoteCmd = "cd $repoPathOnVps && export IMAGE_TAG=`$(date +%Y-%m-%d-%H%M) && export GIT_LAST_UPDATE=`$(date -u +'%Y-%m-%d %H:%M:%S UTC') && echo '[deploy] Step: skip git pull (LMUPDATE_SKIP_GIT=1)' && echo '[deploy] Image tag:' `$IMAGE_TAG && echo '[deploy] Step: docker compose build' && $dc build --no-cache $servicesBuild && echo '[deploy] Step: docker compose up -d' && $dc up -d && echo '[deploy] Step: docker compose restart' && $dc restart $servicesRestart && echo '[deploy] Step: docker compose ps' && $dc ps"
} else {
    $remoteCmd = "cd $repoPathOnVps && export IMAGE_TAG=`$(date +%Y-%m-%d-%H%M) && export GIT_LAST_UPDATE=`$(date -u +'%Y-%m-%d %H:%M:%S UTC') && ( [ -f deploy/build_number ] && export BUILD_NUMBER=`$((`$(cat deploy/build_number)+1)) || export BUILD_NUMBER=1 ) && echo `$BUILD_NUMBER > deploy/build_number && echo '[deploy] Image tag:' `$IMAGE_TAG 'build:' `$BUILD_NUMBER && echo '[deploy] Step: git pull' && git pull && echo '[deploy] Step: docker compose build' && $dc build --no-cache $servicesBuild && echo '[deploy] Step: docker compose up -d' && $dc up -d && echo '[deploy] Step: docker compose restart' && $dc restart $servicesRestart && echo '[deploy] Step: docker compose ps' && $dc ps"
}

& ssh -F $emptyConfig -i "$sshKey" -o ConnectTimeout=15 -o StrictHostKeyChecking=accept-new root@187.124.22.93 "$remoteCmd"
if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "Deploy failed. Check: key at $sshKey, repo on VPS at $repoPathOnVps (set `$env:PROD_REPO_PATH if different)." -ForegroundColor Yellow
    Write-Host "If the key has a passphrase, run once: ssh-add `"$sshKey`" then run this script again." -ForegroundColor Gray
    Write-Host "Ensure the VPS has your public key in /root/.ssh/authorized_keys." -ForegroundColor Gray
    Write-Host "Hostinger-style dir without git: `$env:LMUPDATE_SKIP_GIT='1'; `$env:LMUPDATE_COMPOSE_FILE='docker-compose.yml'; `$env:LMUPDATE_ENV_FILE='.env'; `$env:PROD_REPO_PATH='/docker/labelops-lm'" -ForegroundColor Gray
    exit $LASTEXITCODE
}

Write-Host "[deploy-prod-remote] PROD update finished."
