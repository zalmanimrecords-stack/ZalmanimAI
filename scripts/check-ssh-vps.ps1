# Quick SSH check to Hostinger VPS (same key resolution as deploy scripts).
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot
. .\Resolve-HostingerSshKey.ps1
$key = Get-HostingerSshKeyPath
if (-not $key) {
    Write-Host 'FAIL: No SSH key. Add hostinger_vps or set LMUPDATE_SSH_KEY.'
    exit 1
}
Write-Host "OK: Using key $key"
ssh -F NUL -i $key -o ConnectTimeout=15 -o StrictHostKeyChecking=accept-new root@187.124.22.93 'echo SSH_OK; hostname -f; uptime -p'
$code = $LASTEXITCODE
if ($code -ne 0) {
    Write-Host "FAIL: ssh exited with code $code"
}
exit $code
