# =====================================================================
# action-engine.ps1  -  The Executive Action Engine (Epic 15, hardened 15.1)
# ---------------------------------------------------------------------
# The SOLE execution authority for Tony. Nothing in GIOK writes an owner store
# as the RESULT OF AN ACTION except through this engine, and every execution
# originates from an APPROVED Executive Inbox proposal - never from a reasoning
# provider, never ambiently. Reasoning proposes; the human approves; the engine
# executes, verifies, and records.
#
# Every execution walks an explicit, persisted state machine:
#
#     pending -> validating -> executing -> verifying -> succeeded
#                    |             |            |     \-> failed
#                    +-------------+------------+--------> failed
#
# INTENT BEFORE SIDE EFFECT (Epic 15.1): before any owner write, the engine
# persists an immutable execution INTENT - the action type, the target id (or a
# PRE-ALLOCATED new id for create-style actions), and the exact facts that will
# prove the change landed. Recovery therefore ALWAYS has enough deterministic
# information to re-verify an interrupted execution: a crash after the owner
# write but before any later logging recovers to succeeded (the intended change
# exists) or failed (it does not) - never a blind re-run, never a double write.
#
# SUCCESS is never claimed until VERIFICATION confirms the owner store actually
# changed. The verification gate is the ENGINE'S OWN intent check; a handler's
# verify block can only add strictness, never grant success.
#
# Guarantees preserved from the rest of GIOK:
#   * approval-first        - only Approve-InboxItem drives an execution;
#   * single source of truth- approved data lives ONLY in its owner; the engine
#                             writes through the owner's own functions and keeps
#                             no second copy of business data (the log records
#                             executions, not the data);
#   * deterministic         - no AI, no network in this file; pure local dispatch;
#   * restart safety        - non-terminal executions are recovered by verifying
#                             the persisted intent;
#   * no direct writes      - reasoning providers still only propose.
# =====================================================================

$ErrorActionPreference = 'Stop'

$script:ActionEngineVersion = '1.1'

# The canonical execution states. 'succeeded'/'failed' are terminal.
$script:ExecStates      = @('pending', 'validating', 'executing', 'verifying', 'succeeded', 'failed')
$script:ExecTerminal    = @('succeeded', 'failed')
$script:ExecNonTerminal = @('pending', 'validating', 'executing', 'verifying')
function Get-ExecutionStates { return $script:ExecStates }

# ---- durable audit store (gitignored; executions, not business data) ---
# ARCHITECTURE (Epic 15.1): ATOMIC SNAPSHOT with last-known-good backup - the
# smallest safe change from the existing whole-file JSON store. Every save writes
# a temp file and atomically replaces the primary ([IO.File]::Replace), which
# also refreshes execution_log.json.bak as the last-known-good copy. A corrupt
# primary recovers from the backup and NEVER silently erases history; if BOTH are
# unreadable the store FAILS CLOSED: reads report empty, and every write path
# throws - so no execution can proceed unaudited. Writes are serialized by a
# named mutex. Retention is bounded: the newest terminal records are kept up to
# a cap; non-terminal records are NEVER pruned.
function Get-ExecutionLogPath { return (Join-Path $PSScriptRoot '..\..\execution_log.json') }
$script:ExecutionLogRetention = 500     # newest terminal records kept; non-terminal never pruned
$script:ExecLogMutex = $null
function Get-ExecLogMutex {
    if (-not $script:ExecLogMutex) { $script:ExecLogMutex = New-Object System.Threading.Mutex($false, 'Local\GiokExecutionLog') }
    return $script:ExecLogMutex
}
function Read-ExecutionLogFile {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return $null }
    $raw = $null
    try { $raw = Get-Content -Path $Path -Raw -Encoding UTF8 } catch { return $null }
    if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
    try {
        $d = $raw | ConvertFrom-Json
        if ($d -and ($d.PSObject.Properties.Name -contains 'executions')) { return $d }
        return $null
    }
    catch { return $null }
}
function New-EmptyExecutionLog { return [pscustomobject]@{ meta = [pscustomobject]@{ version = '1.1'; updated = '' }; executions = @() } }
# 'ok' | 'backup' (primary corrupt, recovered) | 'fresh' (no log yet) | 'failed'
# (primary present but unreadable AND no readable backup -> fail closed).
function Get-ExecutionLogState {
    $p = Get-ExecutionLogPath
    $hasPrimary = (Test-Path $p) -and -not [string]::IsNullOrWhiteSpace((Get-Content -Path $p -Raw -Encoding UTF8 -ErrorAction SilentlyContinue))
    if (Read-ExecutionLogFile -Path $p) { return 'ok' }
    if (Read-ExecutionLogFile -Path ($p + '.bak')) { return 'backup' }
    if ($hasPrimary) { return 'failed' }
    return 'fresh'
}
# Returns the log, or $NULL when the store is fail-closed (both copies unreadable).
# Write paths treat $null as a hard stop; read paths degrade to empty.
function Get-ExecutionLog {
    $p = Get-ExecutionLogPath
    $d = Read-ExecutionLogFile -Path $p
    if ($d) { return $d }
    $b = Read-ExecutionLogFile -Path ($p + '.bak')
    if ($b) { return $b }   # corrupt/missing primary, healthy backup: history preserved
    $state = Get-ExecutionLogState
    if ($state -eq 'failed') { return $null }
    $fresh = New-EmptyExecutionLog
    if (-not ($fresh.PSObject.Properties.Name -contains 'executions') -or $null -eq $fresh.executions) { $fresh | Add-Member -NotePropertyName executions -NotePropertyValue @() -Force }
    return $fresh
}
# Atomic, serialized, bounded save. THROWS on any failure (mutex timeout, disk,
# fail-closed store) - callers treat a failed save as a hard stop, which is what
# makes "no unaudited side effect" true.
function Save-ExecutionLog {
    param([Parameter(Mandatory)] $Data)
    $Data.meta.updated = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    # retention: never prune non-terminal; keep the NEWEST terminal up to the cap
    $all = @($Data.executions)
    if ($all.Count -gt $script:ExecutionLogRetention) {
        $nonTerminal = @($all | Where-Object { $script:ExecTerminal -notcontains [string]$_.state })
        $terminal = @($all | Where-Object { $script:ExecTerminal -contains [string]$_.state })
        $keepTerminal = [math]::Max(0, $script:ExecutionLogRetention - $nonTerminal.Count)
        if ($terminal.Count -gt $keepTerminal) { $terminal = @($terminal | Select-Object -Last $keepTerminal) }
        $Data.executions = @(@($nonTerminal) + @($terminal) | Sort-Object { [string]$_.id })
    }
    $mtx = Get-ExecLogMutex
    $got = $false
    try { $got = $mtx.WaitOne(3000) } catch [System.Threading.AbandonedMutexException] { $got = $true }
    if (-not $got) { throw 'execution log is locked; save refused (fail closed)' }
    try {
        $p = Get-ExecutionLogPath; $tmp = $p + '.tmp'; $bak = $p + '.bak'
        ($Data | ConvertTo-Json -Depth 12) | Set-Content -Path $tmp -Encoding UTF8
        if (Test-Path $p) { [System.IO.File]::Replace($tmp, $p, $bak) }
        else { Move-Item -Path $tmp -Destination $p -Force }
    }
    finally { try { $mtx.ReleaseMutex() } catch { } }
}
function Get-Executions {
    param([string]$State = 'all')
    $log = Get-ExecutionLog
    if (-not $log) { return @() }   # fail-closed store: reads degrade to empty; writes are blocked
    $all = @($log.executions)
    if ($State -eq 'all') { return $all }
    return @($all | Where-Object { $_.state -eq $State })
}
function Get-ExecutionById { param([string]$Id) return @(Get-Executions -State 'all' | Where-Object { $_.id -eq $Id })[0] }
function Get-NextExecutionId {
    param($Log)
    $max = 0
    foreach ($e in @($Log.executions)) { if ([string]$e.id -match '^EXE-(\d+)$') { $n = [int]$Matches[1]; if ($n -gt $max) { $max = $n } } }
    return ('EXE-{0:00000}' -f ($max + 1))
}

