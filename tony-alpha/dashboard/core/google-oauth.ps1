# =====================================================================
# google-oauth.ps1  —  Shared Google OAuth 2.0 (installed desktop app)
# ---------------------------------------------------------------------
# The ONE OAuth mechanism every Google live provider reuses: Calendar,
# Gmail, and any future Google service. Authorization Code flow with
# PKCE (S256), a 127.0.0.1 loopback redirect, offline access (refresh
# token), and minimum read-only scopes. The system browser handles
# sign-in and consent; Tony never sees the Google password.
#
# MULTI-ACCOUNT (D17): one token file per service holds ALL connected
# accounts for that service, keyed by account email. There is still ONE
# Calendar provider and ONE Gmail provider - never a provider per account.
# Each account's tokens are stored separately inside the (gitignored) file:
#   { meta:{version}, accounts:[ { id:<email>, access_token, refresh_token,
#     token_type, scope, expires_at, obtained } ] }
#
# MIGRATION: an older single-account FLAT file ({access_token,...}) is read
# as one account with id 'default'; the provider re-keys it to the real
# email on first identity resolution. Existing users keep working untouched.
#
# This module is provider-NEUTRAL. Each provider passes a small config
# object and its own local token path; the mechanics live here exactly
# once (Single Source of Truth). The same shape extends to non-Google mail
# later by swapping endpoints.
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
# Diagnostics NEVER contain tokens, codes, secrets, or account addresses.
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

# ---- account-keyed token store (local, gitignored) -----------------
function Clear-GoogleTokenFile { param([Parameter(Mandatory)][string]$Path) if (Test-Path $Path) { Remove-Item $Path -Force } }

# Read the store, migrating a legacy flat single-account file in memory.
function Read-GoogleAccountStore {
    param([Parameter(Mandatory)][string]$Path)
    $data = $null
    if (Test-Path $Path) { try { $data = Get-Content $Path -Raw -Encoding UTF8 | ConvertFrom-Json } catch { } }
    $accounts = @()
    if ($data) {
        if (($data.PSObject.Properties.Name -contains 'accounts') -and $data.accounts) {
            $accounts = @($data.accounts)
        } elseif (($data.PSObject.Properties.Name -contains 'access_token') -and $data.access_token) {
            # legacy flat file -> one 'default' account (re-keyed to email on first use)
            $accounts = @([pscustomobject]@{ id = 'default'; access_token = $data.access_token; refresh_token = $data.refresh_token; token_type = $data.token_type; scope = $data.scope; expires_at = $data.expires_at; obtained = $data.obtained })
        }
    }
    return [pscustomobject]@{ meta = [pscustomobject]@{ version = '2.0' }; accounts = @($accounts) }
}
function Write-GoogleAccountStore {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)] $Store)
    ($Store | ConvertTo-Json -Depth 8) | Set-Content -Path $Path -Encoding UTF8
}
function Get-GoogleAccountIds {
    param([Parameter(Mandatory)][string]$Path)
    return @((Read-GoogleAccountStore -Path $Path).accounts | ForEach-Object { [string]$_.id })
}
function Get-GoogleAccountRecord {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Id)
    return @((Read-GoogleAccountStore -Path $Path).accounts | Where-Object { $_.id -eq $Id }) | Select-Object -First 1
}
function Set-GoogleAccountRecord {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)] $Account)
    $store = Read-GoogleAccountStore -Path $Path
    $store.accounts = @(@($store.accounts | Where-Object { $_.id -ne $Account.id }) + $Account)
    Write-GoogleAccountStore -Path $Path -Store $store
}
function Remove-GoogleAccountRecord {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Id)
    $store = Read-GoogleAccountStore -Path $Path
    $before = @($store.accounts).Count
    $store.accounts = @(@($store.accounts) | Where-Object { $_.id -ne $Id })
    if (@($store.accounts).Count -eq 0) { Clear-GoogleTokenFile -Path $Path } else { Write-GoogleAccountStore -Path $Path -Store $store }
    return (@($store.accounts).Count -ne $before)
}
# Re-key a record (legacy 'default' -> real email). If NewId already exists,
# the freshly-renamed record wins (a reconnect of the same account).
function Rename-GoogleAccountRecord {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$OldId, [Parameter(Mandatory)][string]$NewId)
    if ($OldId -eq $NewId) { return }
    $store = Read-GoogleAccountStore -Path $Path
    $rec = @($store.accounts | Where-Object { $_.id -eq $OldId }) | Select-Object -First 1
    if (-not $rec) { return }
    $rec.id = $NewId
    $store.accounts = @(@($store.accounts | Where-Object { $_.id -ne $OldId -and $_.id -ne $NewId }) + $rec)
    Write-GoogleAccountStore -Path $Path -Store $store
}

