# =====================================================================
# google-calendar-provider.ps1  —  Read-ONLY Google Calendar (live provider)
# ---------------------------------------------------------------------
# Tony owns the conversation; Google Calendar owns the calendar data; this
# provider is an implementation detail. Jake asks Tony about his day - he
# never operates the Google Calendar API.
#
# READ ONLY. This provider retrieves and explains calendar information. It
# NEVER creates, edits, moves, accepts, declines, or deletes events. The
# only scope requested is calendar.readonly. Write access is out of scope
# and would require separate, explicit approval.
#
# Auth: Google OAuth 2.0 for an INSTALLED DESKTOP APP - Authorization Code
# flow with PKCE, a loopback redirect, offline access (refresh token). The
# system browser handles sign-in and consent; Tony never sees the Google
# password. No service accounts for a personal calendar.
#
# Private local files (gitignored, never printed/committed/logged):
#   calendar.config.json  - OAuth client id/secret for the desktop app
#   calendar.tokens.json  - access/refresh tokens
# It implements the reusable live-provider contract (relevant/query/status)
# from core/live-providers.ps1, so Tony Brain consumes it generically.
# =====================================================================

$ErrorActionPreference = 'Stop'

# ---- configuration (client id/secret live ONLY in the local file) --
function Get-GCalConfigPath { return (Join-Path $PSScriptRoot 'calendar.config.json') }
function Get-GCalTokenPath  { return (Join-Path $PSScriptRoot '..\..\calendar.tokens.json') }

function Get-GCalConfig {
    $clientId = $null; $clientSecret = $null; $source = 'none'
    $p = Get-GCalConfigPath
    if (Test-Path $p) {
        try {
            $c = Get-Content $p -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($c.clientId) { $clientId = [string]$c.clientId }
            if ($c.clientSecret) { $clientSecret = [string]$c.clientSecret }
            if ($clientId) { $source = 'calendar.config.json' }
        } catch { }
    }
    return [pscustomobject]@{
        clientId     = $clientId
        clientSecret = $clientSecret
        configured   = -not [string]::IsNullOrWhiteSpace($clientId)
        source       = $source
        scope        = 'https://www.googleapis.com/auth/calendar.readonly'
        authEndpoint = 'https://accounts.google.com/o/oauth2/v2/auth'
        tokenEndpoint = 'https://oauth2.googleapis.com/token'
        revokeEndpoint = 'https://oauth2.googleapis.com/revoke'
        apiBase      = 'https://www.googleapis.com/calendar/v3'
        readOnly     = $true
    }
}

# ---- token store (local, gitignored) -------------------------------
function Get-GCalTokens {
    $p = Get-GCalTokenPath
    if (Test-Path $p) { try { return (Get-Content $p -Raw -Encoding UTF8 | ConvertFrom-Json) } catch { } }
    return $null
}
function Save-GCalTokens {
    param([Parameter(Mandatory)] $Tokens)
    ($Tokens | ConvertTo-Json -Depth 6) | Set-Content -Path (Get-GCalTokenPath) -Encoding UTF8
}
function Clear-GCalTokens { $p = Get-GCalTokenPath; if (Test-Path $p) { Remove-Item $p -Force } }

# ---- PKCE ----------------------------------------------------------
function ConvertTo-Base64Url {
    param([byte[]]$Bytes)
    return ([System.Convert]::ToBase64String($Bytes)).TrimEnd('=').Replace('+', '-').Replace('/', '_')
}
function New-GCalPkce {
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    $vb = New-Object byte[] 48; $rng.GetBytes($vb)
    $verifier = ConvertTo-Base64Url -Bytes $vb
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $challenge = ConvertTo-Base64Url -Bytes ($sha.ComputeHash([System.Text.Encoding]::ASCII.GetBytes($verifier)))
    return [pscustomobject]@{ verifier = $verifier; challenge = $challenge }
}

# ---- diagnostics that NEVER contain tokens or codes ----------------
function Write-GCalDiag { param([string]$Level = 'info', [string]$Message = '') if (Get-Command Write-TonyDiag -ErrorAction SilentlyContinue) { Write-TonyDiag -Level $Level -Source 'calendar' -Message $Message } }

