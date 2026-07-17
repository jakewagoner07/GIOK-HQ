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
function Get-ExecutionLogPath { return (Join-Path $PSScriptRoot '..\..\execution_log.json') }
function Get-ExecutionLog {
    $p = Get-ExecutionLogPath; $d = $null
    if (Test-Path $p) { try { $d = Get-Content -Path $p -Raw -Encoding UTF8 | ConvertFrom-Json } catch { $d = $null } }
    if (-not $d) { $d = [pscustomobject]@{ meta = [pscustomobject]@{ version = '1.1'; updated = '' }; executions = @() } }
    if (-not ($d.PSObject.Properties.Name -contains 'executions') -or $null -eq $d.executions) { $d | Add-Member -NotePropertyName executions -NotePropertyValue @() -Force }
    return $d
}
function Save-ExecutionLog {
    param([Parameter(Mandatory)] $Data)
    $Data.meta.updated = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    ($Data | ConvertTo-Json -Depth 12) | Set-Content -Path (Get-ExecutionLogPath) -Encoding UTF8
}
function Get-Executions {
    param([string]$State = 'all')
    $all = @((Get-ExecutionLog).executions)
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
# The normalized titles currently present at a destination - the verification
# surface for owner-minted creates (goals / life items / memory), where the owner
# assigns the id inside its own writer and the engine cannot pre-allocate one.
function Get-DestinationTitleSet {
    param([string]$Destination)
    $titles = @()
    try {
        switch ($Destination) {
            'Goals' { if (Get-Command Get-GoalsList -ErrorAction SilentlyContinue) { $titles = @(Get-GoalsList | ForEach-Object { [string]$_.title }) } }
            'Tony Memory' { if (Get-Command Get-Memories -ErrorAction SilentlyContinue) { $titles = @(Get-Memories | ForEach-Object { [string]$_.value }) } }
            default {
                $dom = $script:ExecDestinationDomain[$Destination]
                if ($dom -and (Get-Command Get-LifeItems -ErrorAction SilentlyContinue)) { $titles = @(Get-LifeItems -Domain $dom | ForEach-Object { [string]$_.title }) }
            }
        }
    }
    catch { $titles = @() }
    return @($titles | ForEach-Object { ConvertTo-ExecNormalizedTitle $_ })
}
function ConvertTo-ExecNormalizedTitle {
    param([string]$Text)
    return (([string]$Text) -replace '\s+', ' ').Trim().TrimEnd('.', ',', '!', '?', ';', ':').ToLower()
}

# ---- the execution INTENT (Epic 15.1) ----------------------------------
# The immutable, persisted statement of what an execution will do and how success
# will be PROVEN. Built at validation time, persisted BEFORE any side effect.
# Modes:
#   'field'     - an existing Action Item ($targetId) gains $field = $expected
#   'create-id' - a NEW Action Item is created under the PRE-ALLOCATED id $newId
#   'title'     - an owner-minted record (goal/life/memory) with $title appears
#                 at $destination (the owner assigns the id inside its writer)
#   'result'    - a registered custom handler; verified from its persisted result
#                 (documented limitation: a crash before the result persist
#                 recovers to failed/retriable - safe, never a double write)
$script:ExecFollowUpTypes = @('calendar', 'crm', 'communication', 'document')
function New-ExecutionIntent {
    param([Parameter(Mandatory)] $Proposal)
    $type = [string]$Proposal.type
    $title = [string]$Proposal.title
    $value = if ($Proposal.description) { [string]$Proposal.description } else { [string]$Proposal.proposedDestination }
    $mk = { param($h) [pscustomobject]@{ valid = $true; reason = ''; intent = [pscustomobject]$h } }
    switch ($type) {
        'reminder' {
            $newId = if (Get-Command Get-NextActionId -ErrorAction SilentlyContinue) { Get-NextActionId -Data (Get-ActionItemsData) } else { $null }
            if (-not $newId) { return [pscustomobject]@{ valid = $false; reason = 'Action Items owner unavailable'; intent = $null } }
            return (& $mk @{ mode = 'field'; destination = 'Action Items'; targetId = $newId; newId = $newId; field = 'remindAt'; expected = $value; title = $title; create = $true })
        }
        'set-priority' {
            if (-not $Proposal.sourceId) { return [pscustomobject]@{ valid = $false; reason = 'no target action item id on the proposal'; intent = $null } }
            return (& $mk @{ mode = 'field'; destination = 'Action Items'; targetId = [string]$Proposal.sourceId; newId = ''; field = 'priority'; expected = $value; title = $title; create = $false })
        }
        'defer' {
            if (-not $Proposal.sourceId) { return [pscustomobject]@{ valid = $false; reason = 'no target action item id on the proposal'; intent = $null } }
            return (& $mk @{ mode = 'field'; destination = 'Action Items'; targetId = [string]$Proposal.sourceId; newId = ''; field = 'deferredUntil'; expected = $value; title = $title; create = $false })
        }
        'archive' {
            if (-not $Proposal.sourceId) { return [pscustomobject]@{ valid = $false; reason = 'no target action item id on the proposal'; intent = $null } }
            return (& $mk @{ mode = 'field'; destination = 'Action Items'; targetId = [string]$Proposal.sourceId; newId = ''; field = 'archived'; expected = 'True'; title = $title; create = $false })
        }
        { $_ -eq 'task' -or $script:ExecFollowUpTypes -contains $_ } {
            $t = if ($script:ExecFollowUpTypes -contains $type) { 'Follow up: ' + $title } else { $title }
            $newId = if (Get-Command Get-NextActionId -ErrorAction SilentlyContinue) { Get-NextActionId -Data (Get-ActionItemsData) } else { $null }
            if (-not $newId) { return [pscustomobject]@{ valid = $false; reason = 'Action Items owner unavailable'; intent = $null } }
            return (& $mk @{ mode = 'create-id'; destination = 'Action Items'; targetId = $newId; newId = $newId; field = ''; expected = ''; title = $t; create = $true })
        }
        'goal'           { return (& $mk @{ mode = 'title'; destination = 'Goals'; targetId = ''; newId = ''; field = ''; expected = ''; title = $title; create = $true }) }
        'project'        { return (& $mk @{ mode = 'title'; destination = 'Home Projects'; targetId = ''; newId = ''; field = ''; expected = ''; title = $title; create = $true }) }
        'non-negotiable' { return (& $mk @{ mode = 'title'; destination = 'Non-Negotiables'; targetId = ''; newId = ''; field = ''; expected = ''; title = $title; create = $true }) }
        'family'         { return (& $mk @{ mode = 'title'; destination = 'Family'; targetId = ''; newId = ''; field = ''; expected = ''; title = $title; create = $true }) }
        'health'         { return (& $mk @{ mode = 'title'; destination = 'Health'; targetId = ''; newId = ''; field = ''; expected = ''; title = $title; create = $true }) }
        'financial'      { return (& $mk @{ mode = 'title'; destination = 'Financial'; targetId = ''; newId = ''; field = ''; expected = ''; title = $title; create = $true }) }
        'agency'         { return (& $mk @{ mode = 'title'; destination = 'Agency'; targetId = ''; newId = ''; field = ''; expected = ''; title = $title; create = $true }) }
        'learning'       { return (& $mk @{ mode = 'title'; destination = 'Learning'; targetId = ''; newId = ''; field = ''; expected = ''; title = $title; create = $true }) }
        'memory'         { return (& $mk @{ mode = 'title'; destination = 'Tony Memory'; targetId = ''; newId = ''; field = ''; expected = ''; title = $title; create = $true }) }
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
                $want = ConvertTo-ExecNormalizedTitle ([string]$Intent.title)
                if (-not $want) { return $false }
                return ((Get-DestinationTitleSet -Destination ([string]$Intent.destination)) -contains $want)
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
    return ('{0}|{1}' -f [string]$Proposal.id, (Get-ProposalFingerprint -Proposal $Proposal))
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
# owner's existing writer. The intent's TITLE is the recovery-verification surface,
# because the owner assigns the id inside its own function.
function Invoke-DefaultActionExecute {
    param($Record)
    if (-not (Get-Command Invoke-InboxRoute -ErrorAction SilentlyContinue)) { return [pscustomobject]@{ ok = $false; message = 'Inbox router unavailable.' } }
    $item = [pscustomobject]@{ id = $Record.proposalId; type = $Record.type; title = $Record.title; description = $Record.description; source = $Record.source; sourceId = $Record.sourceId; proposedDestination = $Record.proposedDestination }
    $route = Invoke-InboxRoute -Item $item
    if (-not $route.ok) { return [pscustomobject]@{ ok = $false; message = [string]$route.message } }
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
    param([Parameter(Mandatory)] $Proposal)
    if (-not $Proposal -or -not $Proposal.id) { return [pscustomobject]@{ ok = $false; message = 'No proposal to execute.'; executionId = $null } }

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
    try { [void](Update-ExecutionRecord -Record $rec) }
    catch {
        try { [void](Set-ExecutionState -Record $rec -State 'failed' -Detail 'could not persist the execution intent') } catch { }
        return [pscustomobject]@{ ok = $false; message = 'The execution intent could not be recorded; nothing was changed.'; executionId = $rec.id }
    }
    $handler = Get-ActionHandler -Type ([string]$rec.type)
    if (-not $handler -and [string]$rec.intent.mode -eq 'title' -and -not (Get-Command Invoke-InboxRoute -ErrorAction SilentlyContinue)) {
        [void](Set-ExecutionState -Record $rec -State 'failed' -Detail 'no owner router available')
        return [pscustomobject]@{ ok = $false; message = 'The owning module is not available; left pending.'; executionId = $rec.id }
    }

    # ---- executing (handlers see a DTO, never the live record) ----
    [void](Set-ExecutionState -Record $rec -State 'executing' -Detail ("mode={0}" -f $rec.intent.mode))
    $result = $null
    try {
        $request = New-ActionRequest -Record $rec
        $raw = if ($handler) { & $handler.execute $request }
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
