# =====================================================================
# connectors/google-calendar.ps1  -  Google Calendar WRITE connector (Epic 17)
# ---------------------------------------------------------------------
# GIOK's FIRST external side-effecting connector. It gives the Executive Action
# Engine the ability to create / update / cancel Google Calendar events - and it
# is the ONLY code in GIOK that writes a calendar. See
# Blueprint/Google_Calendar_Connector.md for the full contract.
#
# SEPARATION OF CONCERNS (permanent):
#   * The Action Engine owns approval validation + instance binding, the
#     immutable intent, idempotency, state transitions, timeout policy, audit,
#     the REQUIREMENT to verify before success, terminal state, and recovery.
#   * This connector owns ONLY: connector-specific payload validation, the
#     approved Google request, safe provider result metadata, and the read-back
#     of the event by its exact provider id for verification.
#   * The connector MAY NOT approve proposals, change execution state, mark
#     itself succeeded, write GIOK business stores, expose credentials, or log
#     private calendar content.
#
# This file contains ALL Google Calendar API knowledge. No Google call lives in
# action-engine.ps1, executive-inbox.ps1, tony-ui.ps1, or any reasoning module.
#
# WRITE SCOPE: https://www.googleapis.com/auth/calendar.events (least privilege).
# This is a SEPARATE consent and a SEPARATE token store from the read-only
# provider (calendar.readonly / calendar.tokens.json). Write tokens live in the
# gitignored calendar.write.tokens.json. The two share the same desktop client
# but never share tokens - a read token can never write.
#
# Windows PowerShell 5.1: pure-ASCII source, no ternary, no $Input param.
# =====================================================================

$ErrorActionPreference = 'Stop'

$script:GCalConnectorId      = 'google-calendar'
$script:GCalWriteScope       = 'https://www.googleapis.com/auth/calendar.events'
$script:GCalApiBase          = 'https://www.googleapis.com/calendar/v3'
$script:GCalAuthEndpoint     = 'https://accounts.google.com/o/oauth2/v2/auth'
$script:GCalTokenEndpoint    = 'https://oauth2.googleapis.com/token'
$script:GCalRevokeEndpoint   = 'https://oauth2.googleapis.com/revoke'
$script:GCalDiagSource       = 'google-calendar-connector'
$script:GCalHttpTimeoutSec   = 20
# The provider-neutral action types this one connector serves.
$script:GCalActionTypes      = @('calendar.create-event', 'calendar.create-focus-block', 'calendar.create-follow-up-block', 'calendar.protect-family-time', 'calendar.update-event', 'calendar.cancel-event')
$script:GCalCreateTypes      = @('calendar.create-event', 'calendar.create-focus-block', 'calendar.create-follow-up-block', 'calendar.protect-family-time')
function Get-GCalActionTypes { return $script:GCalActionTypes }
function Test-GCalActionType { param([string]$Type) return ($script:GCalActionTypes -contains [string]$Type) }
function Test-GCalCreateType { param([string]$Type) return ($script:GCalCreateTypes -contains [string]$Type) }

# ---- diagnostics: states/counts/error-classes only, NEVER tokens or content --
function Write-GCalDiag {
    param([string]$Level = 'info', [string]$Message = '')
    if (Get-Command Write-TonyDiag -ErrorAction SilentlyContinue) { Write-TonyDiag -Level $Level -Source $script:GCalDiagSource -Message $Message }
}

# ---- config + token paths (local, gitignored) ------------------------------
# Reuse the shared desktop client (calendar.config.json); write tokens in their
# OWN file so the write consent is independently connectable/revocable.
function Get-GCalConfigPath      { return (Join-Path $PSScriptRoot '..\..\providers\calendar.config.json') }
function Get-GCalWriteTokenPath  { return (Join-Path $PSScriptRoot '..\..\..\calendar.write.tokens.json') }

# Load the desktop OAuth client (id/secret). Returns $null if unconfigured, so
# availability can report 'not-configured' truthfully (never a fake client).
function Get-GCalClientConfig {
    $p = Get-GCalConfigPath
    if (-not (Test-Path $p)) { return $null }
    $cfg = $null
    try { $cfg = Get-Content $p -Raw -Encoding UTF8 | ConvertFrom-Json } catch { return $null }
    if (-not $cfg -or [string]::IsNullOrWhiteSpace([string]$cfg.clientId) -or ([string]$cfg.clientId -like 'YOUR_*')) { return $null }
    return $cfg
}

# The provider-neutral OAuth config object consumed by core/google-oauth.ps1,
# carrying the WRITE scope and the WRITE token path. Never contains a token.
function Get-GCalWriteOAuthConfig {
    $cfg = Get-GCalClientConfig
    if (-not $cfg) { return $null }
    return [pscustomobject]@{
        clientId      = [string]$cfg.clientId
        clientSecret  = [string]$cfg.clientSecret
        scope         = $script:GCalWriteScope
        authEndpoint  = $script:GCalAuthEndpoint
        tokenEndpoint = $script:GCalTokenEndpoint
        revokeEndpoint = $script:GCalRevokeEndpoint
        apiBase       = $script:GCalApiBase
        tokenPath     = (Get-GCalWriteTokenPath)
        appName       = 'Google Calendar (write)'
        diagSource    = $script:GCalDiagSource
    }
}

# ---- availability: truthful, never guesses -----------------------------------
# Reports whether the connector can perform a write RIGHT NOW, without leaking
# anything. States: not-configured | not-connected | connected | needs-attention.
function Get-GCalWriteAvailability {
    param([string]$AccountId = '')
    $oauth = Get-GCalWriteOAuthConfig
    if (-not $oauth) { return [pscustomobject]@{ ok = $false; state = 'not-configured'; detail = 'Google Calendar write is not configured (no OAuth client).'; accounts = @() } }
    $ids = @()
    try { $ids = @(Get-GoogleAccountIds -Path $oauth.tokenPath) } catch { $ids = @() }
    if (@($ids).Count -eq 0) { return [pscustomobject]@{ ok = $false; state = 'not-connected'; detail = 'Google Calendar write is not connected yet.'; accounts = @() } }
    $target = if ($AccountId) { $AccountId } else { $ids[0] }
    $tok = $null
    try { $tok = Get-GoogleAccountAccessToken -Config $oauth -Id $target } catch { $tok = $null }
    if (-not $tok -or -not $tok.ok) {
        $detail = if ($tok -and $tok.detail) { [string]$tok.detail } else { 'Authorization expired; reconnect Google Calendar write.' }
        return [pscustomobject]@{ ok = $false; state = 'needs-attention'; detail = $detail; accounts = @($ids) }
    }
    return [pscustomobject]@{ ok = $true; state = 'connected'; detail = 'Google Calendar write is connected.'; accounts = @($ids); account = $target }
}
function Test-GCalWriteConnected { param([string]$AccountId = '') return [bool](Get-GCalWriteAvailability -AccountId $AccountId).ok }

