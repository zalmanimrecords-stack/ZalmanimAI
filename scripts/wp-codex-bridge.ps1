param(
  [Parameter(Mandatory = $true)]
  [ValidateSet('pair', 'context', 'handshake', 'content', 'design')]
  [string]$Action,

  [string]$EnvFile = 'wp-codex-bridge.env',
  [string]$BodyJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Read-EnvFile {
  param([string]$Path)

  if (-not (Test-Path -Path $Path)) {
    throw "Env file not found: $Path"
  }

  $map = @{}
  Get-Content -Path $Path | ForEach-Object {
    $line = $_.Trim()
    if (-not $line -or $line.StartsWith('#')) { return }

    $parts = $line -split '=', 2
    if ($parts.Count -ne 2) { return }

    $key = $parts[0].Trim()
    $value = $parts[1].Trim()
    $map[$key] = $value
  }

  return $map
}

function Get-Nonce {
  return ([guid]::NewGuid().ToString('N'))
}

function Get-Sha256Hex {
  param([string]$Text)

  if ($null -eq $Text) { $Text = '' }
  $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
  $hash = [System.Security.Cryptography.SHA256]::HashData($bytes)
  return ([System.BitConverter]::ToString($hash).Replace('-', '').ToLowerInvariant())
}

function Get-HmacSha256Hex {
  param(
    [string]$Secret,
    [string]$Message
  )

  $secretBytes = [System.Text.Encoding]::UTF8.GetBytes($Secret)
  $msgBytes = [System.Text.Encoding]::UTF8.GetBytes($Message)
  $hmac = [System.Security.Cryptography.HMACSHA256]::new($secretBytes)
  try {
    $sig = $hmac.ComputeHash($msgBytes)
    return ([System.BitConverter]::ToString($sig).Replace('-', '').ToLowerInvariant())
  }
  finally {
    $hmac.Dispose()
  }
}

function Invoke-CodexBridgeSigned {
  param(
    [ValidateSet('GET', 'POST')]
    [string]$Method,
    [string]$Url,
    [hashtable]$Cfg,
    [string]$Body
  )

  if ($null -eq $Body) { $Body = '' }

  $uri = [System.Uri]$Url
  $route = $uri.AbsolutePath
  $timestamp = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds().ToString()
  $nonce = Get-Nonce
  $bodyHash = Get-Sha256Hex -Text $Body

  $stringToSign = "$Method`n$route`n$timestamp`n$nonce`n$bodyHash"
  $signature = Get-HmacSha256Hex -Secret $Cfg.CLIENT_SECRET -Message $stringToSign

  $headers = @{
    'X-Codex-Key' = $Cfg.CLIENT_KEY
    'X-Codex-Timestamp' = $timestamp
    'X-Codex-Nonce' = $nonce
    'X-Codex-Signature' = $signature
  }

  $common = @{
    Method = $Method
    Uri = $Url
    Headers = $headers
    ContentType = 'application/json'
  }

  if ($Method -eq 'POST') {
    $common.Body = $Body
  }

  return Invoke-RestMethod @common
}

$cfg = Read-EnvFile -Path $EnvFile

if (-not $cfg.REST_BASE_URL) { throw 'REST_BASE_URL missing in env file.' }
if (-not $cfg.CLIENT_KEY) { throw 'CLIENT_KEY missing in env file.' }
if (-not $cfg.CLIENT_SECRET) { throw 'CLIENT_SECRET missing in env file.' }

try {
  switch ($Action) {
    'pair' {
      if (-not $cfg.ONE_TIME_PAIRING_KEY) {
        throw 'ONE_TIME_PAIRING_KEY is empty. Put the one-time key in the env file and retry.'
      }
      $url = "$($cfg.REST_BASE_URL.TrimEnd('/'))/pair"
      $payload = @{ pairing_key = $cfg.ONE_TIME_PAIRING_KEY } | ConvertTo-Json -Compress
      $result = Invoke-RestMethod -Method POST -Uri $url -ContentType 'application/json' -Body $payload
      $result | ConvertTo-Json -Depth 10
    }

    'context' {
      $url = "$($cfg.REST_BASE_URL.TrimEnd('/'))/context"
      $result = Invoke-CodexBridgeSigned -Method GET -Url $url -Cfg $cfg -Body ''
      $result | ConvertTo-Json -Depth 10
    }

    'handshake' {
      $url = "$($cfg.REST_BASE_URL.TrimEnd('/'))/handshake"
      if (-not $BodyJson) {
        $contentScope = 'true'
        $designScope = 'true'
        if ($cfg.ContainsKey('SCOPES_CONTENT') -and $cfg.SCOPES_CONTENT) { $contentScope = $cfg.SCOPES_CONTENT }
        if ($cfg.ContainsKey('SCOPES_DESIGN') -and $cfg.SCOPES_DESIGN) { $designScope = $cfg.SCOPES_DESIGN }

        $defaultBody = @{
          scopes = @{
            content = ($contentScope.ToLowerInvariant() -eq 'true')
            design = ($designScope.ToLowerInvariant() -eq 'true')
          }
        }
        $BodyJson = $defaultBody | ConvertTo-Json -Compress
      }
      $result = Invoke-CodexBridgeSigned -Method POST -Url $url -Cfg $cfg -Body $BodyJson
      $result | ConvertTo-Json -Depth 10
    }

    'content' {
      $url = "$($cfg.REST_BASE_URL.TrimEnd('/'))/content"
      if (-not $BodyJson) {
        $BodyJson = '{"operation":"upsert","post_type":"page","title":"Home","content":"<h1>Hello</h1>","status":"publish"}'
      }
      $result = Invoke-CodexBridgeSigned -Method POST -Url $url -Cfg $cfg -Body $BodyJson
      $result | ConvertTo-Json -Depth 10
    }

    'design' {
      $url = "$($cfg.REST_BASE_URL.TrimEnd('/'))/design"
      if (-not $BodyJson) {
        $BodyJson = '{"custom_css":"body{background:#f8f8f8;}","site_title":"My Site","tagline":"Fast updates"}'
      }
      $result = Invoke-CodexBridgeSigned -Method POST -Url $url -Cfg $cfg -Body $BodyJson
      $result | ConvertTo-Json -Depth 10
    }
  }
}
catch {
  $ex = $_.Exception
  Write-Error "Request failed: $($ex.Message)"
  if ($ex.Response -and $ex.Response.GetResponseStream) {
    $stream = $ex.Response.GetResponseStream()
    if ($stream) {
      $reader = [System.IO.StreamReader]::new($stream)
      try {
        $raw = $reader.ReadToEnd()
        if ($raw) {
          Write-Host 'Server response:'
          Write-Host $raw
        }
      }
      finally {
        $reader.Dispose()
      }
    }
  }
  exit 1
}