# ---- execution record + transitions ------------------------------------
# A record carries everything needed to VERIFY and AUDIT an execution without the
# original proposal (which is removed from the inbox on success). It is the audit
# entry and the restart-recovery unit. 'intent' is the immutable statement of what
# the execution is ABOUT TO do - persisted before any side effect.
function New-ExecutionRecord {
    param([Parameter(Mandatory)] $Proposal)
    $log = Get-ExecutionLog
    if (-not $log) { throw 'execution log unreadable; refusing to execute (fail closed)' }
    $id = Get-NextExecutionId -Log $log
    $now = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    $rec = [pscustomobject]@{
        id                  = $id
        proposalId          = [string]$Proposal.id
        type                = [string]$Proposal.type
        title               = [string]$Proposal.title
        description         = [string]$Proposal.description
        source              = [string]$Proposal.source
        sourceId            = [string]$Proposal.sourceId
        proposedDestination = [string]$Proposal.proposedDestination
        state               = 'pending'
        createdAt           = $now
        updatedAt           = $now
        attempts            = 0
        idempotencyKey      = (Get-ExecutionIdempotencyKey -Proposal $Proposal)
        approval            = $null   # { approvedBy; approvedAt; source; fingerprint } - grounded in the real approval event
        intent              = $null   # persisted BEFORE any side effect (15.1)
        result              = $null   # { ok; destination; newId; message }
        history             = @([pscustomobject]@{ state = 'pending'; at = $now; detail = 'execution created from approved proposal' })
    }
    $log.executions = @($log.executions) + $rec
    Save-ExecutionLog $log
    return $rec
}
# Persist the record's CURRENT content (intent/result) without a state change.
# Used to write the intent before executing and the result immediately after -
# the two persists that close the crash-recovery gap.
function Update-ExecutionRecord {
    param([Parameter(Mandatory)] $Record)
    $Record.updatedAt = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    $log = Get-ExecutionLog
    if (-not $log) { throw 'execution log unreadable; refusing to record (fail closed)' }
    $found = $false
    $log.executions = @(@($log.executions) | ForEach-Object { if ($_.id -eq $Record.id) { $found = $true; $Record } else { $_ } })
    if (-not $found) { $log.executions = @($log.executions) + $Record }
    Save-ExecutionLog $log
    return $Record
}
# ---- the transition table: the ONLY legal state moves (Epic 15.1) ------
# Skipping a stage or re-entering a terminal record is refused, so neither a bug
# nor a hostile handler can walk a record to 'succeeded' out of order, and a
# finished execution can never be rewritten.
$script:ExecTransitions = @{
    'pending'    = @('validating', 'failed')
    'validating' = @('executing', 'failed')
    'executing'  = @('verifying', 'failed')
    'verifying'  = @('succeeded', 'failed')
    'succeeded'  = @()
    'failed'     = @()
}
# Move a record to a new state, append an audit line, and persist. Returns the record.
# ENGINE-PRIVATE by contract: handlers receive a DTO (no 'state'/'history'), so any
# handler calling this throws; and the persisted copy is checked so a terminal
# record can never be transitioned again, even via a stale reference.
function Set-ExecutionState {
    param([Parameter(Mandatory)] $Record, [Parameter(Mandatory)][string]$State, [string]$Detail = '')
    if ($script:ExecStates -notcontains $State) { throw ("unknown execution state: {0}" -f $State) }
    if (-not ($Record.PSObject.Properties.Name -contains 'id') -or -not ($Record.PSObject.Properties.Name -contains 'state')) {
        throw 'not an execution record (state transitions are engine-private)'
    }
    $from = [string]$Record.state
    if (@($script:ExecTransitions[$from]) -notcontains $State) {
        throw ("illegal execution transition: {0} -> {1}" -f $from, $State)
    }
    # terminal lock against the PERSISTED copy: a finished record is immutable.
    $persisted = Get-ExecutionById -Id ([string]$Record.id)
    if ($persisted -and ($script:ExecTerminal -contains [string]$persisted.state)) {
        throw ("execution {0} is terminal ({1}); it cannot be transitioned" -f $Record.id, $persisted.state)
    }
    $now = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    $Record.state = $State
    $Record.updatedAt = $now
    $Record.history = @($Record.history) + [pscustomobject]@{ state = $State; at = $now; detail = [string]$Detail }
    # upsert into the log by id
    $log = Get-ExecutionLog
    if (-not $log) { throw 'execution log unreadable; refusing to transition (fail closed)' }
    $found = $false
    $log.executions = @(@($log.executions) | ForEach-Object { if ($_.id -eq $Record.id) { $found = $true; $Record } else { $_ } })
    if (-not $found) { $log.executions = @($log.executions) + $Record }
    Save-ExecutionLog $log
    return $Record
}

