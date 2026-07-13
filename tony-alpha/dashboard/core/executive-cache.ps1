# =====================================================================
# executive-cache.ps1  -  Bounded in-memory signal cache (Epic 9)
# ---------------------------------------------------------------------
# Measurement (Blueprint/Performance_Responsiveness.md) proved the entire
# cost of Home, the Inbox scan, and Tony prep is LIVE PROVIDER LATENCY -
# Yahoo IMAP ~20s, Gmail ~10s, Calendar ~5s - fetched independently by
# more than one action. This cache stores ONLY the read-only results that
# providers return, so the 2nd..Nth action inside a short window is instant.
#
# It is NOT a database, NOT persisted, and NOT a source of truth. Providers
# and the Executive Context remain the sole owners and the only code that
# actually reads a source. We deliberately cache ONLY external provider
# signals (calendar / communications / CRM) - never local-domain data
# (Life OS, Goals, Memory). The Executive Context is rebuilt each time from
# cached signals (cheap ~0.7s) so it always reflects current local data:
# that keeps Single Source of Truth and needs no invalidate-on-write here.
#
# Guarantees: per-entry fetchedAt + TTL; returns the last good value marked
# STALE past TTL or on a failed refresh (calm degraded state); single-flight
# (one refresh per key at a time); bounded (LRU-ish cap). Thread note: the
# store is a hashtable guarded by a sync root so a background runspace can
# publish a result while the UI thread reads.
# =====================================================================

$ErrorActionPreference = 'Stop'

$script:GiokCache = @{}
$script:GiokCacheLock = New-Object object
$script:GiokCacheCap = 64

# Default TTLs (seconds). Justified by the baseline; revisit against re-measured numbers.
$script:GiokCacheTtl = @{
    'calendar'       = 120   # 2 min
    'communications' = 120   # 2 min (Gmail + Yahoo)
    'crm'            = 300   # 5 min
}
function Get-CacheTtl { param([string]$Key) if ($script:GiokCacheTtl.ContainsKey($Key)) { return [int]$script:GiokCacheTtl[$Key] } return 120 }

function Clear-ExecutiveCache { param([string]$Key) if ($Key) { [void]$script:GiokCache.Remove($Key) } else { $script:GiokCache = @{} } }

function Get-ExecutiveCacheStats {
    $now = Get-Date
    @($script:GiokCache.GetEnumerator() | ForEach-Object {
        $e = $_.Value
        [pscustomobject]@{ key = $_.Key; ageSec = [int](($now - $e.fetchedAt).TotalSeconds); ttlSec = $e.ttlSec; refreshing = [bool]$e.refreshing; hasValue = ($null -ne $e.value); lastError = [string]$e.lastError }
    })
}

function Test-CacheFresh {
    param([string]$Key, [datetime]$Now = (Get-Date))
    $e = $script:GiokCache[$Key]
    if (-not $e -or $null -eq $e.value) { return $false }
    if ([int]$e.ttlSec -le 0) { return $true }
    return ((($Now - $e.fetchedAt).TotalSeconds) -lt [int]$e.ttlSec)
}

# Publish a freshly fetched value (called by the sync path and by background workers).
function Set-CachedSignal {
    param([Parameter(Mandatory)][string]$Key, $Value, [int]$TtlSec = -1)
    if ($TtlSec -lt 0) { $TtlSec = Get-CacheTtl $Key }
    [System.Threading.Monitor]::Enter($script:GiokCacheLock)
    try {
        $script:GiokCache[$Key] = @{ value = $Value; fetchedAt = (Get-Date); ttlSec = $TtlSec; refreshing = $false; lastError = $null }
        # bounded: evict oldest if over cap
        if ($script:GiokCache.Count -gt $script:GiokCacheCap) {
            $oldest = $script:GiokCache.GetEnumerator() | Sort-Object { $_.Value.fetchedAt } | Select-Object -First 1
            if ($oldest) { [void]$script:GiokCache.Remove($oldest.Key) }
        }
    } finally { [System.Threading.Monitor]::Exit($script:GiokCacheLock) }
}

# Mark a key as being refreshed (single-flight gate). Returns $true if THIS caller
# claimed the refresh, $false if another refresh is already in flight.
function Enter-CacheRefresh {
    param([Parameter(Mandatory)][string]$Key)
    [System.Threading.Monitor]::Enter($script:GiokCacheLock)
    try {
        $e = $script:GiokCache[$Key]
        if ($e -and $e.refreshing) { return $false }
        if (-not $e) { $e = @{ value = $null; fetchedAt = [datetime]::MinValue; ttlSec = (Get-CacheTtl $Key); refreshing = $false; lastError = $null }; $script:GiokCache[$Key] = $e }
        $e.refreshing = $true
        return $true
    } finally { [System.Threading.Monitor]::Exit($script:GiokCacheLock) }
}
function Exit-CacheRefresh {
    param([Parameter(Mandatory)][string]$Key, [string]$Error = $null)
    [System.Threading.Monitor]::Enter($script:GiokCacheLock)
    try { $e = $script:GiokCache[$Key]; if ($e) { $e.refreshing = $false; if ($Error) { $e.lastError = $Error } } }
    finally { [System.Threading.Monitor]::Exit($script:GiokCacheLock) }
}

