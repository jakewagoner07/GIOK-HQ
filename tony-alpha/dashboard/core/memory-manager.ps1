# =====================================================================
# memory-manager.ps1  —  Tony's permanent memory, with permission
# ---------------------------------------------------------------------
# The user owns their data. The user owns their memories. Tony earns
# trust by ASKING - never by assuming. Tony never creates a permanent
# memory without the user's explicit permission.
#
# This module is the ONLY write path for permanent memory. Nothing else
# writes it. Detection surfaces CANDIDATES and a permission prompt; a
# memory is created only when the user approves (Approve-Memory). The
# user can edit, delete, disable, and export at any time. The Executive
# Context Engine READS approved memories; it never writes them.
#
# Source of truth: tony_memory.json (local, gitignored - private). No
# cloud, no duplicate storage, no hidden memories, no automatic writes.
# =====================================================================

$ErrorActionPreference = 'Stop'

# The memory categories (Sprint D12).
function Get-MemoryCategories {
    return @('Identity', 'Goals', 'Preferences', 'Work Style', 'Communication Style', 'Business', 'Health', 'Family', 'Learning', 'Relationships', 'Projects')
}

function Get-MemoryPath { return (Join-Path $PSScriptRoot '..\..\tony_memory.json') }

# Normalized signature of a memory value - used to dedupe and to honor
# "never ask again" without storing the raw text twice.
function New-MemorySignature {
    param([string]$Value)
    $s = ([string]$Value).ToLower() -replace '[^a-z0-9 ]', ' ' -replace '\s+', ' '
    return $s.Trim().Substring(0, [math]::Min(80, $s.Trim().Length))
}

# Read the store, normalizing to the permission schema. Tolerant of the
# older framework file (which had a 'categories' object) - it simply
# starts with an empty memory list.
function Get-MemoryStore {
    $p = Get-MemoryPath
    $data = $null
    if (Test-Path $p) { try { $data = Get-Content -Path $p -Raw -Encoding UTF8 | ConvertFrom-Json } catch { } }
    $memories = @(); $neverAsk = @()
    if ($data) {
        if ($data.PSObject.Properties.Name -contains 'memories' -and $data.memories) { $memories = @($data.memories) }
        if ($data.PSObject.Properties.Name -contains 'neverAsk' -and $data.neverAsk) { $neverAsk = @($data.neverAsk) }
    }
    return [pscustomobject]@{
        meta     = [pscustomobject]@{ version = '1.0.0'; note = 'Permission-based memory. Tony never writes here without explicit approval.'; updated = $(if ($data -and $data.meta) { $data.meta.updated } else { $null }) }
        memories = @($memories)
        neverAsk = @($neverAsk)
    }
}

# THE single writer. Every mutation routes through here.
function Save-MemoryStore {
    param([Parameter(Mandatory)] $Store)
    $Store.meta.updated = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    ($Store | ConvertTo-Json -Depth 8) | Set-Content -Path (Get-MemoryPath) -Encoding UTF8
}

function Get-NextMemoryId {
    param($Store)
    $max = 0
    foreach ($m in @($Store.memories)) { if ($m.id -match '^MEM-(\d+)$') { $n = [int]$Matches[1]; if ($n -gt $max) { $max = $n } } }
    return ('MEM-{0:000}' -f ($max + 1))
}

# ---- reads --------------------------------------------------------
function Get-Memories {
    param([switch]$IncludeDisabled)
    $all = @((Get-MemoryStore).memories)
    if ($IncludeDisabled) { return $all }
    return @($all | Where-Object { $_.status -eq 'active' })
}
function Get-MemoryById { param([string]$Id) return @((Get-MemoryStore).memories | Where-Object { $_.id -eq $Id }) | Select-Object -First 1 }
function Test-MemoryKnown { param([string]$Value) $sig = New-MemorySignature $Value; return [bool](@((Get-MemoryStore).memories | Where-Object { $_.signature -eq $sig }).Count -gt 0) }
function Test-MemoryNeverAsk { param([string]$Value) $sig = New-MemorySignature $Value; return [bool](@((Get-MemoryStore).neverAsk | Where-Object { $_.signature -eq $sig }).Count -gt 0) }

# Active memories as compact "Category: value" lines - what the Executive
# Context Engine reads. Reference only; never a second copy.
function Get-MemoryContextLines {
    param([int]$Max = 12)
    return @(Get-Memories | Select-Object -First $Max | ForEach-Object { "{0}: {1}" -f $_.category, $_.value })
}