# ---- verification: did the owner store actually change? ----------------
# Maps a routing destination to its Life OS domain (for Get-LifeItemById / titles).
$script:ExecDestinationDomain = @{
    'Home Projects'   = 'projects'
    'Non-Negotiables' = 'nonNegotiables'
    'Family'          = 'family'
    'Health'          = 'health'
    'Financial'       = 'financial'
    'Agency'          = 'agency'
    'Learning'        = 'learning'
}
# Confirm an owner record with $NewId now exists at $Destination.
function Test-ExecutionApplied {
    param([string]$Destination, [string]$NewId)
    if ([string]::IsNullOrWhiteSpace($NewId)) { return $false }
    try {
        switch ($Destination) {
            'Action Items' {
                if (-not (Get-Command Get-ActionItemsData -ErrorAction SilentlyContinue)) { return $false }
                return [bool](@((Get-ActionItemsData).items) | Where-Object { [string]$_.id -eq $NewId })
            }
            'Goals' {
                if (-not (Get-Command Get-GoalsList -ErrorAction SilentlyContinue)) { return $false }
                return [bool](@(Get-GoalsList) | Where-Object { [string]$_.id -eq $NewId })
            }
            'Tony Memory' {
                if (-not (Get-Command Get-Memories -ErrorAction SilentlyContinue)) { return $false }
                return [bool](@(Get-Memories) | Where-Object { [string]$_.id -eq $NewId })
            }
            default {
                $dom = $script:ExecDestinationDomain[$Destination]
                if ($dom -and (Get-Command Get-LifeItemById -ErrorAction SilentlyContinue)) {
                    return [bool](Get-LifeItemById -Domain $dom -Id $NewId)
                }
                return $false
            }
        }
    }
    catch { return $false }
}
# Owner-minted creates (goals / life items / memory) - the owner assigns the id
# inside its own writer, so the engine cannot pre-allocate one. To verify a create
# by STABLE IDENTITY (never mere title existence), the engine reads the {id,title}
# records at a destination: it snapshots the matching-title ids BEFORE the write
# (into the intent) and, at verify time, requires either the exact minted id OR a
# matching-title id that did NOT exist before the intent. A pre-existing duplicate
# title can never satisfy recovery. (Epic 15.1 BLK-1 fix.)
function Get-DestinationRecords {
    param([string]$Destination)
    $recs = @()
    try {
        switch ($Destination) {
            'Goals' { if (Get-Command Get-GoalsList -ErrorAction SilentlyContinue) { $recs = @(Get-GoalsList | ForEach-Object { [pscustomobject]@{ id = [string]$_.id; title = [string]$_.title } }) } }
            'Tony Memory' { if (Get-Command Get-Memories -ErrorAction SilentlyContinue) { $recs = @(Get-Memories | ForEach-Object { [pscustomobject]@{ id = [string]$_.id; title = [string]$_.value } }) } }
            default {
                $dom = $script:ExecDestinationDomain[$Destination]
                if ($dom -and (Get-Command Get-LifeItems -ErrorAction SilentlyContinue)) { $recs = @(Get-LifeItems -Domain $dom | ForEach-Object { [pscustomobject]@{ id = [string]$_.id; title = [string]$_.title } }) }
            }
        }
    }
    catch { $recs = @() }
    return @($recs)
}
function ConvertTo-ExecNormalizedTitle {
    param([string]$Text)
    return (([string]$Text) -replace '\s+', ' ').Trim().TrimEnd('.', ',', '!', '?', ';', ':').ToLower()
}
# The ids of records at a destination whose normalized title matches $Title.
function Get-DestinationMatchingIds {
    param([string]$Destination, [string]$Title)
    $want = ConvertTo-ExecNormalizedTitle $Title
    if (-not $want) { return @() }
    return @(Get-DestinationRecords -Destination $Destination | Where-Object { (ConvertTo-ExecNormalizedTitle $_.title) -eq $want } | ForEach-Object { [string]$_.id })
}

# ---- the execution INTENT (Epic 15.1) ----------------------------------
# The immutable, persisted statement of what an execution will do and how success
# will be PROVEN. Built at validation time, persisted BEFORE any side effect.
# Modes:
#   'field'     - an existing Action Item ($targetId) gains $field = $expected
#   'create-id' - a NEW Action Item is created under the PRE-ALLOCATED id $newId
#   'title'     - an owner-minted record (goal/life/memory) verified by STABLE IDENTITY:
#                 the exact minted $result.newId, else a matching-title record whose id
#                 did NOT exist before the intent ($preIds snapshot). Never mere title
#                 membership - a pre-existing duplicate title cannot satisfy recovery.
#   'result'    - a registered custom handler; verified from its persisted result
#                 (documented limitation: a crash before the result persist
#                 recovers to failed/retriable - safe, never a double write)
$script:ExecFollowUpTypes = @('calendar', 'crm', 'communication', 'document')
# Action-specific validation (Epic 15.1). Runs BEFORE the intent is persisted and
# therefore before any owner write: a malformed payload fails validation, the
# proposal stays pending, and no store is touched.
$script:ExecAllowedPriorities = @('low', 'medium', 'high')
# The normalized proposal schema. Unknown fields REJECT (not silently ignored):
# a payload carrying properties the engine does not understand is not executed.
$script:ExecAllowedProposalFields = @('id', 'uid', 'discoveredBy', 'type', 'title', 'description',
    'proposedDestination', 'evidence', 'confidence', 'status', 'created', 'source', 'sourceId')
