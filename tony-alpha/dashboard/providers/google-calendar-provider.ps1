# =====================================================================
# google-calendar-provider.ps1  —  Read-ONLY Google Calendar (MULTI-ACCOUNT)
# ---------------------------------------------------------------------
# Tony owns the conversation; Google Calendar owns the calendar data; this
# provider is an implementation detail. ONE Calendar provider serves ALL
# connected Google accounts (D17): it reads each account's calendars
# read-only, tags every event with its source account, MERGES + DEDUPES
# across accounts (by iCalUID), and computes one set of Calendar Insights.
# Never a provider per account.
#
# READ ONLY. It NEVER creates, edits, moves, accepts, declines, or deletes
# events. The only scope requested is calendar.readonly.
#
# Auth: the SHARED account-aware Google OAuth module (core/google-oauth.ps1)
# - installed-desktop-app flow (PKCE + loopback + offline refresh), with
# each account's tokens stored separately (keyed by email) in the gitignored
# calendar.tokens.json. One expired account never breaks the others.
#
# Private local files (gitignored, never printed/committed/logged):
#   calendar.config.json  - OAuth client id/secret for the desktop app
#   calendar.tokens.json  - per-account access/refresh tokens
# Registers as the generic 'calendar' live signal.
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
        clientId       = $clientId
        clientSecret   = $clientSecret
        configured     = -not [string]::IsNullOrWhiteSpace($clientId)
        source         = $source
        scope          = 'https://www.googleapis.com/auth/calendar.readonly'
        authEndpoint   = 'https://accounts.google.com/o/oauth2/v2/auth'
        tokenEndpoint  = 'https://oauth2.googleapis.com/token'
        revokeEndpoint = 'https://oauth2.googleapis.com/revoke'
        apiBase        = 'https://www.googleapis.com/calendar/v3'
        tokenPath      = (Get-GCalTokenPath)
        appName        = 'Google Calendar'
        diagSource     = 'calendar'
        readOnly       = $true
    }
}

# The subset passed to the shared OAuth module.
function Get-GCalOAuthConfig {
    $c = Get-GCalConfig
    return [pscustomobject]@{
        clientId = $c.clientId; clientSecret = $c.clientSecret; scope = $c.scope
        authEndpoint = $c.authEndpoint; tokenEndpoint = $c.tokenEndpoint; revokeEndpoint = $c.revokeEndpoint
        apiBase = $c.apiBase; tokenPath = $c.tokenPath; appName = $c.appName; diagSource = $c.diagSource
    }
}

function Write-GCalDiag { param([string]$Level = 'info', [string]$Message = '') if (Get-Command Write-TonyDiag -ErrorAction SilentlyContinue) { Write-TonyDiag -Level $Level -Source 'calendar' -Message $Message } }

# read-only GET against the Calendar API (delegates to the shared decoder).
function Invoke-GCalApi {
    param([string]$Token, [string]$Path, [hashtable]$Query = @{})
    return (Invoke-GoogleApi -Token $Token -BaseUrl (Get-GCalConfig).apiBase -Path $Path -Query $Query)
}

# Resolve an account's identity (primary calendar email) from a token.
function Resolve-GCalIdentity {
    param([Parameter(Mandatory)][string]$Token)
    $calList = Invoke-GCalApi -Token $Token -Path '/users/me/calendarList'
    $primary = @($calList.items | Where-Object { $_.primary }) | Select-Object -First 1
    if ($primary) { return [string]$primary.id }
    return $null
}