# ---- connect / disconnect (explicit user actions) ----------------------------
# Resolve the account email with the write token (calendarList primary), so
# write tokens are keyed by the same email the read side uses.
function Resolve-GCalAccountIdentity {
    param([Parameter(Mandatory)][string]$AccessToken)
    try {
        $me = Invoke-GoogleApi -Token $AccessToken -BaseUrl $script:GCalApiBase -Path '/users/me/calendarList/primary'
        if ($me -and $me.id) { return [string]$me.id }
    } catch { }
    return $null
}
function Connect-GCalWrite {
    $oauth = Get-GCalWriteOAuthConfig
    if (-not $oauth) { return [pscustomobject]@{ ok = $false; state = 'not-configured'; detail = 'Configure the Google Calendar OAuth client first.'; id = $null } }
    return (Connect-GoogleAccount -Config $oauth -ResolveIdentity { param($tok) Resolve-GCalAccountIdentity -AccessToken $tok })
}
function Disconnect-GCalWrite {
    param([Parameter(Mandatory)][string]$AccountId)
    $oauth = Get-GCalWriteOAuthConfig
    if (-not $oauth) { return [pscustomobject]@{ ok = $false; state = 'not-configured'; detail = 'Nothing to disconnect.'; id = $AccountId } }
    return (Disconnect-GoogleAccount -Config $oauth -Id $AccountId)
}

# ---- deterministic, provider-safe client event id ----------------------------
# Google accepts a client-specified event id (base32hex: lowercase a-v + 0-9,
# length 5-1024, unique per calendar). Lowercase hex is a SUBSET of base32hex, so
# 'giok' + hex(MD5(seed)) is always valid. Deterministic in the execution
# idempotency key -> the SAME approved proposal always yields the SAME event id,
# so a retry/crash/restart re-inserts the same id (409 -> already created), never
# a duplicate; two distinct proposals yield different ids.
function Get-GCalClientEventId {
    param([Parameter(Mandatory)][string]$Seed)
    $md5 = [System.Security.Cryptography.MD5]::Create()
    $hex = ([System.BitConverter]::ToString($md5.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Seed))) -replace '-', '').ToLower()
    return ('giok' + $hex)   # 4 + 32 = 36 chars, all within [0-9a-v]
}
# Guard: confirm an id conforms to Google's base32hex id rules.
function Test-GCalEventIdFormat {
    param([string]$Id)
    if ([string]::IsNullOrWhiteSpace($Id)) { return $false }
    if ($Id.Length -lt 5 -or $Id.Length -gt 1024) { return $false }
    return ($Id -cmatch '^[0-9a-v]+$')
}

# ---- timezone (IANA) validation - NEVER guessed ------------------------------
# .NET Framework on Windows has no IANA/ICU tz database, so we validate the IANA
# name against an embedded set of canonical zones (extendable). An absent or
# unrecognized zone is a VALIDATION FAILURE, not a default. DST ambiguity is
# handled separately by requiring an explicit UTC offset on start/end (below).
$script:GCalIanaZones = @(
    'UTC',
    'America/New_York', 'America/Detroit', 'America/Chicago', 'America/Denver', 'America/Phoenix',
    'America/Los_Angeles', 'America/Anchorage', 'America/Adak', 'America/Boise', 'America/Indiana/Indianapolis',
    'America/Kentucky/Louisville', 'America/Toronto', 'America/Vancouver', 'America/Edmonton', 'America/Halifax',
    'America/St_Johns', 'America/Mexico_City', 'America/Sao_Paulo', 'America/Bogota', 'America/Lima',
    'America/Argentina/Buenos_Aires', 'Pacific/Honolulu', 'Pacific/Auckland', 'Pacific/Fiji',
    'Europe/London', 'Europe/Dublin', 'Europe/Lisbon', 'Europe/Madrid', 'Europe/Paris', 'Europe/Berlin',
    'Europe/Amsterdam', 'Europe/Brussels', 'Europe/Zurich', 'Europe/Rome', 'Europe/Vienna', 'Europe/Prague',
    'Europe/Warsaw', 'Europe/Stockholm', 'Europe/Oslo', 'Europe/Copenhagen', 'Europe/Helsinki', 'Europe/Athens',
    'Europe/Istanbul', 'Europe/Moscow', 'Europe/Kiev', 'Europe/Bucharest',
    'Africa/Cairo', 'Africa/Johannesburg', 'Africa/Lagos', 'Africa/Nairobi', 'Africa/Casablanca',
    'Asia/Jerusalem', 'Asia/Dubai', 'Asia/Karachi', 'Asia/Kolkata', 'Asia/Dhaka', 'Asia/Bangkok',
    'Asia/Jakarta', 'Asia/Singapore', 'Asia/Hong_Kong', 'Asia/Shanghai', 'Asia/Taipei', 'Asia/Tokyo',
    'Asia/Seoul', 'Asia/Manila', 'Asia/Kuala_Lumpur',
    'Australia/Sydney', 'Australia/Melbourne', 'Australia/Brisbane', 'Australia/Perth', 'Australia/Adelaide'
)
function Test-GCalTimezone {
    param([string]$Timezone)
    if ([string]::IsNullOrWhiteSpace($Timezone)) { return $false }
    return ($script:GCalIanaZones -contains [string]$Timezone)
}

# An event instant is unambiguous ONLY if the string carries an explicit UTC
# offset (Z or +/-HH:MM). A bare local time is AMBIGUOUS across a DST transition,
# so it is rejected (mirrors the engine's 'reminder' verb). Returns a normalized
# RFC3339 string with explicit offset, or $null if it is bare/unparseable.
function ConvertTo-GCalInstant {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return $null }
    $hasOffset = ($Value -match 'Z$') -or ($Value -match '[+-]\d{2}:?\d{2}$')
    if (-not $hasOffset) { return $null }   # ambiguous local time - reject
    $dto = [DateTimeOffset]::MinValue
    $styles = [System.Globalization.DateTimeStyles]::RoundtripKind
    if (-not [DateTimeOffset]::TryParse($Value, [System.Globalization.CultureInfo]::InvariantCulture, $styles, [ref]$dto)) { return $null }
    return $dto.ToString('yyyy-MM-ddTHH:mm:sszzz')
}