function Test-ExecTargetActionItem {
    param([string]$Id)
    if ([string]::IsNullOrWhiteSpace($Id)) { return $false }
    if (-not (Get-Command Get-ActionItemsData -ErrorAction SilentlyContinue)) { return $false }
    return (@((Get-ActionItemsData).items | Where-Object { [string]$_.id -eq $Id }).Count -gt 0)
}
function New-ExecutionIntent {
    param([Parameter(Mandatory)] $Proposal)
    $type = [string]$Proposal.type
    $title = [string]$Proposal.title
    $value = if ($Proposal.description) { [string]$Proposal.description } else { [string]$Proposal.proposedDestination }
    # unknown proposal fields reject
    foreach ($pn in $Proposal.PSObject.Properties.Name) {
        if ($script:ExecAllowedProposalFields -notcontains $pn) {
            return [pscustomobject]@{ valid = $false; reason = ("unsupported proposal field: {0}" -f $pn); intent = $null }
        }
    }
    $mk = { param($h) [pscustomobject]@{ valid = $true; reason = ''; intent = [pscustomobject]$h } }
    # Owner-minted creates (Epic 16A): every one is now a create-id intent with a
    # deterministic PRE-ALLOCATED id in the owner's format, so verification is by exact
    # identity - title-mode is retired for production creates.
    $ownerDest = @{ 'goal' = 'Goals'; 'project' = 'Home Projects'; 'non-negotiable' = 'Non-Negotiables'; 'family' = 'Family'; 'health' = 'Health'; 'financial' = 'Financial'; 'agency' = 'Agency'; 'learning' = 'Learning'; 'memory' = 'Tony Memory' }
    switch ($type) {
        'reminder' {
            # a valid, unambiguous timestamp with EXPLICIT timezone semantics: the
            # intent stores ISO-8601 with the local UTC offset, so "when" survives
            # restarts, DST edges, and future connector round-trips unambiguously.
            $dt = [datetime]::MinValue
            if (-not [datetime]::TryParse($value, [ref]$dt)) { return [pscustomobject]@{ valid = $false; reason = ("invalid reminder timestamp: '{0}'" -f $value); intent = $null } }
            $when = $dt.ToString('yyyy-MM-ddTHH:mm:sszzz')
            $newId = if (Get-Command Get-NextActionId -ErrorAction SilentlyContinue) { Get-NextActionId -Data (Get-ActionItemsData) } else { $null }
            if (-not $newId) { return [pscustomobject]@{ valid = $false; reason = 'Action Items owner unavailable'; intent = $null } }
            return (& $mk @{ mode = 'field'; destination = 'Action Items'; targetId = $newId; newId = $newId; field = 'remindAt'; expected = $when; title = $title; create = $true })
        }
        'set-priority' {
            $pv = ([string]$value).Trim().ToLower()
            if ($script:ExecAllowedPriorities -notcontains $pv) { return [pscustomobject]@{ valid = $false; reason = ("invalid priority '{0}' (allowed: {1})" -f $value, ($script:ExecAllowedPriorities -join ', ')); intent = $null } }
            if (-not (Test-ExecTargetActionItem -Id ([string]$Proposal.sourceId))) { return [pscustomobject]@{ valid = $false; reason = 'target action item not found'; intent = $null } }
            return (& $mk @{ mode = 'field'; destination = 'Action Items'; targetId = [string]$Proposal.sourceId; newId = ''; field = 'priority'; expected = $pv; title = $title; create = $false })
        }
        'defer' {
            $dt = [datetime]::MinValue
            if (-not [datetime]::TryParse($value, [ref]$dt)) { return [pscustomobject]@{ valid = $false; reason = ("invalid defer date: '{0}'" -f $value); intent = $null } }
            if ($dt.Date -lt (Get-Date).Date) { return [pscustomobject]@{ valid = $false; reason = ("defer date is in the past: '{0}'" -f $value); intent = $null } }
            if (-not (Test-ExecTargetActionItem -Id ([string]$Proposal.sourceId))) { return [pscustomobject]@{ valid = $false; reason = 'target action item not found'; intent = $null } }
            return (& $mk @{ mode = 'field'; destination = 'Action Items'; targetId = [string]$Proposal.sourceId; newId = ''; field = 'deferredUntil'; expected = $dt.ToString('yyyy-MM-dd'); title = $title; create = $false })
        }
        'archive' {
            if (-not (Test-ExecTargetActionItem -Id ([string]$Proposal.sourceId))) { return [pscustomobject]@{ valid = $false; reason = 'target action item not found'; intent = $null } }
            return (& $mk @{ mode = 'field'; destination = 'Action Items'; targetId = [string]$Proposal.sourceId; newId = ''; field = 'archived'; expected = 'True'; title = $title; create = $false })
        }
        { $_ -eq 'task' -or $script:ExecFollowUpTypes -contains $_ } {
            $t = if ($script:ExecFollowUpTypes -contains $type) { 'Follow up: ' + $title } else { $title }
            $newId = if (Get-Command Get-NextActionId -ErrorAction SilentlyContinue) { Get-NextActionId -Data (Get-ActionItemsData) } else { $null }
            if (-not $newId) { return [pscustomobject]@{ valid = $false; reason = 'Action Items owner unavailable'; intent = $null } }
            return (& $mk @{ mode = 'create-id'; destination = 'Action Items'; targetId = $newId; newId = $newId; field = ''; expected = ''; title = $t; create = $true })
        }
        { $ownerDest.ContainsKey($_) } {
            # required field: a non-empty title/value (the owner also validates)
            if ([string]::IsNullOrWhiteSpace($title)) { return [pscustomobject]@{ valid = $false; reason = 'create requires a non-empty title'; intent = $null } }
            if (-not (Get-Command Get-InboxCreateId -ErrorAction SilentlyContinue)) { return [pscustomobject]@{ valid = $false; reason = 'owner id allocator unavailable'; intent = $null } }
            # deterministic, stable target id from the execution identity (proposal +
            # fingerprint). Same proposal -> same id on retry/restart; never regenerated.
            $seed = Get-ExecutionIdempotencyKey -Proposal $Proposal
            $newId = Get-InboxCreateId -Type $type -Seed $seed
            if (-not $newId) { return [pscustomobject]@{ valid = $false; reason = ("no owner create id available for type: {0}" -f $type); intent = $null } }
            return (& $mk @{ mode = 'create-id'; destination = $ownerDest[$type]; targetId = $newId; newId = $newId; field = ''; expected = ''; title = $title; create = $true; route = $true })
        }
        default          { return (& $mk @{ mode = 'result'; destination = ''; targetId = ''; newId = ''; field = ''; expected = ''; title = $title; create = $false }) }
    }
}
# THE verification gate: does the owner store now show exactly what the persisted
# intent said it would? Works identically at runtime and during restart recovery,
# because the intent (not the handler's claims) defines success.
function Test-ExecutionIntentApplied {
    param($Intent, $Result)
    if (-not $Intent) { return $false }
    try {
        switch ([string]$Intent.mode) {
            'field' {
                $actual = Get-ActionItemField -Id ([string]$Intent.targetId) -Field ([string]$Intent.field)
                if ([string]$Intent.field -eq 'archived') { return [bool]$actual }
                return ($null -ne $actual -and [string]$actual -eq [string]$Intent.expected)
            }
            'create-id' { return (Test-ExecutionApplied -Destination ([string]$Intent.destination) -NewId ([string]$Intent.newId)) }
            'title' {
                # TITLE-MODE IS RETIRED (Epic 16A). No production create emits it; every
                # owner create is now a create-id intent verified by exact identity. This
                # branch survives only to FAIL CLOSED for any legacy title record: it can
                # succeed ONLY on a precise result.newId that resolves to a real owner
                # record - never by title membership or title-count delta.
                if ($Result -and $Result.newId -and (Test-ExecutionApplied -Destination ([string]$Intent.destination) -NewId ([string]$Result.newId))) { return $true }
                return $false
            }
            'result' {
                if (-not $Result -or -not $Result.newId) { return $false }
                return (Test-ExecutionApplied -Destination ([string]$Result.destination) -NewId ([string]$Result.newId))
            }
            default { return $false }
        }
    }
    catch { return $false }
}

