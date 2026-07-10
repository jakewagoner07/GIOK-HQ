# =====================================================================
# google-oauth.ps1  —  Shared Google OAuth 2.0 (installed desktop app)
# ---------------------------------------------------------------------
# The ONE OAuth mechanism every Google live provider reuses: Calendar,
# Gmail, and any future Google service. Authorization Code flow with
# PKCE (S256), a 127.0.0.1 loopback redirect, offline access (refresh
# token), and minimum read-only scopes. The system browser handles
# sign-in and consent; Tony never sees the Google password.
#
# This module is provider-NEUTRAL. Each provider passes a small config
# object and its own local token path; the mechanics live here exactly
# once (Single Source of Truth). It is written so the same shape extends
# to non-Google mail later (Outlook / Microsoft 365 / Yahoo) by swapping
# endpoints - the loopback + PKCE + offline-refresh pattern is identical.
#
# A provider config object has:
#   clientId, clientSecret   OAuth desktop-app credentials (local only)
#   scope                    space-delimited read-only scope(s)
#   authEndpoint, tokenEndpoint, revokeEndpoint
#   apiBase                  REST base url for Invoke-GoogleApi
#   tokenPath                local, gitignored token file for THIS provider
#   appName                  shown on the "connected" browser page
#   diagSource               diagnostics label (never contains tokens)
#
# Diagnostics NEVER contain tokens, codes, secrets, or message text.
# =====================================================================

$ErrorActionPreference = 'Stop'

function Write-GoogleOAuthDiag {
    param([string]$Source = 'google-oauth', [string]$Level = 'info', [string]$Message = '')
    if (Get-Command Write-TonyDiag -ErrorAction SilentlyContinue) { Write-TonyDiag -Level $Level -Source $Source -Message $Message }
}

# ---- PKCE ----------------------------------------------------------
function ConvertTo-GoogleB64Url {
    param([byte[]]$Bytes)
    return ([System.Convert]::ToBase64String($Bytes)).TrimEnd('=').Replace('+', '-').Replace('/', '_')
}
function New-GoogleOAuthPkce {
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    $vb = New-Object byte[] 48; $rng.GetBytes($vb)
    $verifier = ConvertTo-GoogleB64Url -Bytes $vb
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $challenge = ConvertTo-GoogleB64Url -Bytes ($sha.ComputeHash([System.Text.Encoding]::ASCII.GetBytes($verifier)))
    return [pscustomobject]@{ verifier = $verifier; challenge = $challenge }
}

# ---- token store (local, gitignored, per provider) -----------------
function Get-GoogleOAuthTokens {
    param([Parameter(Mandatory)][string]$Path)
    if (Test-Path $Path) { try { return (Get-Content $Path -Raw -Encoding UTF8 | ConvertFrom-Json) } catch { } }
    return $null
}
function Save-GoogleOAuthTokens {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)] $Tokens)
    ($Tokens | ConvertTo-Json -Depth 6) | Set-Content -Path $Path -Encoding UTF8
}
function Clear-GoogleOAuthTokens {
    param([Parameter(Mandatory)][string]$Path)
    if (Test-Path $Path) { Remove-Item $Path -Force }
}

