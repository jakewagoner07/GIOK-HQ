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