# ---- local action verbs (first-class; Action Items) --------------------
# Small, deterministic mutators on the Action Items owner store. Every handler
# reads its ids and values from the PERSISTED INTENT - never invents them - so
# what executes is exactly what was recorded before the side effect.
function Set-ActionItemFields {
    param([Parameter(Mandatory)][string]$Id, [Parameter(Mandatory)][hashtable]$Fields)
    if (-not (Get-Command Get-ActionItemsData -ErrorAction SilentlyContinue)) { return $false }
    $d = Get-ActionItemsData
    $hit = $false
    foreach ($it in @($d.items)) {
        if ([string]$it.id -eq $Id) {
            foreach ($k in $Fields.Keys) {
                if ($it.PSObject.Properties.Name -contains $k) { $it.$k = $Fields[$k] }
                else { $it | Add-Member -NotePropertyName $k -NotePropertyValue $Fields[$k] -Force }
            }
            $hit = $true
        }
    }
    if ($hit) { Save-ActionItemsData $d }
    return $hit
}
function Get-ActionItemField {
    param([string]$Id, [string]$Field)
    if (-not (Get-Command Get-ActionItemsData -ErrorAction SilentlyContinue)) { return $null }
    $it = @((Get-ActionItemsData).items | Where-Object { [string]$_.id -eq $Id })[0]
    if (-not $it -or -not ($it.PSObject.Properties.Name -contains $Field)) { return $null }
    return $it.$Field
}
# Idempotent create under a PRE-ALLOCATED id: if the intended item already exists
# (a retried/recovered execution), it is NOT created twice.
function New-IntendedActionItem {
    param([Parameter(Mandatory)][string]$Id, [Parameter(Mandatory)][string]$Title)
    if (-not (Get-Command Add-ActionItem -ErrorAction SilentlyContinue)) { return $false }
    $d = Get-ActionItemsData
    if (@($d.items | Where-Object { [string]$_.id -eq $Id }).Count -gt 0) { return $true }
    [void](Add-ActionItem -Data $d -Title $Title -Id $Id)
    Save-ActionItemsData $d
    return $true
}

# ---- identity: fingerprint + idempotency (Epic 15.1) --------------------
# The fingerprint pins the proposal CONTENT; the idempotency key pins proposal +
# content, so one proposal maps to at most one active/successful execution and an
# edited proposal is a different execution identity.
function Get-ProposalFingerprint {
    param([Parameter(Mandatory)] $Proposal)
    $material = (@([string]$Proposal.type, [string]$Proposal.title, [string]$Proposal.description,
            [string]$Proposal.sourceId, [string]$Proposal.proposedDestination) -join "`n")
    $md5 = [System.Security.Cryptography.MD5]::Create()
    return (([System.BitConverter]::ToString($md5.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($material))) -replace '-', '').Substring(0, 16))
}
function Get-ExecutionIdempotencyKey {
    param([Parameter(Mandatory)] $Proposal)
    # The proposal INSTANCE identity. Prefer the durable per-instance uid (INBOX ids
    # are reused, so id alone cannot distinguish two separate proposals); fall back to
    # id + created for legacy/hand-built proposals. The content fingerprint is included
    # so a content edit is a new intent. Deterministic and stable across restart.
    $instance = if (($Proposal.PSObject.Properties.Name -contains 'uid') -and $Proposal.uid) { [string]$Proposal.uid }
    else { ('{0}|{1}' -f [string]$Proposal.id, [string]$Proposal.created) }
    return ('{0}|{1}' -f $instance, (Get-ProposalFingerprint -Proposal $Proposal))
}