# ---- payload validation (BEFORE any intent/side effect) ----------------------
# Strict, provider-neutral. Returns { valid; reason; payload } - payload is the
# NORMALIZED, safe request contract (never carries a token). Unknown fields
# reject; timezone is never guessed; end must be after start; update/cancel need
# an exact eventId; a change set must be non-empty and may not touch identity.
$script:GCalCreateFields = @('calendarId', 'title', 'start', 'end', 'timezone', 'description', 'location', 'sourceProposalId', 'sourceUid')
$script:GCalUpdateFields = @('calendarId', 'eventId', 'expectedProviderVersion', 'changes')
$script:GCalCancelFields = @('calendarId', 'eventId', 'expectedProviderVersion')
$script:GCalChangeFields = @('title', 'start', 'end', 'timezone', 'description', 'location')

function Test-GCalCalendarId {
    param([string]$CalendarId)
    if ([string]::IsNullOrWhiteSpace($CalendarId)) { return $false }
    # 'primary' or an email-like / google calendar id; reject whitespace/control.
    if ($CalendarId -eq 'primary') { return $true }
    return ($CalendarId -cmatch '^[^\s<>]+@[^\s<>]+$') -or ($CalendarId -cmatch '^[A-Za-z0-9._%+\-]+@(group\.calendar\.google\.com|gmail\.com|.+\..+)$')
}

function Test-GCalPayload {
    param([Parameter(Mandatory)][string]$ActionType, [Parameter(Mandatory)] $Payload)
    $fail = { param($r) [pscustomobject]@{ valid = $false; reason = $r; payload = $null } }
    if (-not $Payload) { return (& $fail 'no payload') }
    $names = @($Payload.PSObject.Properties.Name)

    if (Test-GCalCreateType -Type $ActionType) {
        foreach ($n in $names) { if ($script:GCalCreateFields -notcontains $n) { return (& $fail ("unsupported field: {0}" -f $n)) } }
        # V1 never adds attendees / notifications
        if ($names -contains 'attendees') { return (& $fail 'attendees are not supported in V1') }
        if ([string]::IsNullOrWhiteSpace([string]$Payload.title)) { return (& $fail 'create requires a non-empty title') }
        if (-not (Test-GCalCalendarId -CalendarId ([string]$Payload.calendarId))) { return (& $fail 'malformed calendarId') }
        if (-not (Test-GCalTimezone -Timezone ([string]$Payload.timezone))) { return (& $fail ("invalid or unrecognized timezone: '{0}'" -f $Payload.timezone)) }
        $startN = ConvertTo-GCalInstant -Value ([string]$Payload.start)
        $endN   = ConvertTo-GCalInstant -Value ([string]$Payload.end)
        if (-not $startN) { return (& $fail 'invalid start (must be RFC3339 with an explicit UTC offset; a bare local time is ambiguous across DST)') }
        if (-not $endN)   { return (& $fail 'invalid end (must be RFC3339 with an explicit UTC offset; a bare local time is ambiguous across DST)') }
        if ([DateTimeOffset]::Parse($endN) -le [DateTimeOffset]::Parse($startN)) { return (& $fail 'end must be after start') }
        $p = [pscustomobject]@{
            action = 'create'; calendarId = [string]$Payload.calendarId; title = [string]$Payload.title
            start = $startN; end = $endN; timezone = [string]$Payload.timezone
            description = [string]$(if ($names -contains 'description') { $Payload.description } else { '' })
            location = [string]$(if ($names -contains 'location') { $Payload.location } else { '' })
            sourceProposalId = [string]$(if ($names -contains 'sourceProposalId') { $Payload.sourceProposalId } else { '' })
            sourceUid = [string]$(if ($names -contains 'sourceUid') { $Payload.sourceUid } else { '' })
        }
        return [pscustomobject]@{ valid = $true; reason = ''; payload = $p }
    }

    if ($ActionType -eq 'calendar.update-event') {
        foreach ($n in $names) { if ($script:GCalUpdateFields -notcontains $n) { return (& $fail ("unsupported field: {0}" -f $n)) } }
        if (-not (Test-GCalCalendarId -CalendarId ([string]$Payload.calendarId))) { return (& $fail 'malformed calendarId') }
        if ([string]::IsNullOrWhiteSpace([string]$Payload.eventId)) { return (& $fail 'update requires an eventId') }
        if (-not ($names -contains 'changes') -or -not $Payload.changes) { return (& $fail 'update requires a non-empty change set') }
        $cnames = @($Payload.changes.PSObject.Properties.Name)
        if (@($cnames).Count -eq 0) { return (& $fail 'empty change set') }
        foreach ($cn in $cnames) {
            if ($cn -in @('eventId', 'calendarId', 'id')) { return (& $fail 'cannot change immutable provider identity') }
            if ($script:GCalChangeFields -notcontains $cn) { return (& $fail ("unsupported change field: {0}" -f $cn)) }
        }
        $changes = @{}
        if ($cnames -contains 'title') { if ([string]::IsNullOrWhiteSpace([string]$Payload.changes.title)) { return (& $fail 'title cannot be blanked') } $changes['title'] = [string]$Payload.changes.title }
        if (($cnames -contains 'start') -or ($cnames -contains 'end') -or ($cnames -contains 'timezone')) {
            # a time change must supply start+end+timezone together, unambiguously
            if (-not (($cnames -contains 'start') -and ($cnames -contains 'end') -and ($cnames -contains 'timezone'))) { return (& $fail 'a time change must include start, end, and timezone together') }
            if (-not (Test-GCalTimezone -Timezone ([string]$Payload.changes.timezone))) { return (& $fail ("invalid or unrecognized timezone: '{0}'" -f $Payload.changes.timezone)) }
            $s = ConvertTo-GCalInstant -Value ([string]$Payload.changes.start)
            $e = ConvertTo-GCalInstant -Value ([string]$Payload.changes.end)
            if (-not $s) { return (& $fail 'invalid start (needs explicit UTC offset)') }
            if (-not $e) { return (& $fail 'invalid end (needs explicit UTC offset)') }
            if ([DateTimeOffset]::Parse($e) -le [DateTimeOffset]::Parse($s)) { return (& $fail 'end must be after start') }
            $changes['start'] = $s; $changes['end'] = $e; $changes['timezone'] = [string]$Payload.changes.timezone
        }
        if ($cnames -contains 'description') { $changes['description'] = [string]$Payload.changes.description }
        if ($cnames -contains 'location') { $changes['location'] = [string]$Payload.changes.location }
        $p = [pscustomobject]@{
            action = 'update'; calendarId = [string]$Payload.calendarId; eventId = [string]$Payload.eventId
            expectedProviderVersion = [string]$(if ($names -contains 'expectedProviderVersion') { $Payload.expectedProviderVersion } else { '' })
            changes = ([pscustomobject]$changes)
        }
        return [pscustomobject]@{ valid = $true; reason = ''; payload = $p }
    }

    if ($ActionType -eq 'calendar.cancel-event') {
        foreach ($n in $names) { if ($script:GCalCancelFields -notcontains $n) { return (& $fail ("unsupported field: {0}" -f $n)) } }
        if (-not (Test-GCalCalendarId -CalendarId ([string]$Payload.calendarId))) { return (& $fail 'malformed calendarId') }
        if ([string]::IsNullOrWhiteSpace([string]$Payload.eventId)) { return (& $fail 'cancel requires an eventId') }
        $p = [pscustomobject]@{
            action = 'cancel'; calendarId = [string]$Payload.calendarId; eventId = [string]$Payload.eventId
            expectedProviderVersion = [string]$(if ($names -contains 'expectedProviderVersion') { $Payload.expectedProviderVersion } else { '' })
        }
        return [pscustomobject]@{ valid = $true; reason = ''; payload = $p }
    }

    return (& $fail ("unsupported calendar action type: {0}" -f $ActionType))
}