# ---- connect / disconnect (per account) ----------------------------
function Connect-GoogleCalendar {
    if (-not (Get-Command Connect-GoogleAccount -ErrorAction SilentlyContinue)) { return [pscustomobject]@{ ok = $false; state = 'error'; detail = 'OAuth module not loaded.' } }
    $cfg = Get-GCalConfig
    if (-not $cfg.configured) { return [pscustomobject]@{ ok = $false; state = 'not-configured'; detail = 'No OAuth client configured. Add calendar.config.json (client id/secret for a Desktop app).' } }
    return (Connect-GoogleAccount -Config (Get-GCalOAuthConfig) -ResolveIdentity { param($tok) Resolve-GCalIdentity -Token $tok })
}
function Disconnect-GoogleCalendar {
    param([Parameter(Mandatory)][string]$Account)
    return (Disconnect-GoogleAccount -Config (Get-GCalOAuthConfig) -Id $Account)
}
function Get-GCalAccountIds { return @(Get-GoogleAccountIds -Path (Get-GCalTokenPath)) }

function Get-GCalEventState {
    param([datetime]$Start, [datetime]$End, [datetime]$Now)
    if ($End -le $Now) { return 'completed' }
    if ($Start -le $Now -and $End -ge $Now) { return 'current' }
    return 'upcoming'
}