# ---- engine-private state: what a handler is allowed to see -------------
# Handlers receive a DEEP-CLONED request DTO - proposal facts + intent, nothing
# else. No 'id', no 'state', no 'history': mutating it changes nothing, and
# passing it to Set-ExecutionState throws. The engine alone owns the record.
function New-ActionRequest {
    param([Parameter(Mandatory)] $Record, $Result = $null)
    $c = $Record | ConvertTo-Json -Depth 12 | ConvertFrom-Json
    $req = [pscustomobject]@{
        executionId         = [string]$c.id
        proposalId          = [string]$c.proposalId
        type                = [string]$c.type
        title               = [string]$c.title
        description         = [string]$c.description
        source              = [string]$c.source
        sourceId            = [string]$c.sourceId
        proposedDestination = [string]$c.proposedDestination
        intent              = $c.intent
    }
    if ($null -ne $Result) { $req | Add-Member -NotePropertyName result -NotePropertyValue ($Result | ConvertTo-Json -Depth 8 | ConvertFrom-Json) -Force }
    return $req
}
# A handler's return is REDUCED to the four result fields. Forged state / history /
# succeeded flags are dropped; multiple pipeline outputs are malformed (rejected);
# anything without a boolean 'ok' is malformed.
function ConvertTo-SanitizedActionResult {
    param($Raw)
    if ($null -eq $Raw) { return $null }
    if ($Raw -is [System.Array]) { return $null }
    if (-not $Raw.PSObject -or -not ($Raw.PSObject.Properties.Name -contains 'ok')) { return $null }
    return [pscustomobject]@{
        ok          = [bool]$Raw.ok
        destination = $(if ($Raw.PSObject.Properties.Name -contains 'destination') { [string]$Raw.destination } else { '' })
        newId       = $(if ($Raw.PSObject.Properties.Name -contains 'newId') { [string]$Raw.newId } else { '' })
        message     = $(if ($Raw.PSObject.Properties.Name -contains 'message') { [string]$Raw.message } else { '' })
    }
}

# ---- handler registry --------------------------------------------------
# type -> { execute(request) -> {ok,destination,newId,message}; verify(request) -> bool }.
# The engine's own intent gate is ALWAYS the authority; a handler verify can only
# add strictness on top of it.
$script:ActionHandlers = @{}
function Register-ActionHandler {
    param([Parameter(Mandatory)][string]$Type, [Parameter(Mandatory)][scriptblock]$Execute, [Parameter(Mandatory)][scriptblock]$Verify)
    $script:ActionHandlers[$Type] = [pscustomobject]@{ execute = $Execute; verify = $Verify }
}
function Get-ActionHandler { param([string]$Type) if ($script:ActionHandlers.ContainsKey($Type)) { return $script:ActionHandlers[$Type] } return $null }

# reminder: create the PRE-ALLOCATED action item carrying remindAt (from the intent).
Register-ActionHandler -Type 'reminder' `
    -Execute {
        param($Request)
        $i = $Request.intent
        if (-not (New-IntendedActionItem -Id ([string]$i.newId) -Title ([string]$Request.title))) { return [pscustomobject]@{ ok = $false; message = 'Action Items owner unavailable.' } }
        [void](Set-ActionItemFields -Id ([string]$i.newId) -Fields @{ remindAt = [string]$i.expected; kind = 'reminder' })
        return [pscustomobject]@{ ok = $true; destination = 'Action Items'; newId = [string]$i.newId; message = ("Reminder created ({0})." -f $i.newId) }
    } `
    -Verify { param($Request) return $true }   # the engine's intent gate is the authority

# set-priority: set priority on the EXISTING intent target.
Register-ActionHandler -Type 'set-priority' `
    -Execute {
        param($Request)
        $i = $Request.intent
        if (-not (Set-ActionItemFields -Id ([string]$i.targetId) -Fields @{ priority = [string]$i.expected })) { return [pscustomobject]@{ ok = $false; message = 'Target action item not found.' } }
        return [pscustomobject]@{ ok = $true; destination = 'Action Items'; newId = [string]$i.targetId; message = ("Priority set on {0}." -f $i.targetId) }
    } `
    -Verify { param($Request) return $true }

# defer: set deferredUntil on the existing intent target.
Register-ActionHandler -Type 'defer' `
    -Execute {
        param($Request)
        $i = $Request.intent
        if (-not (Set-ActionItemFields -Id ([string]$i.targetId) -Fields @{ deferredUntil = [string]$i.expected })) { return [pscustomobject]@{ ok = $false; message = 'Target action item not found.' } }
        return [pscustomobject]@{ ok = $true; destination = 'Action Items'; newId = [string]$i.targetId; message = ("Deferred {0}." -f $i.targetId) }
    } `
    -Verify { param($Request) return $true }

# archive: archive the existing intent target.
Register-ActionHandler -Type 'archive' `
    -Execute {
        param($Request)
        $i = $Request.intent
        if (-not (Get-Command Set-ActionItemArchived -ErrorAction SilentlyContinue)) { return [pscustomobject]@{ ok = $false; message = 'Action Items owner unavailable.' } }
        $d = Get-ActionItemsData
        if (@($d.items | Where-Object { [string]$_.id -eq [string]$i.targetId }).Count -eq 0) { return [pscustomobject]@{ ok = $false; message = 'Target action item not found.' } }
        [void](Set-ActionItemArchived -Data $d -Id ([string]$i.targetId) -Archived $true)
        Save-ActionItemsData $d
        return [pscustomobject]@{ ok = $true; destination = 'Action Items'; newId = [string]$i.targetId; message = ("Archived {0}." -f $i.targetId) }
    } `
    -Verify { param($Request) return $true }

# Engine-internal create for 'create-id' intents (task + connector follow-ups):
# the item is created under the intent's PRE-ALLOCATED id, so recovery can always
# tell whether this exact write landed.
function Invoke-IntentCreateExecute {
    param($Request)
    $i = $Request.intent
    if (-not (New-IntendedActionItem -Id ([string]$i.newId) -Title ([string]$i.title))) { return [pscustomobject]@{ ok = $false; message = 'Action Items owner unavailable.' } }
    return [pscustomobject]@{ ok = $true; destination = 'Action Items'; newId = [string]$i.newId; message = ("Added action item {0}." -f $i.newId) }
}
# Owner-minted creates (goal / project / life domains / memory): route through the
# owner's existing writer, passing the intent's PRE-ALLOCATED targetId so the owner
# persists that exact id and verification is by exact identity (Epic 16A).
function Invoke-DefaultActionExecute {
    param($Record)
    if (-not (Get-Command Invoke-InboxRoute -ErrorAction SilentlyContinue)) { return [pscustomobject]@{ ok = $false; message = 'Inbox router unavailable.' } }
    $tid = if ($Record.intent -and ($Record.intent.PSObject.Properties.Name -contains 'newId')) { [string]$Record.intent.newId } else { '' }
    $item = [pscustomobject]@{ id = $Record.proposalId; type = $Record.type; title = $Record.title; description = $Record.description; source = $Record.source; sourceId = $Record.sourceId; proposedDestination = $Record.proposedDestination; targetId = $tid }
    $route = Invoke-InboxRoute -Item $item
    if (-not $route.ok) { return [pscustomobject]@{ ok = $false; message = [string]$route.message } }
    # the owner must have persisted the exact pre-allocated id
    if ($tid -and ([string]$route.newId) -ne $tid) { return [pscustomobject]@{ ok = $false; message = ("owner did not persist the pre-allocated id ({0})" -f $tid) } }
    return [pscustomobject]@{ ok = $true; destination = [string]$route.destination; newId = [string]$route.newId; message = [string]$route.message }
}