# ---- WRITE PATH (permission-gated) --------------------------------
# The ONLY way a permanent memory is created. Calling this IS the user's
# approval - the UI calls it only after the user chooses "Remember".
# -Id (Epic 16A): optional caller-supplied STABLE id. Omitted -> unchanged sequential
# MEM-NNN. Supplied -> the EXACT id after two gates: well-formed MEM- id and not a
# duplicate. Owner stays the only writer.
function Approve-Memory {
    param(
        [Parameter(Mandatory)][string]$Category,
        [Parameter(Mandatory)][string]$Value,
        [string]$Why = '',
        [string]$Source = 'conversation',
        [string]$Id = ''
    )
    if ([string]::IsNullOrWhiteSpace($Value)) { return $null }
    $cat = if ($Category -in (Get-MemoryCategories)) { $Category } else { 'Preferences' }
    $store = Get-MemoryStore
    $useId = ''
    if ($Id) {
        if ($Id -notmatch '^MEM-[A-Za-z0-9]+$') { return $null }                                       # invalid id -> reject
        if (@($store.memories | Where-Object { [string]$_.id -eq $Id }).Count -gt 0) { return $null }  # duplicate id -> reject
        $useId = $Id
    }
    else { $useId = Get-NextMemoryId -Store $store }
    $mem = [pscustomobject]@{
        id         = $useId
        category   = $cat
        value      = $Value.Trim()
        why        = $Why.Trim()
        source     = $Source
        signature  = (New-MemorySignature $Value)
        created    = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
        approvedAt = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
        status     = 'active'
    }
    $store.memories = @($store.memories) + $mem
    Save-MemoryStore -Store $store
    return $mem
}

function Update-Memory {
    param([Parameter(Mandatory)][string]$Id, [string]$Value, [string]$Category, [string]$Why)
    $store = Get-MemoryStore
    $found = $null
    foreach ($m in @($store.memories)) {
        if ($m.id -eq $Id) {
            if ($PSBoundParameters.ContainsKey('Value') -and $Value) { $m.value = $Value.Trim(); $m.signature = (New-MemorySignature $Value) }
            if ($PSBoundParameters.ContainsKey('Category') -and $Category -and $Category -in (Get-MemoryCategories)) { $m.category = $Category }
            if ($PSBoundParameters.ContainsKey('Why')) { $m.why = ([string]$Why).Trim() }
            $found = $m
        }
    }
    if ($found) { Save-MemoryStore -Store $store }
    return $found
}

function Remove-Memory {
    param([Parameter(Mandatory)][string]$Id)
    $store = Get-MemoryStore
    $before = @($store.memories).Count
    $store.memories = @(@($store.memories) | Where-Object { $_.id -ne $Id })
    if (@($store.memories).Count -ne $before) { Save-MemoryStore -Store $store; return $true }
    return $false
}

function Set-MemoryStatus {
    param([Parameter(Mandatory)][string]$Id, [Parameter(Mandatory)][ValidateSet('active', 'disabled')][string]$Status)
    $store = Get-MemoryStore; $found = $null
    foreach ($m in @($store.memories)) { if ($m.id -eq $Id) { $m.status = $Status; $found = $m } }
    if ($found) { Save-MemoryStore -Store $store }
    return $found
}