# Convert a raw Google event into the provider's structured event. Read only.
# Carries sourceAccount and iCalUID (used to dedupe the same event across
# accounts / calendars).
function Convert-GCalEvent {
    param($Raw, [string]$CalendarId, [datetime]$Now, [string]$SourceAccount = '')
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
        iCalUID            = [string]$Raw.iCalUID
        calendarId         = $CalendarId
        sourceAccount      = $SourceAccount
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

# Calendar Intelligence: the day at a glance, computed from the MERGED events
# across all accounts. Pure, deterministic, testable. All-day events are not
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

# Fetch the ~8-day window for ONE account (read-only), across its selected
# calendars. One unreadable calendar is skipped; one unreadable account is
# captured without breaking the others.
function Get-GCalAccountData {
    param([Parameter(Mandatory)][string]$Id, [datetime]$Now = (Get-Date))
    $cfg = Get-GCalConfig
    $at = Get-GoogleAccountAccessToken -Config (Get-GCalOAuthConfig) -Id $Id
    if (-not $at.ok) { return [pscustomobject]@{ ok = $false; id = $Id; email = $Id; state = $at.state; detail = $at.detail; events = @(); calendars = @(); timezone = $null } }
    try {
        $calList = Invoke-GCalApi -Token $at.token -Path '/users/me/calendarList'
        $cals = @($calList.items | Where-Object { $_.selected -ne $false })
        $primary = @($calList.items | Where-Object { $_.primary }) | Select-Object -First 1
        $email = if ($primary) { [string]$primary.id } else { $Id }
        if (($Id -eq 'default' -or $Id -like 'account-*') -and $primary) { Rename-GoogleAccountRecord -Path $cfg.tokenPath -OldId $Id -NewId $email }
        $tz = if ($primary -and $primary.timeZone) { [string]$primary.timeZone } else { [System.TimeZoneInfo]::Local.Id }

        $timeMin = $Now.Date.ToString('o')
        $timeMax = $Now.Date.AddDays(8).ToString('o')
        $events = @()
        foreach ($cal in $cals) {
            try {
                $ev = Invoke-GCalApi -Token $at.token -Path ("/calendars/{0}/events" -f [uri]::EscapeDataString($cal.id)) -Query @{ timeMin = $timeMin; timeMax = $timeMax; singleEvents = 'true'; orderBy = 'startTime'; maxResults = '100' }
                foreach ($raw in @($ev.items)) { $c = Convert-GCalEvent -Raw $raw -CalendarId $cal.id -Now $Now -SourceAccount $email; if ($c) { $events += $c } }
            } catch { }   # a single unreadable calendar (holiday/subscribed) never fails the account
        }
        $calSummaries = @($cals | ForEach-Object { [pscustomobject]@{ id = $_.id; summary = [string]$_.summary; primary = [bool]$_.primary; account = $email } })
        return [pscustomobject]@{ ok = $true; id = $email; email = $email; state = 'connected'; detail = ('Live from Google Calendar ({0}).' -f $email); events = @($events); calendars = $calSummaries; timezone = $tz }
    } catch {
        $msg = $_.Exception.Message; $state = 'error'
        if ($_.Exception.Response -and ($_.Exception.Response.PSObject.Properties.Name -contains 'StatusCode')) {
            $sc = [int]$_.Exception.Response.StatusCode
            if ($sc -eq 401) { $state = 'needs-attention'; $msg = 'Authorization expired; reconnect this account.' }
            elseif ($sc -eq 403) { $state = 'denied'; $msg = 'I can reach Google Calendar, but the request was denied.' }
        } elseif ($_.Exception -is [System.Net.WebException]) { $state = 'network-error'; $msg = 'The network is unavailable.' }
        Write-GCalDiag -Level 'error' -Message ("Calendar fetch {0} for one account." -f $state)
        return [pscustomobject]@{ ok = $false; id = $Id; email = $Id; state = $state; detail = $msg; events = @(); calendars = @(); timezone = $null }
    }
}

# ---- THE contract: merged calendar across ALL accounts -------------
function Get-Calendar {
    param([string]$When = 'today', [datetime]$Now = (Get-Date))
    $cfg = Get-GCalConfig
    $nowStr = $Now.ToString('yyyy-MM-dd HH:mm:ss')
    $fail = {
        param($state, $detail)
        [pscustomobject]@{ provider = 'calendar'; ok = $false; errorState = $state; status = [pscustomobject]@{ state = $state; detail = $detail; lastRefresh = $null; lastError = $detail }; timestamp = $nowStr; account = $null; accounts = @(); accountCount = 0; timezone = $null; calendars = @(); events = @(); nextEvent = $null; todayCount = 0; tomorrowCount = 0; freeWindows = @(); conflicts = @(); insights = $null }
    }
    if (-not $cfg.configured) { return (& $fail 'not-configured' 'Google Calendar is not connected yet.') }
    $ids = @(Get-GoogleAccountIds -Path $cfg.tokenPath)
    if ($ids.Count -eq 0) { return (& $fail 'not-connected' 'Google Calendar is not connected yet.') }

    $allEvents = @(); $allCals = @(); $accountsInfo = @(); $anyOk = $false; $tz = $null; $firstBadState = $null; $firstBadDetail = $null
    foreach ($id in $ids) {
        $d = Get-GCalAccountData -Id $id -Now $Now
        $accountsInfo += [pscustomobject]@{ email = $d.email; state = $d.state; detail = $d.detail; count = @($d.events).Count }
        if ($d.ok) { $anyOk = $true; $allEvents += @($d.events); $allCals += @($d.calendars); if (-not $tz) { $tz = $d.timezone } }
        elseif (-not $firstBadState) { $firstBadState = $d.state; $firstBadDetail = $d.detail }
    }
    if (-not $anyOk) { return (& $fail $firstBadState $firstBadDetail) }

    # MERGE across accounts: dedupe the same event (same iCalUID) seen on more
    # than one account/calendar, keeping one copy and remembering every account
    # it appears in. This is where account data is merged before intelligence.
    $seen = @{}; $events = @()
    foreach ($e in @($allEvents | Sort-Object start)) {
        $key = if ($e.iCalUID) { 'uid:' + $e.iCalUID } else { 'id:' + [string]$e.id }
        $sa = [string]$e.sourceAccount
        if ($seen.ContainsKey($key)) {
            $ex = $seen[$key]
            if ($sa -and ($ex.sourceAccounts -notcontains $sa)) { $ex.sourceAccounts = @($ex.sourceAccounts + $sa) }
            continue
        }
        $e | Add-Member -NotePropertyName sourceAccounts -NotePropertyValue @($(if ($sa) { $sa } else { $null }) | Where-Object { $_ }) -Force
        $seen[$key] = $e; $events += $e
    }
    $events = @($events | Sort-Object start)

    $today = @($events | Where-Object { $_.start.Date -eq $Now.Date })
    $tomorrow = @($events | Where-Object { $_.start.Date -eq $Now.Date.AddDays(1) })
    $next = @($events | Where-Object { $_.start -gt $Now -and -not $_.allDay } | Sort-Object start | Select-Object -First 1)
    $freeToday = Get-GCalFreeWindows -Date $Now -Events $today
    $freeTomorrow = Get-GCalFreeWindows -Date $Now.AddDays(1) -Events $tomorrow
    $insights = Get-CalendarInsights -Events $events -Now $Now

    $connected = @($accountsInfo | Where-Object { $_.state -eq 'connected' })
    $primary = if ($connected.Count -gt 0) { $connected[0].email } else { $null }
    $degraded = @($accountsInfo | Where-Object { $_.state -ne 'connected' })
    $detail = if ($degraded.Count -eq 0) { ('Live from Google Calendar ({0} account(s)).' -f $connected.Count) }
    else { ('Live from Google Calendar ({0} of {1} account(s); {2} need attention).' -f $connected.Count, $accountsInfo.Count, $degraded.Count) }

    return [pscustomobject]@{
        provider     = 'calendar'; ok = $true; errorState = $null
        status       = [pscustomobject]@{ state = 'connected'; detail = $detail; lastRefresh = $nowStr; lastError = $(if ($degraded.Count) { $degraded[0].detail } else { $null }) }
        timestamp    = $nowStr; account = $primary; accounts = @($accountsInfo); accountCount = @($accountsInfo).Count; timezone = $tz
        calendars    = @($allCals)
        events       = @($events); nextEvent = @($next)[0]
        todayCount   = $today.Count; tomorrowCount = $tomorrow.Count
        freeWindows  = @(@($freeToday) + @($freeTomorrow))
        conflicts    = @(Get-GCalConflicts -Events $events)
        insights     = $insights
    }
}

# Status for Settings. Without -Live: config/connection state (per account),
# no network. With -Live: a real read to confirm access across all accounts.
function Get-GCalStatus {
    param([switch]$Live)
    $cfg = Get-GCalConfig
    if (-not $cfg.configured) { return [pscustomobject]@{ name = 'Google Calendar'; state = 'not-configured'; detail = 'No OAuth client configured. Add a Desktop-app client id/secret to calendar.config.json, then Connect.'; account = $null; accounts = @(); readOnly = $true; lastRefresh = $null; lastError = $null } }
    $ids = @(Get-GoogleAccountIds -Path $cfg.tokenPath)
    if ($ids.Count -eq 0) { return [pscustomobject]@{ name = 'Google Calendar'; state = 'not-connected'; detail = 'Configured but not connected. Click Connect Google Calendar.'; account = $null; accounts = @(); readOnly = $true; lastRefresh = $null; lastError = $null } }
    if (-not $Live) {
        $accts = @($ids | ForEach-Object { [pscustomobject]@{ email = $_; state = 'connected'; detail = 'Connected (read-only).' } })
        return [pscustomobject]@{ name = 'Google Calendar'; state = 'connected'; detail = ('{0} account(s) connected (read-only). Run Test Connection to confirm live access.' -f $ids.Count); account = $ids[0]; accounts = $accts; readOnly = $true; lastRefresh = $null; lastError = $null }
    }
    $c = Get-Calendar -When 'today'
    $accts = @($c.accounts | ForEach-Object { [pscustomobject]@{ email = $_.email; state = $_.state; detail = $_.detail } })
    $state = if ($c.ok) { 'connected' } else { $c.status.state }
    return [pscustomobject]@{ name = 'Google Calendar'; state = $state; detail = $c.status.detail; account = $c.account; accounts = $accts; readOnly = $true; lastRefresh = $c.status.lastRefresh; lastError = $c.status.lastError }
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
            description = 'Read-only Google Calendar across one or more Google accounts (OAuth 2.0 desktop, PKCE). Merged and explained by Tony.'
            relevant    = { param($text) Test-CalendarRelevant $text }
            query       = { param($opts) $when = if ($opts -and $opts.When) { $opts.When } else { 'today' }; Get-Calendar -When $when }
            status      = { param($live) Get-GCalStatus -Live:([bool]$live) }
        })
}