# ---- redaction: what may appear in audit detail ------------------------------
# Titles/descriptions/locations are PRIVATE and never enter the audit detail.
# Only the deterministic (non-sensitive) event id and a safe calendar
# representation are safe. This is the private-content policy for external
# payloads (Epic 17), enforced before anything is written to the execution log.
function Get-GCalSafeCalendarRef {
    param([string]$CalendarId)
    if ([string]::IsNullOrWhiteSpace($CalendarId)) { return 'cal:unknown' }
    if ($CalendarId -eq 'primary') { return 'cal:primary' }
    $md5 = [System.Security.Cryptography.MD5]::Create()
    $h = ([System.BitConverter]::ToString($md5.ComputeHash([System.Text.Encoding]::UTF8.GetBytes([string]$CalendarId))) -replace '-', '').Substring(0, 8).ToLower()
    return ('cal:' + $h)
}
# Map a raw provider/HTTP error to a SAFE class (never the message/body/token).
function Get-GCalSafeErrorClass {
    param($ErrorRecord)
    $code = 0
    try {
        $resp = $ErrorRecord.Exception.Response
        if ($resp -and ($resp.PSObject.Properties.Name -contains 'StatusCode')) { $code = [int]$resp.StatusCode }
    } catch { }
    switch ($code) {
        401 { return 'unauthorized' }
        403 { return 'permission-denied' }
        404 { return 'not-found' }
        409 { return 'already-exists' }
        410 { return 'gone' }
        412 { return 'precondition-failed' }
        429 { return 'rate-limited' }
        0   { return 'network-or-timeout' }
        default { if ($code -ge 500) { return 'provider-unavailable' } return ('http-' + $code) }
    }
}

# =====================================================================
# WRITE PATH - token seam + Google API seams + engine handlers (Epic 17)
# ---------------------------------------------------------------------
# Every Google Calendar HTTP call goes through ONE of the four seams below
# (Insert/Get/Patch/Delete). Tests OVERRIDE these four (and the token seam) to
# simulate provider state with no network - exactly how the execution harness
# overrides Get-InboxPath. Real implementations use a bounded -TimeoutSec and
# never log a token, body, or event content.
# =====================================================================

# Resolve a WRITE access token for the target (or default) account. Never logs
# the token. Returns { ok; token; account; state; detail }.
function Get-GCalWriteAccessToken {
    param([string]$AccountId = '')
    $oauth = Get-GCalWriteOAuthConfig
    if (-not $oauth) { return [pscustomobject]@{ ok = $false; token = $null; account = $null; state = 'not-configured'; detail = 'Google Calendar write is not configured.' } }
    $ids = @()
    try { $ids = @(Get-GoogleAccountIds -Path $oauth.tokenPath) } catch { $ids = @() }
    if (@($ids).Count -eq 0) { return [pscustomobject]@{ ok = $false; token = $null; account = $null; state = 'not-connected'; detail = 'Google Calendar write is not connected.' } }
    $target = if ($AccountId) { $AccountId } else { $ids[0] }
    $t = $null
    try { $t = Get-GoogleAccountAccessToken -Config $oauth -Id $target } catch { $t = $null }
    if (-not $t -or -not $t.ok) {
        $detail = if ($t -and $t.detail) { [string]$t.detail } else { 'Authorization expired; reconnect Google Calendar write.' }
        return [pscustomobject]@{ ok = $false; token = $null; account = $target; state = 'needs-attention'; detail = $detail }
    }
    return [pscustomobject]@{ ok = $true; token = [string]$t.token; account = $target; state = 'connected'; detail = 'ok' }
}