# ---- connect (interactive: system browser + loopback capture) ------
# Opens the browser for Google sign-in + consent, captures the one-time
# code on a loopback socket, exchanges it for tokens (PKCE + secret),
# and stores them at $Config.tokenPath. Requires a configured client.
function Connect-GoogleOAuth {
    param([Parameter(Mandatory)] $Config)
    if ([string]::IsNullOrWhiteSpace($Config.clientId)) {
        return [pscustomobject]@{ ok = $false; state = 'not-configured'; detail = 'No OAuth client configured.' }
    }

    $listener = New-Object System.Net.Sockets.TcpListener ([System.Net.IPAddress]::Loopback, 0)
    $listener.Start()
    $port = ([System.Net.IPEndPoint]$listener.LocalEndpoint).Port
    $redirect = "http://127.0.0.1:$port/"

    $pkce = New-GoogleOAuthPkce
    $stateTok = ConvertTo-GoogleB64Url -Bytes ([guid]::NewGuid().ToByteArray())
    $authUrl = ('{0}?client_id={1}&redirect_uri={2}&response_type=code&scope={3}&access_type=offline&prompt=consent&code_challenge={4}&code_challenge_method=S256&state={5}' -f `
            $Config.authEndpoint, [uri]::EscapeDataString($Config.clientId), [uri]::EscapeDataString($redirect), [uri]::EscapeDataString($Config.scope), $pkce.challenge, $stateTok)

    Write-GoogleOAuthDiag -Source $Config.diagSource -Message ("OAuth begin: opening browser, awaiting loopback on port {0}." -f $port)
    Start-Process $authUrl | Out-Null

    $code = $null; $returnedState = $null
    try {
        $client = $listener.AcceptTcpClient()   # blocks until the browser redirects
        $stream = $client.GetStream()
        $reader = New-Object System.IO.StreamReader($stream)
        $requestLine = $reader.ReadLine()
        if ($requestLine -match 'GET\s+/\?([^ ]+)\s+HTTP') {
            $qs = $Matches[1]
            foreach ($pair in ($qs -split '&')) {
                $kv = $pair -split '=', 2
                if ($kv[0] -eq 'code') { $code = [uri]::UnescapeDataString($kv[1]) }
                if ($kv[0] -eq 'state') { $returnedState = [uri]::UnescapeDataString($kv[1]) }
            }
        }
        $appName = if ($Config.appName) { [string]$Config.appName } else { 'GIOK' }
        $html = "<html><body style='font-family:Segoe UI;background:#0f1830;color:#e8eefc;padding:40px'><h2>GIOK - $appName connected.</h2><p>You can close this window and return to Tony.</p></body></html>"
        $resp = "HTTP/1.1 200 OK`r`nContent-Type: text/html`r`nContent-Length: $($html.Length)`r`nConnection: close`r`n`r`n$html"
        $wb = [System.Text.Encoding]::UTF8.GetBytes($resp); $stream.Write($wb, 0, $wb.Length); $stream.Flush()
        $client.Close()
    } finally { $listener.Stop() }

    if ($returnedState -ne $stateTok) { Write-GoogleOAuthDiag -Source $Config.diagSource -Level 'error' -Message 'OAuth state mismatch.'; return [pscustomobject]@{ ok = $false; state = 'error'; detail = 'Authorization state did not match; sign-in was not completed.' } }
    if (-not $code) { Write-GoogleOAuthDiag -Source $Config.diagSource -Level 'error' -Message 'OAuth returned no code.'; return [pscustomobject]@{ ok = $false; state = 'error'; detail = 'No authorization code was returned; consent was not completed.' } }

    $body = @{ code = $code; client_id = $Config.clientId; client_secret = $Config.clientSecret; redirect_uri = $redirect; grant_type = 'authorization_code'; code_verifier = $pkce.verifier }
    try {
        $tok = Invoke-RestMethod -Method Post -Uri $Config.tokenEndpoint -Body $body -ContentType 'application/x-www-form-urlencoded'
    } catch {
        Write-GoogleOAuthDiag -Source $Config.diagSource -Level 'error' -Message 'Token exchange failed.'
        return [pscustomobject]@{ ok = $false; state = 'error'; detail = 'Google would not exchange the authorization for tokens.' }
    }
    $store = [pscustomobject]@{
        access_token  = $tok.access_token
        refresh_token = $tok.refresh_token
        token_type    = $tok.token_type
        scope         = $tok.scope
        expires_at    = (Get-Date).AddSeconds([int]$tok.expires_in - 60).ToString('o')
        obtained      = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    }
    Save-GoogleOAuthTokens -Path $Config.tokenPath -Tokens $store
    Write-GoogleOAuthDiag -Source $Config.diagSource -Message 'OAuth complete: tokens stored (read-only scope).'
    return [pscustomobject]@{ ok = $true; state = 'connected'; detail = ('{0} connected (read-only).' -f $appName) }
}

# Return a valid access token, refreshing with the refresh token if expired.
function Get-GoogleOAuthAccessToken {
    param([Parameter(Mandatory)] $Config)
    $t = Get-GoogleOAuthTokens -Path $Config.tokenPath
    if (-not $t -or -not $t.access_token) { return [pscustomobject]@{ ok = $false; state = 'not-connected'; detail = 'Not connected yet.' } }
    $expired = $true
    try { $expired = ([datetime]::Parse($t.expires_at) -le (Get-Date)) } catch { }
    if (-not $expired) { return [pscustomobject]@{ ok = $true; token = $t.access_token; state = 'connected' } }
    if (-not $t.refresh_token) { return [pscustomobject]@{ ok = $false; state = 'needs-attention'; detail = 'Your Google authorization expired and needs to be renewed.' } }
    $body = @{ client_id = $Config.clientId; client_secret = $Config.clientSecret; refresh_token = $t.refresh_token; grant_type = 'refresh_token' }
    try {
        $r = Invoke-RestMethod -Method Post -Uri $Config.tokenEndpoint -Body $body -ContentType 'application/x-www-form-urlencoded'
        $t.access_token = $r.access_token
        $t.expires_at = (Get-Date).AddSeconds([int]$r.expires_in - 60).ToString('o')
        if ($r.refresh_token) { $t.refresh_token = $r.refresh_token }
        Save-GoogleOAuthTokens -Path $Config.tokenPath -Tokens $t
        Write-GoogleOAuthDiag -Source $Config.diagSource -Message 'Access token refreshed.'
        return [pscustomobject]@{ ok = $true; token = $t.access_token; state = 'connected' }
    } catch {
        Write-GoogleOAuthDiag -Source $Config.diagSource -Level 'error' -Message 'Token refresh failed.'
        return [pscustomobject]@{ ok = $false; state = 'needs-attention'; detail = 'Your Google authorization expired and needs to be renewed.' }
    }
}

function Disconnect-GoogleOAuth {
    param([Parameter(Mandatory)] $Config)
    $t = Get-GoogleOAuthTokens -Path $Config.tokenPath
    if ($t -and $t.refresh_token) { try { Invoke-RestMethod -Method Post -Uri $Config.revokeEndpoint -Body @{ token = $t.refresh_token } -ContentType 'application/x-www-form-urlencoded' | Out-Null } catch { } }
    Clear-GoogleOAuthTokens -Path $Config.tokenPath
    Write-GoogleOAuthDiag -Source $Config.diagSource -Message 'Disconnected: local authorization removed.'
    return [pscustomobject]@{ ok = $true; state = 'not-connected'; detail = 'Disconnected; local authorization removed.' }
}

# ---- read-only REST GET (UTF-8 decoded correctly) ------------------
# Native UTF-8: decode the raw response bytes as UTF-8 ourselves so
# non-ASCII (names, subjects) is never mojibake before Tony sees it.
function Invoke-GoogleApi {
    param([Parameter(Mandatory)][string]$Token, [Parameter(Mandatory)][string]$BaseUrl, [Parameter(Mandatory)][string]$Path, [hashtable]$Query = @{})
    $qs = (@($Query.GetEnumerator() | ForEach-Object { "$($_.Key)=$([uri]::EscapeDataString([string]$_.Value))" }) -join '&')
    $url = "$BaseUrl$Path" + $(if ($qs) { "?$qs" } else { '' })
    $resp = Invoke-WebRequest -Uri $url -Headers @{ Authorization = "Bearer $Token" } -UseBasicParsing -TimeoutSec 20
    return (([System.Text.Encoding]::UTF8.GetString($resp.RawContentStream.ToArray())) | ConvertFrom-Json)
}