# ---- recovery resolution (shared by restart + idempotency) --------------
# Resolve ONE non-terminal record by verifying its persisted intent - walking only
# LEGAL transitions to the truthful terminal state. Never re-runs a write.
function Resolve-ExecutionByVerification {
    param([Parameter(Mandatory)] $Record, [string]$Why = 'recovery')
    $landed = $false
    if ($Record.PSObject.Properties.Name -contains 'intent' -and $Record.intent) {
        $landed = Test-ExecutionIntentApplied -Intent $Record.intent -Result $Record.result
    }
    elseif ($Record.result -and $Record.result.newId) {
        # legacy record (pre-intent): verify from the persisted result
        $landed = Test-ExecutionApplied -Destination ([string]$Record.result.destination) -NewId ([string]$Record.result.newId)
    }
    if ($landed) {
        # walk the LEGAL chain from wherever the crash left it up to succeeded
        while ([string]$Record.state -ne 'verifying') {
            $next = switch ([string]$Record.state) { 'pending' { 'validating' } 'validating' { 'executing' } 'executing' { 'verifying' } }
            [void](Set-ExecutionState -Record $Record -State $next -Detail ("{0}: advancing to re-verify" -f $Why))
        }
        [void](Set-ExecutionState -Record $Record -State 'succeeded' -Detail ("{0}: intended owner change verified (nothing re-run)" -f $Why))
        return 'succeeded'
    }
    [void](Set-ExecutionState -Record $Record -State 'failed' -Detail ("{0}: intended change not found (safe to re-propose; nothing was re-run)" -f $Why))
    return 'failed'
}

