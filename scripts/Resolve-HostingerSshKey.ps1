# Shared by deploy-prod-remote.ps1, deploy-staging-remote.ps1, lmupdate.ps1.
# Prefers $env:LMUPDATE_SSH_KEY when the file exists; otherwise the first existing
# private key among hostinger_vps, hostinger_vps_codex under %USERPROFILE%\.ssh.

function Get-HostingerSshKeyPath {
    [CmdletBinding()]
    param()
    $sshDir = Join-Path $env:USERPROFILE '.ssh'
    if ($env:LMUPDATE_SSH_KEY) {
        $explicit = $env:LMUPDATE_SSH_KEY.Trim()
        if ($explicit -and (Test-Path -LiteralPath $explicit)) {
            return $explicit
        }
        Write-Warning "LMUPDATE_SSH_KEY is set but file not found: $explicit"
    }
    foreach ($name in @('hostinger_vps', 'hostinger_vps_codex')) {
        $candidate = Join-Path $sshDir $name
        if (Test-Path -LiteralPath $candidate) {
            return $candidate
        }
    }
    return $null
}