# ---- OAuth: connect (interactive, system browser + loopback) -------
# Opens the system browser for Google sign-in + consent, captures the code
# on a loopback socket, and exchanges it for tokens. Requires a configured
# desktop-app client id/secret in calendar.config.json.
function Connect-GoogleCalendar {
    $cfg = Get-GCalConfig
    if (-not $cfg.configured) { return [pscustomobject]@{ ok = $false; state = 'not-configured'; detail = 'No OAuth client configured. Add calendar.config.json (client id/secret for a Desktop app).' } }

    # loopback listener on a free port
    $listener = New-Object System.Net.Sockets.TcpListener ([System.Net.IPAddress]::Loopback, 0)
    $listener.Start()
    $port = ([System.Net.IPEndPoint]$listener.LocalEndpoint).Port
    $redirect = "http://127.0.0.1:$port/"

    $pkce = New-GCalPkce
    $stateTok = ConvertTo-Base64Url -Bytes ([guid]::NewGuid().ToByteArray())
    $authUrl = ('{0}?client_id={1}&redirect_uri={2}&response_type=code&scope={3}&access_type=offline&prompt=consent&code_challenge={4}&code_challenge_method=S256&state={5}' -f `
            $cfg.authEndpoint, [uri]::EscapeDataString($cfg.clientId), [uri]::EscapeDataString($redirect), [uri]::EscapeDataString($cfg.scope), $pkce.challenge, $stateTok)

    Write-GCalDiag -Message ("OAuth begin: opening browser, awaiting loopback on port {0}." -f $port)
    Start-Process $authUrl | Out-Null

    # accept ONE redirect, parse the code, respond, close
    $code = $null; $returnedState = $null
    try {
        $client = $listener.AcceptTcpClient()   # blocks until the browser redirects
        $stream = $client.GetStream()
        $reader = New-Object System.IO.StreamReader($stream)
        $requestLine = $reader.ReadLine()   # e.g. GET /?code=...&state=... HTTP/1.1
        if ($requestLine -match 'GET\s+/\?([^ ]+)\s+HTTP') {
            $qs = $Matches[1]
            foreach ($pair in ($qs -split '&')) {
                $kv = $pair -split '=', 2
                if ($kv[0] -eq 'code') { $code = [uri]::UnescapeDataString($kv[1]) }
                if ($kv[0] -eq 'state') { $returnedState = [uri]::UnescapeDataString($kv[1]) }
            }
        }
        $html = "<html><body style='font-family:Segoe UI;background:#0f1830;color:#e8eefc;padding:40px'><h2>GIOK - Google Calendar connected.</h2><p>You can close this window and return to Tony.</p></body></html>"
        $resp = "HTTP/1.1 200 OK`r`nContent-Type: text/html`r`nContent-Length: $($html.Length)`r`nConnection: close`r`n`r`n$html"
        $wb = [System.Text.Encoding]::UTF8.GetBytes($resp); $stream.Write($wb, 0, $wb.Length); $stream.Flush()
        $client.Close()
    } finally { $listener.Stop() }

    if ($returnedState -ne $stateTok) { Write-GCalDiag -Level 'error' -Message 'OAuth state mismatch.'; return [pscustomobject]@{ ok = $false; state = 'error'; detail = 'Authorization state did not match; sign-in was not completed.' } }
    if (-not $code) { Write-GCalDiag -Level 'error' -Message 'OAuth returned no code.'; return [pscustomobject]@{ ok = $false; state = 'error'; detail = 'No authorization code was returned; consent was not completed.' } }

    # exchange the code for tokens (PKCE + desktop client secret)
    $body = @{ code = $code; client_id = $cfg.clientId; client_secret = $cfg.clientSecret; redirect_uri = $redirect; grant_type = 'authorization_code'; code_verifier = $pkce.verifier }
    try {
        $tok = Invoke-RestMethod -Method Post -Uri $cfg.tokenEndpoint -Body $body -ContentType 'application/x-www-form-urlencoded'
    } catch {
        Write-GCalDiag -Level 'error' -Message 'Token exchange failed.'
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
    Save-GCalTokens -Tokens $store
    Write-GCalDiag -Message 'OAuth complete: tokens stored (read-only scope).'
    return [pscustomobject]@{ ok = $true; state = 'connected'; detail = 'Google Calendar connected (read-only).' }
}

# Return a valid access token, refreshing with the refresh token if expired.
function Get-GCalAccessToken {
    $cfg = Get-GCalConfig
    $t = Get-GCalTokens
    if (-not $t -or -not $t.access_token) { return [pscustomobject]@{ ok = $false; state = 'not-connected'; detail = 'Google Calendar is not connected yet.' } }
    $expired = $true
    try { $expired = ([datetime]::Parse($t.expires_at) -le (Get-Date)) } catch { }
    if (-not $expired) { return [pscustomobject]@{ ok = $true; token = $t.access_token; state = 'connected' } }
    if (-not $t.refresh_token) { return [pscustomobject]@{ ok = $false; state = 'needs-attention'; detail = 'Your Google authorization expired and needs to be renewed.' } }
    $body = @{ client_id = $cfg.clientId; client_secret = $cfg.clientSecret; refresh_token = $t.refresh_token; grant_type = 'refresh_token' }
    try {
        $r = Invoke-RestMethod -Method Post -Uri $cfg.tokenEndpoint -Body $body -ContentType 'application/x-www-form-urlencoded'
        $t.access_token = $r.access_token
        $t.expires_at = (Get-Date).AddSeconds([int]$r.expires_in - 60).ToString('o')
        if ($r.refresh_token) { $t.refresh_token = $r.refresh_token }
        Save-GCalTokens -Tokens $t
        Write-GCalDiag -Message 'Access token refreshed.'
        return [pscustomobject]@{ ok = $true; token = $t.access_token; state = 'connected' }
    } catch {
        Write-GCalDiag -Level 'error' -Message 'Token refresh failed.'
        return [pscustomobject]@{ ok = $false; state = 'needs-attention'; detail = 'Your Google authorization expired and needs to be renewed.' }
    }
}

function Disconnect-GoogleCalendar {
    $cfg = Get-GCalConfig
    $t = Get-GCalTokens
    if ($t -and $t.refresh_token) { try { Invoke-RestMethod -Method Post -Uri $cfg.revokeEndpoint -Body @{ token = $t.refresh_token } -ContentType 'application/x-www-form-urlencoded' | Out-Null } catch { } }
    Clear-GCalTokens
    Write-GCalDiag -Message 'Disconnected: local authorization removed.'
    return [pscustomobject]@{ ok = $true; state = 'not-connected'; detail = 'Google Calendar disconnected; local authorization removed.' }
}

# ---- read-only API calls -------------------------------------------
function Invoke-GCalApi {
    param([string]$Token, [string]$Path, [hashtable]$Query = @{})
    $cfg = Get-GCalConfig
    $qs = (@($Query.GetEnumerator() | ForEach-Object { "$($_.Key)=$([uri]::EscapeDataString([string]$_.Value))" }) -join '&')
    $url = "$($cfg.apiBase)$Path" + $(if ($qs) { "?$qs" } else { '' })
    $resp = Invoke-WebRequest -Uri $url -Headers @{ Authorization = "Bearer $Token" } -UseBasicParsing -TimeoutSec 20
    return (([System.Text.Encoding]::UTF8.GetString($resp.RawContentStream.ToArray())) | ConvertFrom-Json)
}

function Get-GCalEventState {
    param([datetime]$Start, [datetime]$End, [datetime]$Now)
    if ($End -le $Now) { return 'completed' }
    if ($Start -le $Now -and $End -ge $Now) { return 'current' }
    return 'upcoming'
}

# Convert a raw Google event into the provider's structured event. Read only.
function Convert-GCalEvent {
    param($Raw, [string]$CalendarId, [datetime]$Now)
    if ($Raw.status -eq 'cancelled') { return $null }   # skip cancelled events
    $allDay = [bool]($Raw.start.date -and -not $Raw.start.dateTime)
    if ($allDay) {
        $start = [datetime]::Parse($Raw.start.date); $end = [datetime]::Parse($Raw.end.date)
    } else {
        $start = ([datetimeoffset]::Parse($Raw.start.dateTime)).LocalDateTime
        $end = ([datetimeoffset]::Parse($Raw.end.dateTime)).LocalDateTime
    }
    $mine = @($Raw.attendees | Where-Object { $_.self }) | Select-Object -First 1
    $link = $Raw.hangoutLink
    if (-not $link -and $Raw.conferenceData -and $Raw.conferenceData.entryPoints) { $link = (@($Raw.conferenceData.entryPoints | Where-Object { $_.uri }) | Select-Object -First 1).uri }
    $descr = [string]$Raw.description; if ($descr.Length -gt 160) { $descr = $descr.Substring(0, 160) + '...' }
    return [pscustomobject]@{
        id                 = $Raw.id
        calendarId         = $CalendarId
        title              = $(if ($Raw.summary) { [string]$Raw.summary } else { '(no title)' })
        start              = $start
        end                = $end
        allDay             = $allDay
        location           = [string]$Raw.location
        descriptionSummary = $descr
        organizer          = $(if ($Raw.organizer) { [string]$Raw.organizer.email } else { '' })
        attendeeCount      = @($Raw.attendees).Count
        responseStatus     = $(if ($mine) { [string]$mine.responseStatus } else { '' })
        meetingLink        = [string]$link
        state              = $(if ($allDay) { 'upcoming' } else { Get-GCalEventState -Start $start -End $end -Now $Now })
    }
}

# Free-time windows within [DayStart..DayEnd] on a given date, given busy
# (timed, non-all-day) events. Pure logic - deterministic and testable.
function Get-GCalFreeWindows {
    param([datetime]$Date, $Events, [int]$DayStartHour = 7, [int]$DayEndHour = 21, [int]$MinMinutes = 30)
    $dayStart = $Date.Date.AddHours($DayStartHour)
    $dayEnd = $Date.Date.AddHours($DayEndHour)
    $busy = @($Events | Where-Object { -not $_.allDay -and $_.end -gt $dayStart -and $_.start -lt $dayEnd } | Sort-Object start)
    $windows = @()
    $cursor = $dayStart
    foreach ($e in $busy) {
        $s = if ($e.start -lt $dayStart) { $dayStart } else { $e.start }
        if ($s -gt $cursor) {
            $mins = [int]([math]::Round(($s - $cursor).TotalMinutes))
            if ($mins -ge $MinMinutes) { $windows += [pscustomobject]@{ start = $cursor; end = $s; minutes = $mins } }
        }
        if ($e.end -gt $cursor) { $cursor = $e.end }
    }
    if ($dayEnd -gt $cursor) {
        $mins = [int]([math]::Round(($dayEnd - $cursor).TotalMinutes))
        if ($mins -ge $MinMinutes) { $windows += [pscustomobject]@{ start = $cursor; end = $dayEnd; minutes = $mins } }
    }
    return @($windows)
}

# Overlapping timed events = scheduling conflicts. Pure logic.
function Get-GCalConflicts {
    param($Events)
    $timed = @($Events | Where-Object { -not $_.allDay } | Sort-Object start)
    $conflicts = @()
    for ($i = 0; $i -lt $timed.Count; $i++) {
        for ($j = $i + 1; $j -lt $timed.Count; $j++) {
            if ($timed[$j].start -lt $timed[$i].end) {
                $conflicts += [pscustomobject]@{ a = $timed[$i].title; b = $timed[$j].title; at = $timed[$j].start }
            } else { break }
        }
    }
    return @($conflicts)
}

# Calendar Intelligence: the day at a glance, computed from events. Pure,
# deterministic, testable. First/last meeting, totals, free focus blocks,
# and which days in the window are meeting-heavy. All-day events are not
# counted as "meetings" (they don't consume focus time).
function Get-CalendarInsights {
    param($Events, [datetime]$Now = (Get-Date), [int]$HeavyThreshold = 4)
    $timed = @($Events | Where-Object { -not $_.allDay } | Sort-Object start)
    $todayTimed = @($timed | Where-Object { $_.start.Date -eq $Now.Date })
    $first = if ($todayTimed.Count -gt 0) { $todayTimed[0] } else { $null }
    $last = if ($todayTimed.Count -gt 0) { @($todayTimed | Sort-Object end)[-1] } else { $null }
    $busyMin = 0; foreach ($e in $todayTimed) { $busyMin += [int]([math]::Round(($e.end - $e.start).TotalMinutes)) }
    $free = Get-GCalFreeWindows -Date $Now -Events $todayTimed
    $longestFree = if (@($free).Count -gt 0) { @($free | Sort-Object minutes -Descending)[0] } else { $null }
    $byDay = $timed | Group-Object { $_.start.Date.ToString('yyyy-MM-dd') }
    $heavyDays = @($byDay | Where-Object { @($_.Group).Count -ge $HeavyThreshold } | ForEach-Object { [pscustomobject]@{ date = $_.Name; day = ([datetime]$_.Name).ToString('dddd'); count = @($_.Group).Count } } | Sort-Object date)
    return [pscustomobject]@{
        today            = [pscustomobject]@{
            firstMeeting     = $first
            lastMeeting      = $last
            totalMeetings    = $todayTimed.Count
            busyMinutes      = $busyMin
            freeBlocks       = @($free)
            longestFreeBlock = $longestFree
            meetingHeavy     = ($todayTimed.Count -ge $HeavyThreshold)
        }
        meetingHeavyDays = $heavyDays
        heavyThreshold   = $HeavyThreshold
    }
}

# ---- THE contract: structured calendar info (or an honest failure) --
function Get-Calendar {
    param([string]$When = 'today', [datetime]$Now = (Get-Date))
    $cfg = Get-GCalConfig
    $nowStr = $Now.ToString('yyyy-MM-dd HH:mm:ss')
    $fail = {
        param($state, $detail)
        [pscustomobject]@{ provider = 'calendar'; ok = $false; errorState = $state; status = [pscustomobject]@{ state = $state; detail = $detail; lastRefresh = $null; lastError = $detail }; timestamp = $nowStr; account = $null; timezone = $null; calendars = @(); events = @(); nextEvent = $null; todayCount = 0; tomorrowCount = 0; freeWindows = @(); conflicts = @(); insights = $null }
    }
    if (-not $cfg.configured) { return (& $fail 'not-configured' 'Google Calendar is not connected yet.') }
    $at = Get-GCalAccessToken
    if (-not $at.ok) { return (& $fail $at.state $at.detail) }

    try {
        $calList = Invoke-GCalApi -Token $at.token -Path '/users/me/calendarList'
        $cals = @($calList.items | Where-Object { $_.selected -ne $false })
        $primary = @($calList.items | Where-Object { $_.primary }) | Select-Object -First 1
        $account = if ($primary) { [string]$primary.id } else { $null }
        $tz = if ($primary -and $primary.timeZone) { [string]$primary.timeZone } else { [System.TimeZoneInfo]::Local.Id }

        $timeMin = $Now.Date.ToString('o')
        $timeMax = $Now.Date.AddDays(8).ToString('o')
        $events = @()
        foreach ($cal in $cals) {
            $ev = Invoke-GCalApi -Token $at.token -Path ("/calendars/{0}/events" -f [uri]::EscapeDataString($cal.id)) -Query @{ timeMin = $timeMin; timeMax = $timeMax; singleEvents = 'true'; orderBy = 'startTime'; maxResults = '100' }
            foreach ($raw in @($ev.items)) { $c = Convert-GCalEvent -Raw $raw -CalendarId $cal.id -Now $Now; if ($c) { $events += $c } }
        }
        # dedupe (same event id can appear across calendars / invitations)
        $events = @($events | Group-Object id | ForEach-Object { $_.Group | Select-Object -First 1 } | Sort-Object start)

        $today = @($events | Where-Object { $_.start.Date -eq $Now.Date })
        $tomorrow = @($events | Where-Object { $_.start.Date -eq $Now.Date.AddDays(1) })
        $next = @($events | Where-Object { $_.start -gt $Now -and -not $_.allDay } | Sort-Object start | Select-Object -First 1)
        $freeToday = Get-GCalFreeWindows -Date $Now -Events $today
        $freeTomorrow = Get-GCalFreeWindows -Date $Now.AddDays(1) -Events $tomorrow
        $insights = Get-CalendarInsights -Events $events -Now $Now

        return [pscustomobject]@{
            provider    = 'calendar'; ok = $true; errorState = $null
            status      = [pscustomobject]@{ state = 'connected'; detail = ('Live from Google Calendar ({0}).' -f $account); lastRefresh = $nowStr; lastError = $null }
            timestamp   = $nowStr; account = $account; timezone = $tz
            calendars   = @($cals | ForEach-Object { [pscustomobject]@{ id = $_.id; summary = [string]$_.summary; primary = [bool]$_.primary } })
            events      = @($events); nextEvent = @($next)[0]
            todayCount  = $today.Count; tomorrowCount = $tomorrow.Count
            freeWindows = @($freeToday + $freeTomorrow)
            conflicts   = @(Get-GCalConflicts -Events $events)
            insights    = $insights
        }
    } catch {
        $msg = $_.Exception.Message; $state = 'error'
        if ($_.Exception.Response -and ($_.Exception.Response.PSObject.Properties.Name -contains 'StatusCode')) {
            $sc = [int]$_.Exception.Response.StatusCode
            if ($sc -eq 401) { $state = 'needs-attention'; $msg = 'Your Google authorization expired and needs to be renewed.' }
            elseif ($sc -eq 403) { $state = 'denied'; $msg = 'I can reach Google Calendar, but the request was denied.' }
        } elseif ($_.Exception -is [System.Net.WebException]) { $state = 'network-error'; $msg = 'I could not retrieve the calendar because the network is unavailable.' }
        Write-GCalDiag -Level 'error' -Message ("Calendar fetch {0}." -f $state)
        return (& $fail $state $msg)
    }
}

# Status for Settings. Without -Live: config/connection state, no network.
# With -Live: a real read to confirm access, with last refresh.
function Get-GCalStatus {
    param([switch]$Live)
    $cfg = Get-GCalConfig
    $t = Get-GCalTokens
    $account = if ($t -and $t.account) { $t.account } else { $null }
    if (-not $cfg.configured) { return [pscustomobject]@{ name = 'Google Calendar'; state = 'not-configured'; detail = 'No OAuth client configured. Add a Desktop-app client id/secret to calendar.config.json, then Connect.'; account = $null; readOnly = $true; lastRefresh = $null; lastError = $null } }
    if (-not $t) { return [pscustomobject]@{ name = 'Google Calendar'; state = 'not-connected'; detail = 'Configured but not connected. Click Connect Google Calendar.'; account = $null; readOnly = $true; lastRefresh = $null; lastError = $null } }
    if (-not $Live) { return [pscustomobject]@{ name = 'Google Calendar'; state = 'connected'; detail = 'Connected (read-only). Run Test Connection to confirm live access.'; account = $account; readOnly = $true; lastRefresh = $null; lastError = $null } }
    $c = Get-Calendar -When 'today'
    $state = if ($c.ok) { 'connected' } else { $c.status.state }
    return [pscustomobject]@{ name = 'Google Calendar'; state = $state; detail = $c.status.detail; account = $c.account; readOnly = $true; lastRefresh = $c.status.lastRefresh; lastError = $c.status.lastError }
}

# Is a question about the calendar/schedule? Tony Brain uses this to route.
function Test-CalendarRelevant {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
    return [bool]($Text -match '(?i)\b(calendar|schedule|scheduled|appointment|appointments|meeting|meetings|agenda|event|events|booked|free time|time for|next (appointment|meeting|event)|my (day|week|afternoon|morning)|what.?s on|how busy|conflicts?|availability|available)\b')
}

# ---- register with the generic live-provider registry --------------
if (Get-Command Register-LiveProvider -ErrorAction SilentlyContinue) {
    Register-LiveProvider -Provider ([pscustomobject]@{
            name        = 'calendar'
            description = 'Read-only Google Calendar via OAuth 2.0 (installed desktop app, PKCE). Explained by Tony.'
            relevant    = { param($text) Test-CalendarRelevant $text }
            query       = { param($opts) $when = if ($opts -and $opts.When) { $opts.When } else { 'today' }; Get-Calendar -When $when }
            status      = { param($live) Get-GCalStatus -Live:([bool]$live) }
        })
}