# ---- interactive consent (loopback) - returns raw tokens, no save --
# prompt=select_account lets the user pick a DIFFERENT account for each
# connection; prompt=consent guarantees a refresh token every time.
function Invoke-GoogleOAuthConsent {
    param([Parameter(Mandatory)] $Config)
    if ([string]::IsNullOrWhiteSpace($Config.clientId)) { return [pscustomobject]@{ ok = $false; state = 'not-configured'; detail = 'No OAuth client configured.' } }

    $listener = New-Object System.Net.Sockets.TcpListener ([System.Net.IPAddress]::Loopback, 0)
    $listener.Start()
    $port = ([System.Net.IPEndPoint]$listener.LocalEndpoint).Port
    $redirect = "http://127.0.0.1:$port/"

    $pkce = New-GoogleOAuthPkce
    $stateTok = ConvertTo-GoogleB64Url -Bytes ([guid]::NewGuid().ToByteArray())
    $authUrl = ('{0}?client_id={1}&redirect_uri={2}&response_type=code&scope={3}&access_type=offline&prompt=select_account+consent&code_challenge={4}&code_challenge_method=S256&state={5}' -f `
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
    return [pscustomobject]@{ ok = $true; tokens = $tok }
}

# Connect ONE more account. Runs consent, resolves the account identity
# (email) with the new token via the provider-supplied ResolveIdentity
# scriptblock, and stores the tokens keyed by that email. Reconnecting an
# existing account simply refreshes it (upsert by id).
function Connect-GoogleAccount {
    param([Parameter(Mandatory)] $Config, [Parameter(Mandatory)][scriptblock]$ResolveIdentity)
    $c = Invoke-GoogleOAuthConsent -Config $Config
    if (-not $c.ok) { return [pscustomobject]@{ ok = $false; state = $c.state; detail = $c.detail; id = $null } }
    $tok = $c.tokens
    $acct = [pscustomobject]@{
        id            = $null
        access_token  = $tok.access_token
        refresh_token = $tok.refresh_token
        token_type    = $tok.token_type
        scope         = $tok.scope
        expires_at    = (Get-Date).AddSeconds([int]$tok.expires_in - 60).ToString('o')
        obtained      = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    }
    $id = $null
    try { $id = & $ResolveIdentity $acct.access_token } catch { }
    if ([string]::IsNullOrWhiteSpace($id)) { $id = 'account-' + ([guid]::NewGuid().ToString('N').Substring(0, 6)) }
    $acct.id = [string]$id
    Set-GoogleAccountRecord -Path $Config.tokenPath -Account $acct
    Write-GoogleOAuthDiag -Source $Config.diagSource -Message 'OAuth complete: account connected (read-only).'
    return [pscustomobject]@{ ok = $true; state = 'connected'; id = $acct.id; detail = ('{0} connected (read-only).' -f $Config.appName) }
}

# Return a valid access token for ONE account, refreshing (and persisting)
# that account's tokens if expired. A failure here affects only this account.
function Get-GoogleAccountAccessToken {
    param([Parameter(Mandatory)] $Config, [Parameter(Mandatory)][string]$Id)
    $rec = Get-GoogleAccountRecord -Path $Config.tokenPath -Id $Id
    if (-not $rec -or -not $rec.access_token) { return [pscustomobject]@{ ok = $false; state = 'not-connected'; detail = 'Not connected.'; id = $Id } }
    $expired = $true
    try { $expired = ([datetime]::Parse($rec.expires_at) -le (Get-Date)) } catch { }
    if (-not $expired) { return [pscustomobject]@{ ok = $true; token = $rec.access_token; state = 'connected'; id = $Id } }
    if (-not $rec.refresh_token) { return [pscustomobject]@{ ok = $false; state = 'needs-attention'; detail = 'Authorization expired; reconnect this account.'; id = $Id } }
    $body = @{ client_id = $Config.clientId; client_secret = $Config.clientSecret; refresh_token = $rec.refresh_token; grant_type = 'refresh_token' }
    try {
        $r = Invoke-RestMethod -Method Post -Uri $Config.tokenEndpoint -Body $body -ContentType 'application/x-www-form-urlencoded'
        $rec.access_token = $r.access_token
        $rec.expires_at = (Get-Date).AddSeconds([int]$r.expires_in - 60).ToString('o')
        if ($r.refresh_token) { $rec.refresh_token = $r.refresh_token }
        Set-GoogleAccountRecord -Path $Config.tokenPath -Account $rec
        Write-GoogleOAuthDiag -Source $Config.diagSource -Message 'Access token refreshed.'
        return [pscustomobject]@{ ok = $true; token = $rec.access_token; state = 'connected'; id = $Id }
    } catch {
        Write-GoogleOAuthDiag -Source $Config.diagSource -Level 'error' -Message 'Token refresh failed.'
        return [pscustomobject]@{ ok = $false; state = 'needs-attention'; detail = 'Authorization expired; reconnect this account.'; id = $Id }
    }
}

# Disconnect ONE account: revoke its refresh token with Google and remove
# only that account's local tokens. Other accounts are untouched.
function Disconnect-GoogleAccount {
    param([Parameter(Mandatory)] $Config, [Parameter(Mandatory)][string]$Id)
    $rec = Get-GoogleAccountRecord -Path $Config.tokenPath -Id $Id
    if ($rec -and $rec.refresh_token) { try { Invoke-RestMethod -Method Post -Uri $Config.revokeEndpoint -Body @{ token = $rec.refresh_token } -ContentType 'application/x-www-form-urlencoded' | Out-Null } catch { } }
    $removed = Remove-GoogleAccountRecord -Path $Config.tokenPath -Id $Id
    Write-GoogleOAuthDiag -Source $Config.diagSource -Message 'Account disconnected: local authorization removed.'
    return [pscustomobject]@{ ok = [bool]$removed; state = 'not-connected'; detail = 'Account disconnected; local authorization removed.'; id = $Id }
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
