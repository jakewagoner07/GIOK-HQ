# =====================================================================
# action-engine.ps1  -  The Executive Action Engine (Epic 15)
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
# and SUCCESS is never claimed until VERIFICATION confirms the owner store
# actually changed (the new record exists by id). Every transition is appended
# to a durable audit trail (execution_log.json, gitignored), so the log is both
# the history AND the restart-recovery source: an execution interrupted mid-flight
# is re-verified on the next launch and resolved to succeeded or failed - never
# left dangling, never silently retried into a double-write.
#
# Guarantees preserved from the rest of GIOK:
#   * approval-first        - only Approve-InboxItem drives an execution;
#   * single source of truth- approved data lives ONLY in its owner; the engine
#                             writes through the owner's own functions and keeps
#                             no second copy of business data (the log records
#                             executions, not the data);
#   * deterministic         - no AI, no network in this file; pure local dispatch;
#   * restart safety        - non-terminal executions are recovered by verification;
#   * no direct writes       - reasoning providers still only propose.
# =====================================================================

$ErrorActionPreference = 'Stop'

$script:ActionEngineVersion = '1.0'

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
    if (-not $d) { $d = [pscustomobject]@{ meta = [pscustomobject]@{ version = '1.0'; updated = '' }; executions = @() } }
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
# entry and the restart-recovery unit.
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
        result              = $null   # { ok; destination; newId; message }
        history             = @([pscustomobject]@{ state = 'pending'; at = $now; detail = 'execution created from approved proposal' })
    }
    $log.executions = @($log.executions) + $rec
    Save-ExecutionLog $log
    return $rec
}
# Move a record to a new state, append an audit line, and persist. Returns the record.
function Set-ExecutionState {
    param([Parameter(Mandatory)] $Record, [Parameter(Mandatory)][string]$State, [string]$Detail = '')
    if ($script:ExecStates -notcontains $State) { throw ("unknown execution state: {0}" -f $State) }
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
# Maps a routing destination to its Life OS domain (for Get-LifeItemById).
$script:ExecDestinationDomain = @{
    'Home Projects'   = 'projects'
    'Non-Negotiables' = 'nonNegotiables'
    'Family'          = 'family'
    'Health'          = 'health'
    'Financial'       = 'financial'
    'Agency'          = 'agency'
    'Learning'        = 'learning'
}
# Confirm an owner record with $NewId now exists at $Destination. This is the gate
# that stands between 'executing' and 'succeeded': no verifier passing => no success.
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

# ---- local action verbs (first-class; Action Items) --------------------
# Small, deterministic mutators on the Action Items owner store. Each returns a
# result the engine verifies. These are the LOCAL actions Epic 15 supports first.
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

# ---- handler registry --------------------------------------------------
# type -> { execute(record) -> {ok,destination,newId,message}; verify(record) -> bool }.
# Local verbs are registered here; everything else uses the DEFAULT handler that
# routes through the owner's existing writer (Invoke-InboxRoute) and verifies by id.
$script:ActionHandlers = @{}
function Register-ActionHandler {
    param([Parameter(Mandatory)][string]$Type, [Parameter(Mandatory)][scriptblock]$Execute, [Parameter(Mandatory)][scriptblock]$Verify)
    $script:ActionHandlers[$Type] = [pscustomobject]@{ execute = $Execute; verify = $Verify }
}
function Get-ActionHandler { param([string]$Type) if ($script:ActionHandlers.ContainsKey($Type)) { return $script:ActionHandlers[$Type] } return $null }

# reminder: create a NEW action item carrying a remindAt (from the proposal).
Register-ActionHandler -Type 'reminder' `
    -Execute {
        param($Record)
        if (-not (Get-Command Add-ActionItem -ErrorAction SilentlyContinue)) { return [pscustomobject]@{ ok = $false; message = 'Action Items owner unavailable.' } }
        $d = Get-ActionItemsData
        $newId = if (Get-Command Get-NextActionId -ErrorAction SilentlyContinue) { Get-NextActionId -Data $d } else { ('AI-{0:000}' -f (@($d.items).Count + 1)) }
        [void](Add-ActionItem -Data $d -Title ([string]$Record.title) -Id $newId)
        Save-ActionItemsData $d
        $when = if ($Record.description) { [string]$Record.description } else { [string]$Record.proposedDestination }
        [void](Set-ActionItemFields -Id $newId -Fields @{ remindAt = $when; kind = 'reminder' })
        return [pscustomobject]@{ ok = $true; destination = 'Action Items'; newId = $newId; message = ("Reminder created ({0})." -f $newId) }
    } `
    -Verify { param($Record) $r = $Record.result; return ((Test-ExecutionApplied -Destination 'Action Items' -NewId ([string]$r.newId)) -and $null -ne (Get-ActionItemField -Id ([string]$r.newId) -Field 'remindAt')) }

# set-priority: set priority on an EXISTING action item (the proposal's sourceId).
Register-ActionHandler -Type 'set-priority' `
    -Execute {
        param($Record)
        $target = [string]$Record.sourceId
        $value = if ($Record.description) { [string]$Record.description } else { [string]$Record.proposedDestination }
        if (-not $target) { return [pscustomobject]@{ ok = $false; message = 'No target action item id on the proposal.' } }
        if (-not (Set-ActionItemFields -Id $target -Fields @{ priority = $value })) { return [pscustomobject]@{ ok = $false; message = 'Target action item not found.' } }
        return [pscustomobject]@{ ok = $true; destination = 'Action Items'; newId = $target; message = ("Priority set on {0}." -f $target) }
    } `
    -Verify { param($Record) $r = $Record.result; $v = if ($Record.description) { [string]$Record.description } else { [string]$Record.proposedDestination }; return ([string](Get-ActionItemField -Id ([string]$r.newId) -Field 'priority') -eq $v) }

# defer: set deferredUntil on an existing action item.
Register-ActionHandler -Type 'defer' `
    -Execute {
        param($Record)
        $target = [string]$Record.sourceId
        $until = if ($Record.description) { [string]$Record.description } else { [string]$Record.proposedDestination }
        if (-not $target) { return [pscustomobject]@{ ok = $false; message = 'No target action item id on the proposal.' } }
        if (-not (Set-ActionItemFields -Id $target -Fields @{ deferredUntil = $until })) { return [pscustomobject]@{ ok = $false; message = 'Target action item not found.' } }
        return [pscustomobject]@{ ok = $true; destination = 'Action Items'; newId = $target; message = ("Deferred {0}." -f $target) }
    } `
    -Verify { param($Record) $r = $Record.result; return ($null -ne (Get-ActionItemField -Id ([string]$r.newId) -Field 'deferredUntil')) }

# archive: archive an existing action item.
Register-ActionHandler -Type 'archive' `
    -Execute {
        param($Record)
        $target = [string]$Record.sourceId
        if (-not $target) { return [pscustomobject]@{ ok = $false; message = 'No target action item id on the proposal.' } }
        if (-not (Get-Command Set-ActionItemArchived -ErrorAction SilentlyContinue)) { return [pscustomobject]@{ ok = $false; message = 'Action Items owner unavailable.' } }
        $d = Get-ActionItemsData
        [void](Set-ActionItemArchived -Data $d -Id $target -Archived $true)
        Save-ActionItemsData $d
        return [pscustomobject]@{ ok = $true; destination = 'Action Items'; newId = $target; message = ("Archived {0}." -f $target) }
    } `
    -Verify { param($Record) $r = $Record.result; $it = @((Get-ActionItemsData).items | Where-Object { [string]$_.id -eq ([string]$r.newId) })[0]; return ([bool]$it -and [bool]$it.archived) }

# The DEFAULT handler: route the proposal through its owner's existing writer, then
# verify the owner record exists by id. This is how goal / project / life / memory /
# task / connector-follow-up proposals execute - all through the engine, all verified.
function Invoke-DefaultActionExecute {
    param($Record)
    if (-not (Get-Command Invoke-InboxRoute -ErrorAction SilentlyContinue)) { return [pscustomobject]@{ ok = $false; message = 'Inbox router unavailable.' } }
    $item = [pscustomobject]@{ id = $Record.proposalId; type = $Record.type; title = $Record.title; description = $Record.description; source = $Record.source; sourceId = $Record.sourceId; proposedDestination = $Record.proposedDestination }
    $route = Invoke-InboxRoute -Item $item
    if (-not $route.ok) { return [pscustomobject]@{ ok = $false; message = [string]$route.message } }
    return [pscustomobject]@{ ok = $true; destination = [string]$route.destination; newId = [string]$route.newId; message = [string]$route.message }
}
function Test-DefaultActionVerified { param($Record) $r = $Record.result; return (Test-ExecutionApplied -Destination ([string]$r.destination) -NewId ([string]$r.newId)) }

# ---- the state machine: the one execution path -------------------------
# Drives an approved proposal through validate -> execute -> verify. Never throws:
# any failure at any stage transitions the record to 'failed' with a truthful reason
# and returns a calm result. SUCCESS requires the verifier to pass.
function Invoke-ProposalExecution {
    param([Parameter(Mandatory)] $Proposal)
    if (-not $Proposal -or -not $Proposal.id) { return [pscustomobject]@{ ok = $false; message = 'No proposal to execute.'; executionId = $null } }
    $rec = New-ExecutionRecord -Proposal $Proposal
    $rec.attempts = 1

    # ---- validating ----
    [void](Set-ExecutionState -Record $rec -State 'validating' -Detail ("type={0}" -f $rec.type))
    $handler = Get-ActionHandler -Type ([string]$rec.type)
    $isLocal = [bool]$handler
    if (-not $isLocal) {
        # a standard owner-routed proposal: the router must be present
        if (-not (Get-Command Invoke-InboxRoute -ErrorAction SilentlyContinue)) {
            [void](Set-ExecutionState -Record $rec -State 'failed' -Detail 'no owner router available')
            return [pscustomobject]@{ ok = $false; message = 'The owning module is not available; left pending.'; executionId = $rec.id }
        }
    }
    if ([string]::IsNullOrWhiteSpace([string]$rec.title)) {
        [void](Set-ExecutionState -Record $rec -State 'failed' -Detail 'proposal has no title')
        return [pscustomobject]@{ ok = $false; message = 'Proposal has no title; cannot execute.'; executionId = $rec.id }
    }

    # ---- executing ----
    [void](Set-ExecutionState -Record $rec -State 'executing' -Detail $(if ($isLocal) { ("local:{0}" -f $rec.type) } else { 'owner-route' }))
    $result = $null
    try {
        $result = if ($isLocal) { & $handler.execute $rec } else { Invoke-DefaultActionExecute -Record $rec }
    }
    catch {
        [void](Set-ExecutionState -Record $rec -State 'failed' -Detail ("execute threw: {0}" -f $_.Exception.Message))
        return [pscustomobject]@{ ok = $false; message = ("Could not execute it: {0}" -f $_.Exception.Message); executionId = $rec.id }
    }
    if (-not $result -or -not $result.ok) {
        $msg = if ($result) { [string]$result.message } else { 'the owning module returned nothing' }
        [void](Set-ExecutionState -Record $rec -State 'failed' -Detail ("execute not ok: {0}" -f $msg))
        return [pscustomobject]@{ ok = $false; message = $msg; executionId = $rec.id }
    }
    $rec.result = [pscustomobject]@{ ok = $true; destination = [string]$result.destination; newId = [string]$result.newId; message = [string]$result.message }

    # ---- verifying (SUCCESS is not claimed without this) ----
    [void](Set-ExecutionState -Record $rec -State 'verifying' -Detail ("{0}:{1}" -f $rec.result.destination, $rec.result.newId))
    $verified = $false
    try { $verified = [bool]$(if ($isLocal) { & $handler.verify $rec } else { Test-DefaultActionVerified -Record $rec }) }
    catch { $verified = $false }
    if (-not $verified) {
        [void](Set-ExecutionState -Record $rec -State 'failed' -Detail 'verification did not confirm the owner change')
        return [pscustomobject]@{ ok = $false; message = 'The change could not be verified; it was not marked done.'; executionId = $rec.id }
    }

    # ---- succeeded ----
    [void](Set-ExecutionState -Record $rec -State 'succeeded' -Detail ("verified {0}:{1}" -f $rec.result.destination, $rec.result.newId))
    return [pscustomobject]@{ ok = $true; destination = $rec.result.destination; newId = $rec.result.newId; message = $rec.result.message; executionId = $rec.id }
}

# ---- restart safety ----------------------------------------------------
# On launch, any execution left non-terminal (a crash between executing and the final
# transition) is resolved by RE-VERIFYING the owner store: if the change actually
# landed, mark it succeeded; otherwise fail it (safe to re-propose). Never re-runs a
# write blindly - that is how a crash could double-write. Returns a small summary.
function Restore-ActionEngine {
    $recovered = 0; $succeeded = 0; $failed = 0
    foreach ($rec in @(Get-Executions -State 'all')) {
        if ($script:ExecTerminal -contains [string]$rec.state) { continue }
        $recovered++
        $r = $rec.result
        if ($r -and $r.newId -and (Test-ExecutionApplied -Destination ([string]$r.destination) -NewId ([string]$r.newId))) {
            [void](Set-ExecutionState -Record $rec -State 'succeeded' -Detail 'recovered after restart: owner change verified')
            $succeeded++
        }
        else {
            [void](Set-ExecutionState -Record $rec -State 'failed' -Detail 'recovered after restart: owner change not verified (safe to re-propose)')
            $failed++
        }
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