# ---- the state machine: the one execution path -------------------------
# idempotency -> intent persisted -> execute (DTO) -> result persisted -> verify
# (from intent) -> terminal. Never throws: any failure transitions the record to
# 'failed' with a truthful reason and returns a calm result.
function Invoke-ProposalExecution {
    param([Parameter(Mandatory)] $Proposal, $Approval = $null)
    if (-not $Proposal -or -not $Proposal.id) { return [pscustomobject]@{ ok = $false; message = 'No proposal to execute.'; executionId = $null } }

    # ---- approval-first (Epic 15.1): the approval must be REAL and CURRENT ----
    # Execution requires explicit approval metadata whose fingerprint matches the
    # proposal AS IT IS NOW. A missing approval fails safely (a direct call cannot
    # bypass the approval path); a stale fingerprint means the proposal was edited
    # after it was approved - the old approval no longer covers it.
    if (-not $Approval -or -not ($Approval.PSObject.Properties.Name -contains 'fingerprint')) {
        return [pscustomobject]@{ ok = $false; message = 'No approval metadata; execution requires an explicit user approval.'; executionId = $null }
    }
    $fpNow = $null
    try { $fpNow = Get-ProposalFingerprint -Proposal $Proposal } catch { $fpNow = $null }
    if (-not $fpNow -or ([string]$Approval.fingerprint) -ne $fpNow) {
        return [pscustomobject]@{ ok = $false; message = 'The proposal changed after it was approved; approve the current version to execute it.'; executionId = $null }
    }

    # ---- idempotency: one proposal -> at most one active/successful execution ----
    $key = $null
    try { $key = Get-ExecutionIdempotencyKey -Proposal $Proposal } catch { $key = $null }
    if ($key) {
        $twins = @(Get-Executions -State 'all' | Where-Object { ($_.PSObject.Properties.Name -contains 'idempotencyKey') -and [string]$_.idempotencyKey -eq $key })
        $done = @($twins | Where-Object { $_.state -eq 'succeeded' })
        if ($done.Count -gt 0) {
            $d = $done[-1]
            return [pscustomobject]@{ ok = $true; destination = [string]$d.result.destination; newId = [string]$d.result.newId; message = ([string]$d.result.message + ' (already completed)'); executionId = [string]$d.id; deduped = $true }
        }
        $open = @($twins | Where-Object { $script:ExecNonTerminal -contains [string]$_.state })
        if ($open.Count -gt 0) {
            # resolve the in-flight twin by verification instead of starting a second
            # execution (and a second write). A deliberate retry is a NEW invocation
            # after this one reports the truthful terminal state.
            $o = $open[0]
            $outcome = Resolve-ExecutionByVerification -Record $o -Why 'duplicate-invocation resolution'
            if ($outcome -eq 'succeeded') {
                return [pscustomobject]@{ ok = $true; destination = [string]$o.result.destination; newId = [string]$o.result.newId; message = 'Verified as already applied.'; executionId = [string]$o.id; deduped = $true }
            }
            return [pscustomobject]@{ ok = $false; message = 'A previous attempt could not be verified and was marked failed. Approve again to retry.'; executionId = [string]$o.id; deduped = $true }
        }
        # only FAILED twins remain -> a deliberate retry is allowed (new attempt below)
    }

    $rec = $null
    try { $rec = New-ExecutionRecord -Proposal $Proposal }
    catch { return [pscustomobject]@{ ok = $false; message = 'The execution log could not be written; nothing was changed.'; executionId = $null } }
    $rec.attempts = 1

    # ---- validating ----
    [void](Set-ExecutionState -Record $rec -State 'validating' -Detail ("type={0}" -f $rec.type))
    if ([string]::IsNullOrWhiteSpace([string]$rec.title)) {
        [void](Set-ExecutionState -Record $rec -State 'failed' -Detail 'proposal has no title')
        return [pscustomobject]@{ ok = $false; message = 'Proposal has no title; cannot execute.'; executionId = $rec.id }
    }
    # build + PERSIST THE INTENT before any side effect. If this persist fails, no
    # owner write happens - a log that cannot record intent blocks execution.
    $iv = New-ExecutionIntent -Proposal $Proposal
    if (-not $iv.valid) {
        [void](Set-ExecutionState -Record $rec -State 'failed' -Detail ("intent: {0}" -f $iv.reason))
        return [pscustomobject]@{ ok = $false; message = $iv.reason; executionId = $rec.id }
    }
    $rec.intent = $iv.intent
    $rec.approval = [pscustomobject]@{
        approvedBy  = [string]$Approval.approvedBy
        approvedAt  = [string]$Approval.approvedAt
        source      = [string]$Approval.source
        fingerprint = [string]$Approval.fingerprint
    }
    try { [void](Update-ExecutionRecord -Record $rec) }
    catch {
        try { [void](Set-ExecutionState -Record $rec -State 'failed' -Detail 'could not persist the execution intent') } catch { }
        return [pscustomobject]@{ ok = $false; message = 'The execution intent could not be recorded; nothing was changed.'; executionId = $rec.id }
    }
    $handler = Get-ActionHandler -Type ([string]$rec.type)
    # an owner-minted create-id routes through the owner's writer (Invoke-InboxRoute);
    # everything else create-id is an Action Item created internally by the engine.
    $isOwnerRoute = (-not $handler -and [string]$rec.intent.mode -eq 'create-id' -and ($rec.intent.PSObject.Properties.Name -contains 'route') -and [bool]$rec.intent.route)
    if ((-not $handler) -and ($isOwnerRoute -or [string]$rec.intent.mode -eq 'result') -and -not (Get-Command Invoke-InboxRoute -ErrorAction SilentlyContinue)) {
        [void](Set-ExecutionState -Record $rec -State 'failed' -Detail 'no owner router available')
        return [pscustomobject]@{ ok = $false; message = 'The owning module is not available; left pending.'; executionId = $rec.id }
    }

    # ---- executing (handlers see a DTO, never the live record) ----
    [void](Set-ExecutionState -Record $rec -State 'executing' -Detail ("mode={0}" -f $rec.intent.mode))
    $result = $null
    try {
        $request = New-ActionRequest -Record $rec
        $raw = if ($handler) { & $handler.execute $request }
        elseif ($isOwnerRoute) { Invoke-DefaultActionExecute -Record $rec }
        elseif ([string]$rec.intent.mode -eq 'create-id') { Invoke-IntentCreateExecute -Request $request }
        else { Invoke-DefaultActionExecute -Record $rec }
        $result = ConvertTo-SanitizedActionResult -Raw $raw
    }
    catch {
        [void](Set-ExecutionState -Record $rec -State 'failed' -Detail ("execute threw: {0}" -f $_.Exception.Message))
        return [pscustomobject]@{ ok = $false; message = ("Could not execute it: {0}" -f $_.Exception.Message); executionId = $rec.id }
    }
    if (-not $result) {
        [void](Set-ExecutionState -Record $rec -State 'failed' -Detail 'execute returned a malformed result')
        return [pscustomobject]@{ ok = $false; message = 'The handler returned a malformed result; nothing was marked done.'; executionId = $rec.id }
    }
    if (-not $result.ok) {
        [void](Set-ExecutionState -Record $rec -State 'failed' -Detail ("execute not ok: {0}" -f $result.message))
        return [pscustomobject]@{ ok = $false; message = $result.message; executionId = $rec.id }
    }
    # persist the RESULT immediately - before verification - so a crash from here on
    # recovers with full knowledge of what was written.
    $rec.result = $result
    try { [void](Update-ExecutionRecord -Record $rec) } catch { }

    # ---- verifying (the ENGINE'S intent gate; a handler verify only adds strictness) ----
    [void](Set-ExecutionState -Record $rec -State 'verifying' -Detail ("{0}:{1}" -f $rec.result.destination, $rec.result.newId))
    $verified = Test-ExecutionIntentApplied -Intent $rec.intent -Result $rec.result
    if ($verified -and $handler -and $handler.verify) {
        try { $verified = [bool](& $handler.verify (New-ActionRequest -Record $rec -Result $rec.result)) } catch { $verified = $false }
    }
    if (-not $verified) {
        [void](Set-ExecutionState -Record $rec -State 'failed' -Detail 'verification did not confirm the intended owner change')
        return [pscustomobject]@{ ok = $false; message = 'The change could not be verified; it was not marked done.'; executionId = $rec.id }
    }

    # ---- succeeded (the ENGINE'S final word; the persisted record is now immutable) ----
    [void](Set-ExecutionState -Record $rec -State 'succeeded' -Detail ("verified {0}:{1}" -f $rec.result.destination, $rec.result.newId))
    return [pscustomobject]@{ ok = $true; destination = $rec.result.destination; newId = $rec.result.newId; message = $rec.result.message; executionId = $rec.id }
}

# ---- restart safety ----------------------------------------------------
# On launch, any execution left non-terminal (a crash mid-flight) is resolved by
# verifying its PERSISTED INTENT against the owner store: the intended change
# exists -> succeeded; it does not -> failed (safe to re-propose). An execution
# with no intent persisted made no side effect by construction -> failed. Never
# re-runs a write blindly. Idempotent: terminal records are never touched again.
function Restore-ActionEngine {
    $recovered = 0; $succeeded = 0; $failed = 0
    foreach ($rec in @(Get-Executions -State 'all')) {
        if ($script:ExecTerminal -contains [string]$rec.state) { continue }
        $recovered++
        $outcome = Resolve-ExecutionByVerification -Record $rec -Why 'recovered after restart'
        if ($outcome -eq 'succeeded') { $succeeded++ } else { $failed++ }
    }
    return [pscustomobject]@{ recovered = $recovered; succeeded = $succeeded; failed = $failed }
}

# ---- audit trail read API ----------------------------------------------
function Get-ExecutionHistory { param([string]$Id) $e = Get-ExecutionById -Id $Id; if ($e) { return @($e.history) } return @() }
function Get-ExecutionSummary {
    $all = @(Get-Executions -State 'all')
    return [pscustomobject]@{
        total     = $all.Count
        succeeded = @($all | Where-Object { $_.state -eq 'succeeded' }).Count
        failed    = @($all | Where-Object { $_.state -eq 'failed' }).Count
        inFlight  = @($all | Where-Object { $script:ExecNonTerminal -contains [string]$_.state }).Count
    }
}
