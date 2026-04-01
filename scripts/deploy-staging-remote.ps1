# Deploy latest code to STAGING by SSHing to the VPS and running pull + docker compose.
# Run from repo root on your local machine.

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

Write-Host "[deploy-staging-remote] Connecting to 187.124.22.93 and deploying staging from $repoPathOnVps ..."
$remoteCmd = "cd $repoPathOnVps && export IMAGE_TAG=`$(date +%Y-%m-%d-%H%M)-staging && export GIT_LAST_UPDATE=`$(date -u +'%Y-%m-%d %H:%M:%S UTC') && ( [ -f deploy/build_number_staging ] && export BUILD_NUMBER=`$((`$(cat deploy/build_number_staging)+1)) || export BUILD_NUMBER=1 ) && echo `$BUILD_NUMBER > deploy/build_number_staging && echo '[deploy-staging] Image tag:' `$IMAGE_TAG 'build:' `$BUILD_NUMBER && echo '[deploy-staging] Step: git pull' && git pull && echo '[deploy-staging] Step: docker compose build' && docker compose -p labelops-staging --env-file deploy/.env.staging -f docker-compose.staging.yml build --no-cache web api worker && echo '[deploy-staging] Step: docker compose up -d' && docker compose -p labelops-staging --env-file deploy/.env.staging -f docker-compose.staging.yml up -d && echo '[deploy-staging] Step: docker compose restart' && docker compose -p labelops-staging --env-file deploy/.env.staging -f docker-compose.staging.yml restart api worker web && echo '[deploy-staging] Step: docker compose ps' && docker compose -p labelops-staging --env-file deploy/.env.staging -f docker-compose.staging.yml ps"
& ssh -F $emptyConfig -i "$sshKey" -o ConnectTimeout=15 -o StrictHostKeyChecking=accept-new root@187.124.22.93 "$remoteCmd"
if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "Staging deploy failed. Check key/repo path and remote docker logs." -ForegroundColor Yellow
    exit $LASTEXITCODE
}

Write-Host "[deploy-staging-remote] STAGING update finished."
