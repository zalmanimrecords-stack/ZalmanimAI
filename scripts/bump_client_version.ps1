# Bump the build number (the +N part) in apps/client/pubspec.yaml.
# Run from repo root when the LM app changes so the top bar shows a new version after deploy.

$ErrorActionPreference = 'Stop'
$pubspecPath = Join-Path $PSScriptRoot '..\apps\client\pubspec.yaml'
$content = Get-Content -Raw -Path $pubspecPath

if ($content -match 'version:\s*(\d+\.\d+\.\d+)\+(\d+)') {
  $versionPart = $Matches[1]
  $buildPart = [int]$Matches[2] + 1
  $newVersion = "version: ${versionPart}+${buildPart}"
  $content = $content -replace 'version:\s*\d+\.\d+\.\d+\+\d+', $newVersion
  Set-Content -Path $pubspecPath -Value $content.TrimEnd()
  Write-Host "Bumped client version to ${versionPart}+${buildPart}"
} else {
  Write-Error "Could not find version line in $pubspecPath"
  exit 1
}