# ---- Google Calendar API seams (real impls; tests override) ------------------
function Invoke-GCalHttp {
    param([Parameter(Mandatory)][string]$Token, [Parameter(Mandatory)][string]$Method, [Parameter(Mandatory)][string]$Url, $Body = $null)
    $headers = @{ Authorization = ("Bearer {0}" -f $Token) }
    $args = @{ Uri = $Url; Method = $Method; Headers = $headers; UseBasicParsing = $true; TimeoutSec = $script:GCalHttpTimeoutSec }
    if ($null -ne $Body) { $args['Body'] = ($Body | ConvertTo-Json -Depth 8); $args['ContentType'] = 'application/json' }
    $resp = Invoke-WebRequest @args
    $raw = $resp.RawContentStream.ToArray()
    if (-not $raw -or $raw.Length -eq 0) { return $null }
    return ([System.Text.Encoding]::UTF8.GetString($raw) | ConvertFrom-Json)
}
function Invoke-GCalInsert {
    param([Parameter(Mandatory)][string]$Token, [Parameter(Mandatory)][string]$CalendarId, [Parameter(Mandatory)] $Body)
    $url = ('{0}/calendars/{1}/events?sendUpdates=none' -f $script:GCalApiBase, [uri]::EscapeDataString($CalendarId))
    return (Invoke-GCalHttp -Token $Token -Method 'POST' -Url $url -Body $Body)
}
function Invoke-GCalGet {
    param([Parameter(Mandatory)][string]$Token, [Parameter(Mandatory)][string]$CalendarId, [Parameter(Mandatory)][string]$EventId)
    $url = ('{0}/calendars/{1}/events/{2}' -f $script:GCalApiBase, [uri]::EscapeDataString($CalendarId), [uri]::EscapeDataString($EventId))
    return (Invoke-GCalHttp -Token $Token -Method 'GET' -Url $url)
}
function Invoke-GCalPatch {
    param([Parameter(Mandatory)][string]$Token, [Parameter(Mandatory)][string]$CalendarId, [Parameter(Mandatory)][string]$EventId, [Parameter(Mandatory)] $Body)
    $url = ('{0}/calendars/{1}/events/{2}?sendUpdates=none' -f $script:GCalApiBase, [uri]::EscapeDataString($CalendarId), [uri]::EscapeDataString($EventId))
    return (Invoke-GCalHttp -Token $Token -Method 'PATCH' -Url $url -Body $Body)
}
function Invoke-GCalDelete {
    param([Parameter(Mandatory)][string]$Token, [Parameter(Mandatory)][string]$CalendarId, [Parameter(Mandatory)][string]$EventId)
    $url = ('{0}/calendars/{1}/events/{2}?sendUpdates=none' -f $script:GCalApiBase, [uri]::EscapeDataString($CalendarId), [uri]::EscapeDataString($EventId))
    return (Invoke-GCalHttp -Token $Token -Method 'DELETE' -Url $url)
}

# ---- BuildIntent: connector validation + normalization -> intent fields ------
# Runs BEFORE any side effect. Derives the DETERMINISTIC client event id from the
# engine's execution idempotency key, so the same approved proposal always maps to
# the same event id (idempotent create; safe recovery), and two distinct proposals
# map to different ids. The fields become the immutable 'connector' intent.
function New-GCalIntent {
    param([Parameter(Mandatory)] $Proposal)
    $type = [string]$Proposal.type
    if (-not (Test-GCalActionType -Type $type)) { return [pscustomobject]@{ valid = $false; reason = ("not a calendar action type: {0}" -f $type); fields = $null } }
    if (-not ($Proposal.PSObject.Properties.Name -contains 'payload') -or -not $Proposal.payload) { return [pscustomobject]@{ valid = $false; reason = 'calendar action requires a payload'; fields = $null } }
    $v = Test-GCalPayload -ActionType $type -Payload $Proposal.payload
    if (-not $v.valid) { return [pscustomobject]@{ valid = $false; reason = $v.reason; fields = $null } }
    $p = $v.payload
    $seed = Get-ExecutionIdempotencyKey -Proposal $Proposal
    $fields = @{ connector = $script:GCalConnectorId; connectorAction = $p.action; calendarId = $p.calendarId; safeCalendarRef = (Get-GCalSafeCalendarRef -CalendarId $p.calendarId) }
    if ($p.action -eq 'create') {
        $fields['clientEventId'] = (Get-GCalClientEventId -Seed $seed)
        $fields['title'] = $p.title; $fields['start'] = $p.start; $fields['end'] = $p.end; $fields['timezone'] = $p.timezone
        $fields['description'] = $p.description; $fields['location'] = $p.location
    }
    elseif ($p.action -eq 'update') {
        $fields['eventId'] = $p.eventId; $fields['expectedProviderVersion'] = $p.expectedProviderVersion; $fields['changes'] = $p.changes
    }
    elseif ($p.action -eq 'cancel') {
        $fields['eventId'] = $p.eventId; $fields['expectedProviderVersion'] = $p.expectedProviderVersion
    }
    return [pscustomobject]@{ valid = $true; reason = ''; fields = $fields }
}