# "Never ask again" for a specific candidate - recorded so detection stays
# silent about it. Never stores it as a memory.
function Set-MemoryNeverAsk {
    param([Parameter(Mandatory)][string]$Value, [string]$Category = '')
    $store = Get-MemoryStore
    $sig = New-MemorySignature $Value
    if (@($store.neverAsk | Where-Object { $_.signature -eq $sig }).Count -eq 0) {
        $store.neverAsk = @($store.neverAsk) + [pscustomobject]@{ signature = $sig; category = $Category; when = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss') }
        Save-MemoryStore -Store $store
    }
    return $true
}

# Export - the user owns their data. Writes a plain JSON copy they keep.
function Export-Memories {
    param([string]$Path)
    if (-not $Path) { $Path = Join-Path (Split-Path (Get-MemoryPath) -Parent) ('memory-export-' + (Get-Date).ToString('yyyyMMdd-HHmmss') + '.json') }
    $store = Get-MemoryStore
    $payload = [pscustomobject]@{ exportedAt = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'); memories = @($store.memories) }
    ($payload | ConvertTo-Json -Depth 8) | Set-Content -Path $Path -Encoding UTF8
    return $Path
}

# ---- DETECTION (surfaces candidates; NEVER saves) -----------------
# Scans a user message for information that could improve future
# recommendations. Returns candidates only - Tony must ask before any of
# them becomes a memory.
function Find-MemoryCandidates {
    param([string]$Text)
    $t = ([string]$Text).Trim()
    if ($t.Length -lt 6) { return @() }
    $cands = @()
    $add = {
        param($cat, $val, $why)
        $v = ([string]$val).Trim().TrimEnd('.', '!', '?')
        if ($v.Length -ge 3 -and $v.Length -le 200) { $script:__c += , ([pscustomobject]@{ category = $cat; value = $v; why = $why; signature = (New-MemorySignature $v) }) }
    }
    $script:__c = @()

    # explicit ask - highest confidence
    if ($t -match '(?i)\bremember(?: that| this)?[:,]?\s+(.+)$') { & $add (Get-BestMemoryCategory $Matches[1]) $Matches[1] 'You asked me to remember this.' }
    # preferences
    elseif ($t -match "(?i)\bi (?:really )?(?:prefer|like|love|enjoy|favou?r) (.+)$") { & $add 'Preferences' $Matches[1] 'Knowing your preferences lets me tailor recommendations to what you actually like.' }
    elseif ($t -match "(?i)\bi (?:don't like|dont like|hate|can't stand|cannot stand|avoid) (.+)$") { & $add 'Preferences' ('dislikes ' + $Matches[1]) 'Knowing what you would rather avoid keeps my suggestions on target.' }
    # work style
    elseif ($t -match '(?i)\bi (?:usually|always|tend to|work best|focus best|like to work) (.+)$') { & $add 'Work Style' $Matches[1] 'Understanding how you work best helps me plan your day around it.' }
    # goals
    elseif ($t -match '(?i)\bmy (?:goal|aim|target) is (?:to )?(.+)$') { & $add 'Goals' $Matches[1] 'Keeping your goal in view helps me connect daily work to what matters.' }
    elseif ($t -match '(?i)\bi (?:want|plan|intend) to (.+)$') { & $add 'Goals' ('wants to ' + $Matches[1]) 'Knowing what you are aiming at helps me keep it alive over time.' }
    # family
    elseif ($t -match '(?i)\bmy (wife|husband|son|daughter|kid|kids|child|children|partner|mom|dad|mother|father|family) (.+)$') { & $add 'Family' ($Matches[1] + ' ' + $Matches[2]) 'Remembering what matters to your family helps me keep it first.' }
    # health
    elseif ($t -match "(?i)\bi(?:'m| am) allergic to (.+)$") { & $add 'Health' ('allergic to ' + $Matches[1]) 'Health facts are worth getting right.' }
    # learning
    elseif ($t -match '(?i)\bi(?:''m| am)? ?(?:learning|studying) (.+)$') { & $add 'Learning' ('learning ' + $Matches[1]) 'Knowing what you are learning lets me support it.' }

    $out = @($script:__c); $script:__c = $null
    return @($out | Select-Object -First 1)   # one at a time - never overwhelm
}

# Best-guess category for an explicit "remember that ..." value.
function Get-BestMemoryCategory {
    param([string]$Text)
    $l = ([string]$Text).ToLower()
    if ($l -match 'goal|aim to|want to|by end of') { return 'Goals' }
    if ($l -match 'wife|husband|son|daughter|kid|child|family|anniversary|birthday') { return 'Family' }
    if ($l -match 'prefer|like|hate|favou?r|rather') { return 'Preferences' }
    if ($l -match 'client|agency|policy|renewal|premium|commission|business') { return 'Business' }
    if ($l -match 'gym|workout|sleep|health|diet|protein|allerg') { return 'Health' }
    if ($l -match 'learn|study|course|book|read') { return 'Learning' }
    if ($l -match 'project|building|launch|rollout') { return 'Projects' }
    if ($l -match 'call|email|text|meeting|morning|evening|schedule|work best') { return 'Work Style' }
    return 'Preferences'
}

# Should Tony ask about this candidate? Not if it's already remembered or
# on the "never ask again" list.
function Test-MemoryShouldAsk {
    param($Candidate)
    if (-not $Candidate) { return $false }
    if (Test-MemoryKnown -Value $Candidate.value) { return $false }
    if (Test-MemoryNeverAsk -Value $Candidate.value) { return $false }
    return $true
}

# The permission prompt + the four choices. Data only - the UI presents it.
# Tony ASKS; he does not save.
function New-MemoryPermissionPrompt {
    param($Candidate)
    return [pscustomobject]@{
        question = "This seems like something that could help me make better recommendations in the future. Would you like me to remember it?"
        category = $Candidate.category
        value    = $Candidate.value
        why      = $Candidate.why
        choices  = @('Remember', 'Edit', 'Not Now', 'Never Ask Again')
    }
}
