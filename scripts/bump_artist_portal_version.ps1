# Bump the build number (the +N part) in apps/artist_portal/pubspec.yaml.
# Run from repo root. Used by pre-push hook so version updates on every push.

$ErrorActionPreference = 'Stop'
$pubspecPath = Join-Path $PSScriptRoot '..\apps\artist_portal\pubspec.yaml'
$content = Get-Content -Raw -Path $pubspecPath

if ($content -match 'version:\s*(\d+\.\d+\.\d+)\+(\d+)') {
  $versionPart = $Matches[1]
  $buildPart = [int]$Matches[2] + 1
  $newVersion = "version: ${versionPart}+${buildPart}"
  $content = $content -replace 'version:\s*\d+\.\d+\.\d+\+\d+', $newVersion
  Set-Content -Path $pubspecPath -Value $content.TrimEnd()
  Write-Host "Bumped artist_portal version to ${versionPart}+${buildPart}"
} else {
  Write-Error "Could not find version line in $pubspecPath"
  exit 1
}