# ---- Execute: perform the approved request, return safe metadata -------------
# newId carries the PROVIDER event id (the verification anchor). Never returns or
# logs a token/body. A 409 on create means the deterministic id already exists ->
# idempotent: read it back and treat as created (never a duplicate).
function Invoke-GCalConnectorExecute {
    param($Request)
    $i = $Request.intent
    $tok = Get-GCalWriteAccessToken
    if (-not $tok.ok) { return [pscustomobject]@{ ok = $false; message = ("Google Calendar write is unavailable ({0})." -f $tok.state) } }
    $action = [string]$i.connectorAction
    try {
        if ($action -eq 'create') {
            $body = [pscustomobject]@{
                id      = [string]$i.clientEventId
                summary = [string]$i.title
                start   = [pscustomobject]@{ dateTime = [string]$i.start; timeZone = [string]$i.timezone }
                end     = [pscustomobject]@{ dateTime = [string]$i.end; timeZone = [string]$i.timezone }
            }
            if (-not [string]::IsNullOrWhiteSpace([string]$i.description)) { $body | Add-Member -NotePropertyName description -NotePropertyValue ([string]$i.description) }
            if (-not [string]::IsNullOrWhiteSpace([string]$i.location)) { $body | Add-Member -NotePropertyName location -NotePropertyValue ([string]$i.location) }
            $ev = $null
            try { $ev = Invoke-GCalInsert -Token $tok.token -CalendarId ([string]$i.calendarId) -Body $body }
            catch {
                $cls = Get-GCalSafeErrorClass -ErrorRecord $_
                if ($cls -eq 'already-exists') {
                    # deterministic id already present (a prior attempt landed) -> read it back
                    try { $ev = Invoke-GCalGet -Token $tok.token -CalendarId ([string]$i.calendarId) -EventId ([string]$i.clientEventId) } catch { $ev = $null }
                } else {
                    Write-GCalDiag -Level 'error' -Message ("insert failed: {0}" -f $cls)
                    return [pscustomobject]@{ ok = $false; message = ("Calendar insert failed ({0})." -f $cls) }
                }
            }
            if (-not $ev -or -not $ev.id) { return [pscustomobject]@{ ok = $false; message = 'Calendar insert returned no event id.' } }
            Write-GCalDiag -Message ("event created ({0})." -f $i.safeCalendarRef)
            return [pscustomobject]@{ ok = $true; destination = [string]$i.safeCalendarRef; newId = [string]$ev.id; message = ('Calendar event created (' + [string]$i.safeCalendarRef + ').') }
        }
        if ($action -eq 'update') {
            # read the current event: for the stale-version guard, no-op detection,
            # and to fail cleanly if it is gone.
            $cur = $null
            try { $cur = Invoke-GCalGet -Token $tok.token -CalendarId ([string]$i.calendarId) -EventId ([string]$i.eventId) }
            catch { $cls = Get-GCalSafeErrorClass -ErrorRecord $_; return [pscustomobject]@{ ok = $false; message = ("Calendar event not found for update ({0})." -f $cls) } }
            if (-not $cur -or -not $cur.id) { return [pscustomobject]@{ ok = $false; message = 'Calendar event not found for update.' } }
            # stale-version protection: refuse to overwrite a newer external change.
            if (-not [string]::IsNullOrWhiteSpace([string]$i.expectedProviderVersion)) {
                $curVer = Get-GCalEventVersion -Ev $cur
                if ($curVer -ne [string]$i.expectedProviderVersion) { return [pscustomobject]@{ ok = $false; message = 'Calendar event changed since approval (stale); it was not overwritten.' } }
            }
            if (Test-GCalNoOpUpdate -Current $cur -Changes $i.changes) { return [pscustomobject]@{ ok = $false; message = 'No-op update: nothing would change.' } }
            $body = New-GCalPatchBody -Changes $i.changes
            $ev = Invoke-GCalPatch -Token $tok.token -CalendarId ([string]$i.calendarId) -EventId ([string]$i.eventId) -Body $body
            if (-not $ev -or -not $ev.id) { return [pscustomobject]@{ ok = $false; message = 'Calendar patch returned no event.' } }
            Write-GCalDiag -Message ("event updated ({0})." -f $i.safeCalendarRef)
            return [pscustomobject]@{ ok = $true; destination = [string]$i.safeCalendarRef; newId = [string]$i.eventId; message = ('Calendar event updated (' + [string]$i.safeCalendarRef + ').') }
        }
        if ($action -eq 'cancel') {
            try { [void](Invoke-GCalDelete -Token $tok.token -CalendarId ([string]$i.calendarId) -EventId ([string]$i.eventId)) }
            catch {
                $cls = Get-GCalSafeErrorClass -ErrorRecord $_
                if ($cls -ne 'not-found' -and $cls -ne 'gone') { return [pscustomobject]@{ ok = $false; message = ("Calendar cancel failed ({0})." -f $cls) } }
                # already gone -> idempotent success
            }
            Write-GCalDiag -Message ("event cancelled ({0})." -f $i.safeCalendarRef)
            return [pscustomobject]@{ ok = $true; destination = [string]$i.safeCalendarRef; newId = [string]$i.eventId; message = ('Calendar event cancelled (' + [string]$i.safeCalendarRef + ').') }
        }
        return [pscustomobject]@{ ok = $false; message = ("unsupported calendar action: {0}" -f $action) }
    }
    catch {
        $cls = Get-GCalSafeErrorClass -ErrorRecord $_
        Write-GCalDiag -Level 'error' -Message ("execute error: {0}" -f $cls)
        return [pscustomobject]@{ ok = $false; message = ("Calendar request failed ({0})." -f $cls) }
    }
}

# ---- Verify: INDEPENDENT read-back by exact provider id ----------------------
# The engine's authoritative gate for 'connector' mode. Reads the event by its
# exact id and confirms the approved facts landed. For a create the id is the
# DETERMINISTIC client id in the intent, so this works even if the execute result
# was never persisted (crash-after-insert) - the anchor is in the intent, not the
# result. Never trusts the HTTP result alone.
function Test-GCalConnectorVerify {
    param($Intent, $Result)
    if (-not $Intent) { return $false }
    $tok = Get-GCalWriteAccessToken
    if (-not $tok.ok) { return $false }   # cannot verify -> fail closed
    $action = [string]$Intent.connectorAction
    try {
        if ($action -eq 'create') {
            $ev = $null
            try { $ev = Invoke-GCalGet -Token $tok.token -CalendarId ([string]$Intent.calendarId) -EventId ([string]$Intent.clientEventId) } catch { return $false }
            if (-not $ev -or -not $ev.id) { return $false }
            if ([string]$ev.id -ne [string]$Intent.clientEventId) { return $false }
            if (($ev.PSObject.Properties.Name -contains 'status') -and ([string]$ev.status -eq 'cancelled')) { return $false }
            # confirm the approved facts landed (start/end instants + title)
            $evStart = if ($ev.start -and ($ev.start.PSObject.Properties.Name -contains 'dateTime')) { [string]$ev.start.dateTime } else { '' }
            $evEnd   = if ($ev.end -and ($ev.end.PSObject.Properties.Name -contains 'dateTime')) { [string]$ev.end.dateTime } else { '' }
            if (-not (Test-GCalInstantsEqual -A $evStart -B ([string]$Intent.start))) { return $false }
            if (-not (Test-GCalInstantsEqual -A $evEnd -B ([string]$Intent.end))) { return $false }
            if (($ev.PSObject.Properties.Name -contains 'summary') -and ([string]$ev.summary -ne [string]$Intent.title)) { return $false }
            return $true
        }
        if ($action -eq 'update') {
            $ev = $null
            try { $ev = Invoke-GCalGet -Token $tok.token -CalendarId ([string]$Intent.calendarId) -EventId ([string]$Intent.eventId) } catch { return $false }
            if (-not $ev -or -not $ev.id) { return $false }
            if (($ev.PSObject.Properties.Name -contains 'status') -and ([string]$ev.status -eq 'cancelled')) { return $false }
            # every intended change must be reflected in the event now
            $ch = $Intent.changes
            foreach ($cn in @($ch.PSObject.Properties.Name)) {
                if ($cn -eq 'title') { if (([string]$ev.summary) -ne [string]$ch.title) { return $false } }
                elseif ($cn -eq 'start') { $es = if ($ev.start -and ($ev.start.PSObject.Properties.Name -contains 'dateTime')) { [string]$ev.start.dateTime } else { '' }; if (-not (Test-GCalInstantsEqual -A $es -B ([string]$ch.start))) { return $false } }
                elseif ($cn -eq 'end') { $ee = if ($ev.end -and ($ev.end.PSObject.Properties.Name -contains 'dateTime')) { [string]$ev.end.dateTime } else { '' }; if (-not (Test-GCalInstantsEqual -A $ee -B ([string]$ch.end))) { return $false } }
                elseif ($cn -eq 'description') { if (([string]$ev.description) -ne [string]$ch.description) { return $false } }
                elseif ($cn -eq 'location') { if (([string]$ev.location) -ne [string]$ch.location) { return $false } }
                # 'timezone' is proven by the start/end instants
            }
            return $true
        }
        if ($action -eq 'cancel') {
            $ev = $null
            try { $ev = Invoke-GCalGet -Token $tok.token -CalendarId ([string]$Intent.calendarId) -EventId ([string]$Intent.eventId) }
            catch { $cls = Get-GCalSafeErrorClass -ErrorRecord $_; if ($cls -eq 'not-found' -or $cls -eq 'gone') { return $true } return $false }
            if (-not $ev) { return $true }   # absent -> deleted
            if (($ev.PSObject.Properties.Name -contains 'status') -and ([string]$ev.status -eq 'cancelled')) { return $true }
            return $false
        }
        return $false
    }
    catch { return $false }
}