# Peek the cached value (may be stale). Returns { value; stale; present; refreshing }.
function Peek-CachedSignal {
    param([Parameter(Mandatory)][string]$Key, [datetime]$Now = (Get-Date))
    $e = $script:GiokCache[$Key]
    if (-not $e -or $null -eq $e.value) { return [pscustomobject]@{ value = $null; stale = $true; present = $false; refreshing = [bool]($e -and $e.refreshing) } }
    [pscustomobject]@{ value = $e.value; stale = (-not (Test-CacheFresh -Key $Key -Now $Now)); present = $true; refreshing = [bool]$e.refreshing }
}

# Synchronous fetch-through: return the fresh cached value, else run $Fetch,
# cache and return it. On a fetch failure return the last good value marked
# stale (never throws to the caller). Single-flight avoids a duplicate fetch.
function Get-CachedSignal {
    param(
        [Parameter(Mandatory)][string]$Key,
        [Parameter(Mandatory)][scriptblock]$Fetch,
        [int]$TtlSec = -1,
        [datetime]$Now = (Get-Date)
    )
    if (Test-CacheFresh -Key $Key -Now $Now) {
        return [pscustomobject]@{ value = $script:GiokCache[$Key].value; stale = $false; fromCache = $true }
    }
    $claimed = Enter-CacheRefresh -Key $Key
    if (-not $claimed) {
        # another refresh in flight - hand back last good, marked stale
        $p = Peek-CachedSignal -Key $Key -Now $Now
        return [pscustomobject]@{ value = $p.value; stale = $true; fromCache = $true }
    }
    try {
        $val = & $Fetch
        Set-CachedSignal -Key $Key -Value $val -TtlSec $TtlSec
        return [pscustomobject]@{ value = $val; stale = $false; fromCache = $false }
    }
    catch {
        Exit-CacheRefresh -Key $Key -Error $_.Exception.GetType().Name
        $p = Peek-CachedSignal -Key $Key -Now $Now
        return [pscustomobject]@{ value = $p.value; stale = $true; fromCache = ($null -ne $p.value); error = $_.Exception.GetType().Name }
    }
}

# ---- cached provider-signal wrappers -------------------------------------
# The ONE place every consumer (Home briefing, Workforce specialists, the Inbox
# scan, Tony pre-LLM prep) reads a live provider, so a source is fetched at most
# once per TTL window across the whole session. Each returns the provider's own
# raw signal object (or $null when not connected). Status checks are local/cheap.
# Providers stay pure for explicit-refresh paths (e.g. Settings "Test accounts").
function Get-CalendarSignal {
    param([datetime]$Now = (Get-Date))
    if (-not ((Get-Command Get-GCalStatus -ErrorAction SilentlyContinue) -and (Get-Command Get-Calendar -ErrorAction SilentlyContinue))) { return $null }
    try { if ((Get-GCalStatus).state -ne 'connected') { return $null } } catch { return $null }
    return (Get-CachedSignal -Key 'calendar' -Now $Now -Fetch { Get-Calendar -When 'today' -Now $Now }).value
}
function Get-CommunicationsSignal {
    param([datetime]$Now = (Get-Date))
    if (-not ((Get-Command Get-CommunicationsStatus -ErrorAction SilentlyContinue) -and (Get-Command Get-Communications -ErrorAction SilentlyContinue))) { return $null }
    try { if ((Get-CommunicationsStatus).state -ne 'connected') { return $null } } catch { return $null }
    return (Get-CachedSignal -Key 'communications' -Now $Now -Fetch { Get-Communications -Now $Now }).value
}
function Get-CrmSignal {
    param([datetime]$Now = (Get-Date))
    if (-not ((Get-Command Get-CRMStatus -ErrorAction SilentlyContinue) -and (Get-Command Get-CRM -ErrorAction SilentlyContinue))) { return $null }
    try { if ((Get-CRMStatus).state -notin @('configured', 'connected', 'degraded')) { return $null } } catch { return $null }
    return (Get-CachedSignal -Key 'crm' -Now $Now -Fetch { Get-CRM -Now $Now }).value
}

# Freshness of a signal for a calm "showing recent data" affordance in the UI.
function Get-SignalFreshness {
    param([string]$Key, [datetime]$Now = (Get-Date))
    $p = Peek-CachedSignal -Key $Key -Now $Now
    [pscustomobject]@{ present = $p.present; stale = $p.stale; refreshing = $p.refreshing }
}