# The event's opaque version token for optimistic concurrency (stale-update
# protection): etag, else the updated timestamp, else the sequence number.
function Get-GCalEventVersion {
    param($Ev)
    if (($Ev.PSObject.Properties.Name -contains 'etag') -and $Ev.etag) { return [string]$Ev.etag }
    if (($Ev.PSObject.Properties.Name -contains 'updated') -and $Ev.updated) { return [string]$Ev.updated }
    if ($Ev.PSObject.Properties.Name -contains 'sequence') { return ('seq:' + [string]$Ev.sequence) }
    return ''
}
# A change set is a no-op if every intended field already equals the current value.
function Test-GCalNoOpUpdate {
    param($Current, $Changes)
    foreach ($cn in @($Changes.PSObject.Properties.Name)) {
        if ($cn -eq 'title') { if (([string]$Current.summary) -ne [string]$Changes.title) { return $false } }
        elseif ($cn -eq 'start') { $cs = if ($Current.start -and ($Current.start.PSObject.Properties.Name -contains 'dateTime')) { [string]$Current.start.dateTime } else { '' }; if (-not (Test-GCalInstantsEqual -A $cs -B ([string]$Changes.start))) { return $false } }
        elseif ($cn -eq 'end') { $ce = if ($Current.end -and ($Current.end.PSObject.Properties.Name -contains 'dateTime')) { [string]$Current.end.dateTime } else { '' }; if (-not (Test-GCalInstantsEqual -A $ce -B ([string]$Changes.end))) { return $false } }
        elseif ($cn -eq 'description') { if (([string]$Current.description) -ne [string]$Changes.description) { return $false } }
        elseif ($cn -eq 'location') { if (([string]$Current.location) -ne [string]$Changes.location) { return $false } }
        # 'timezone' alone does not constitute a change
    }
    return $true
}
# Build the Google patch body from the normalized change set.
function New-GCalPatchBody {
    param($Changes)
    $body = [pscustomobject]@{}
    $names = @($Changes.PSObject.Properties.Name)
    if ($names -contains 'title') { $body | Add-Member -NotePropertyName summary -NotePropertyValue ([string]$Changes.title) -Force }
    if (($names -contains 'start') -and ($names -contains 'end') -and ($names -contains 'timezone')) {
        $body | Add-Member -NotePropertyName start -NotePropertyValue ([pscustomobject]@{ dateTime = [string]$Changes.start; timeZone = [string]$Changes.timezone }) -Force
        $body | Add-Member -NotePropertyName end -NotePropertyValue ([pscustomobject]@{ dateTime = [string]$Changes.end; timeZone = [string]$Changes.timezone }) -Force
    }
    if ($names -contains 'description') { $body | Add-Member -NotePropertyName description -NotePropertyValue ([string]$Changes.description) -Force }
    if ($names -contains 'location') { $body | Add-Member -NotePropertyName location -NotePropertyValue ([string]$Changes.location) -Force }
    return $body
}

# Two RFC3339 instants are equal if they denote the same moment (offset-aware),
# so a provider echoing a different but equivalent offset still verifies.
function Test-GCalInstantsEqual {
    param([string]$A, [string]$B)
    if ([string]::IsNullOrWhiteSpace($A) -or [string]::IsNullOrWhiteSpace($B)) { return $false }
    $da = [DateTimeOffset]::MinValue; $db = [DateTimeOffset]::MinValue
    $st = [System.Globalization.DateTimeStyles]::RoundtripKind
    if (-not [DateTimeOffset]::TryParse($A, [System.Globalization.CultureInfo]::InvariantCulture, $st, [ref]$da)) { return $false }
    if (-not [DateTimeOffset]::TryParse($B, [System.Globalization.CultureInfo]::InvariantCulture, $st, [ref]$db)) { return $false }
    return ($da.UtcDateTime -eq $db.UtcDateTime)
}

# =====================================================================
# UI MODELS (pure) - Settings status + Executive Inbox approval summary
# ---------------------------------------------------------------------
# The UI stays thin: it renders these models. No WPF here. No token/secret ever
# appears in a model. The APPROVAL summary shows the real title/time to the user
# who is approving (that is what he is deciding on); only the AUDIT log redacts.
# =====================================================================

# Default writable calendar preference (gitignored, local). 'primary' unless set.
function Get-GCalWritePrefsPath { return (Join-Path $PSScriptRoot '..\..\..\calendar.write.prefs.json') }
function Get-GCalDefaultCalendar {
    $p = Get-GCalWritePrefsPath
    if (Test-Path $p) { try { $d = Get-Content $p -Raw -Encoding UTF8 | ConvertFrom-Json; if ($d -and $d.defaultCalendar) { return [string]$d.defaultCalendar } } catch { } }
    return 'primary'
}
function Set-GCalDefaultCalendar {
    param([Parameter(Mandatory)][string]$CalendarId)
    if (-not (Test-GCalCalendarId -CalendarId $CalendarId)) { return $false }
    ([pscustomobject]@{ defaultCalendar = $CalendarId } | ConvertTo-Json) | Set-Content -Path (Get-GCalWritePrefsPath) -Encoding UTF8
    return $true
}

# The Settings-card model. state is the truthful availability; label maps it to the
# calm UX strings. Never leaks a token or a raw OAuth error.
function Get-GCalWriteSettingsModel {
    $av = Get-GCalWriteAvailability
    $label = switch ([string]$av.state) {
        'connected'      { 'Connected' }
        'not-connected'  { 'Not connected' }
        'not-configured' { 'Not configured' }
        'needs-attention' { 'Authorization expired' }
        default          { 'Needs attention' }
    }
    return [pscustomobject]@{
        state = [string]$av.state; label = $label; detail = [string]$av.detail
        accounts = @($av.accounts); connected = [bool]$av.ok
        defaultCalendar = (Get-GCalDefaultCalendar); scope = $script:GCalWriteScope
    }
}

# A friendly "when" line from two RFC3339 instants (with explicit offset).
function Format-GCalWhen {
    param([string]$Start, [string]$End)
    $ds = [DateTimeOffset]::MinValue; $de = [DateTimeOffset]::MinValue
    $st = [System.Globalization.DateTimeStyles]::RoundtripKind; $ci = [System.Globalization.CultureInfo]::InvariantCulture
    if (-not [DateTimeOffset]::TryParse($Start, $ci, $st, [ref]$ds)) { return ([string]$Start + ' - ' + [string]$End) }
    if (-not [DateTimeOffset]::TryParse($End, $ci, $st, [ref]$de)) { return ([string]$Start + ' - ' + [string]$End) }
    $sameDay = ($ds.Date -eq $de.Date)
    $offset = $ds.ToString('zzz')
    if ($sameDay) { return ('{0}, {1} - {2} (UTC{3})' -f $ds.ToString('ddd MMM d, yyyy'), $ds.ToString('h:mm tt'), $de.ToString('h:mm tt'), $offset) }
    return ('{0} {1} - {2} {3} (UTC{4})' -f $ds.ToString('ddd MMM d'), $ds.ToString('h:mm tt'), $de.ToString('ddd MMM d'), $de.ToString('h:mm tt'), $offset)
}

# The Executive Inbox approval summary: what Jake is approving, in plain rows. He
# is deciding on this action, so it shows the real title/calendar/time (not the
# redacted audit form). V1 never notifies anyone. Returns an ORDERED array of
# { label; value } rows; an invalid payload surfaces a 'Problem' row.
function Get-GCalApprovalSummary {
    param([Parameter(Mandatory)] $Proposal)
    $rows = @()
    $type = [string]$Proposal.type
    if (-not (Test-GCalActionType -Type $type)) { return $rows }
    $actionLabel = switch ($type) {
        'calendar.create-event'        { 'Create calendar event' }
        'calendar.create-focus-block'  { 'Create focus block' }
        'calendar.create-follow-up-block' { 'Create follow-up block' }
        'calendar.protect-family-time' { 'Protect family time' }
        'calendar.update-event'        { 'Update calendar event' }
        'calendar.cancel-event'        { 'Cancel calendar event' }
        default                        { $type }
    }
    $rows += [pscustomobject]@{ label = 'Action'; value = $actionLabel }
    if (-not ($Proposal.PSObject.Properties.Name -contains 'payload') -or -not $Proposal.payload) { $rows += [pscustomobject]@{ label = 'Problem'; value = 'missing calendar details' }; return $rows }
    $v = Test-GCalPayload -ActionType $type -Payload $Proposal.payload
    if (-not $v.valid) { $rows += [pscustomobject]@{ label = 'Problem'; value = [string]$v.reason }; return $rows }
    $p = $v.payload
    $rows += [pscustomobject]@{ label = 'Calendar'; value = [string]$p.calendarId }
    if ($p.action -eq 'create') {
        $rows += [pscustomobject]@{ label = 'Title'; value = [string]$p.title }
        $rows += [pscustomobject]@{ label = 'When'; value = (Format-GCalWhen -Start $p.start -End $p.end) }
        $rows += [pscustomobject]@{ label = 'Time zone'; value = [string]$p.timezone }
        if (-not [string]::IsNullOrWhiteSpace([string]$p.location)) { $rows += [pscustomobject]@{ label = 'Location'; value = [string]$p.location } }
    }
    elseif ($p.action -eq 'update') {
        $rows += [pscustomobject]@{ label = 'Event'; value = [string]$p.eventId }
        $desc = @()
        foreach ($cn in @($p.changes.PSObject.Properties.Name)) {
            if ($cn -eq 'title') { $desc += ('title -> "' + [string]$p.changes.title + '"') }
            elseif ($cn -eq 'start') { $desc += ('new time ' + (Format-GCalWhen -Start $p.changes.start -End $p.changes.end)) }
            elseif ($cn -eq 'end' -or $cn -eq 'timezone') { }
            elseif ($cn -eq 'location') { $desc += ('location -> "' + [string]$p.changes.location + '"') }
            elseif ($cn -eq 'description') { $desc += 'description updated' }
        }
        $rows += [pscustomobject]@{ label = 'Changes'; value = ($desc -join '; ') }
    }
    elseif ($p.action -eq 'cancel') {
        $rows += [pscustomobject]@{ label = 'Event'; value = [string]$p.eventId }
    }
    $rows += [pscustomobject]@{ label = 'Notifies'; value = 'No one (V1 sends no invitations)' }
    return $rows
}

# ---- registration: plug the connector into the ONE execution path ------------
# Registers ALL six V1 action types (create x4, update, cancel) on the ONE
# execution path. The engine learns no Google specifics - only the three seams.
function Register-GCalConnector {
    if (-not (Get-Command Register-ActionConnector -ErrorAction SilentlyContinue)) { return $false }
    Register-ActionConnector -Types $script:GCalActionTypes `
        -BuildIntent { param($Proposal) New-GCalIntent -Proposal $Proposal } `
        -Execute     { param($Request) Invoke-GCalConnectorExecute -Request $Request } `
        -Verify      { param($Intent, $Result) Test-GCalConnectorVerify -Intent $Intent -Result $Result }
    return $true
}
