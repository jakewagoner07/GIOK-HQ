# =====================================================================
# reasoning-layer.ps1  —  The Executive Reasoning Layer (Epic 12, ARCHITECTURE)
# ---------------------------------------------------------------------
#   caller -> Invoke-Reasoning(task) -> [router] -> provider(driver) -> [validate]
#                                          |                                |
#                                          +--> deterministic floor <-------+
#
# The kernel of Tony's reasoning. A TASK is a syscall: a stable id with a typed
# input and a proposal-shaped output. A PROVIDER is a driver that declares which
# tasks it supports and whether it is available right now. This file routes,
# validates and ATTRIBUTES - it is the only place that decides who reasons.
#
# It contains NO provider, NO API key, NO HTTP, NO networking. Adding Claude/GPT/
# Gemini later means registering a driver; nothing else in GIOK changes.
#
# Five guarantees (see Blueprint/Executive_Reasoning_Layer.md):
#   1. TOTAL          - Invoke-Reasoning never throws. A driver that panics degrades.
#   2. A FLOOR        - the deterministic engine serves every task, always.
#   3. VALIDATED      - nothing unvalidated escapes; local results are not privileged.
#   4. NO AUTHORITY   - the layer NEVER writes. It returns proposals. Owners +
#                       the approval flow + the atomic transaction do the writing.
#   5. BOUNDED        - maxMs rides on every request (plumbing now; enforced when a
#                       provider that can block exists).
#
# Stateless: no store, no cache, no file of its own.
# =====================================================================

$ErrorActionPreference = 'Stop'

$script:ReasoningVersion = '1.0'
function Get-ReasoningVersion { return $script:ReasoningVersion }

# ---- the ABI: task ids are stable strings ------------------------------
# Adding a task is additive. Renaming one is a breaking change.
# 'conversation.answer' is declared for completeness but is NOT routed here yet -
# it remains served by tony-brain's registry (see the Blueprint). It is listed so
# the taxonomy is honest about what exists, not so the layer claims it.
$script:ReasoningTasks = [ordered]@{
    'understanding.extract' = 'Organize onboarding answers into a reviewable Understanding Model.'
    'goals.refine'          = 'Propose a clearer goal from a goal plus context.'
    'briefing.compose'      = 'Compose the executive briefing from Executive Context.'
    'capture.classify'      = 'Classify a captured thought into a proposal candidate.'
    'inbox.propose'         = 'Reason about a signal into an Executive Inbox proposal.'
    'lifeos.reason'         = 'Reason over one Life OS domain.'
    'coaching.advise'       = 'Coaching guidance (future).'
    'conversation.answer'   = 'Tony answers in conversation. LEGACY: served by tony-brain, not routed here yet.'
}
function Get-ReasoningTasks { return @($script:ReasoningTasks.Keys) }
function Test-ReasoningTask { param([string]$TaskId) return $script:ReasoningTasks.Contains($TaskId) }
function Get-ReasoningTaskDescription { param([string]$TaskId) if ($script:ReasoningTasks.Contains($TaskId)) { return [string]$script:ReasoningTasks[$TaskId] } return '' }

# ---- request / result --------------------------------------------------
# NOTE: the payload parameter is NOT named $Input. $Input is a PowerShell
# AUTOMATIC variable (the pipeline enumerator), so a parameter of that name is
# silently shadowed and the caller's payload never arrives. That bug made this
# layer return an EMPTY model and - far worse - made the grounding validator skip
# its check and fail OPEN, accepting a fabricated goal. The request PROPERTY is
# still 'input'; only the parameter is renamed.
function New-ReasoningRequest {
    param(
        [Parameter(Mandatory)][string]$TaskId,
        $Payload,
        $Context,
        [int]$MaxMs = 12000,
        [bool]$RequireGrounding = $true,
        [datetime]$Now = (Get-Date)
    )
    return [pscustomobject]@{
        version     = $script:ReasoningVersion
        requestId   = ('R-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
        taskId      = $TaskId
        input       = $Payload
        context     = $Context
        constraints = [pscustomobject]@{ maxMs = $MaxMs; requireGrounding = $RequireGrounding }
        createdAt   = $Now.ToString('yyyy-MM-dd HH:mm:ss')
    }
}

# reasonCode: ok | no-provider | unavailable | timeout | invalid-output |
#             provider-error | unknown-task | reentrancy-limit
function New-ReasoningResult {
    param(
        [Parameter(Mandatory)][string]$TaskId,
        [bool]$Ok = $true,
        $Output,
        [double]$Confidence = 0.5,
        [string]$Engine = 'local',
        [string]$ProviderName = 'local',
        [string]$ReasonCode = 'ok',
        $Clarifications = @(),
        [bool]$Degraded = $false
    )
    return [pscustomobject]@{
        version        = $script:ReasoningVersion
        taskId         = $TaskId
        ok             = $Ok
        output         = $Output
        confidence     = [math]::Round([math]::Max(0.0, [math]::Min(1.0, $Confidence)), 2)
        engine         = $Engine
        providerName   = $ProviderName
        reasonCode     = $ReasonCode
        clarifications = ([array]@($Clarifications))
        degraded       = $Degraded
    }
}

# ---- validators: the privilege boundary --------------------------------
# Per-task gate. A provider result that fails is DISCARDED and the floor answers.
# The floor's own result passes through the same gate - there is no privileged
# path, because a bug in the deterministic engine is no more welcome than a
# hallucination. A task with no registered validator fails CLOSED (rejected):
# an unguarded task must never be routable.
$script:ReasoningValidators = @{}
function Register-ReasoningValidator {
    param([Parameter(Mandatory)][string]$TaskId, [Parameter(Mandatory)][scriptblock]$Validator)
    if (-not (Test-ReasoningTask $TaskId)) { throw ("Unknown reasoning task: {0}" -f $TaskId) }
    $script:ReasoningValidators[$TaskId] = $Validator
}
# Returns { valid, reason }. Never throws: a validator that panics = invalid.
function Test-ReasoningOutput {
    param([Parameter(Mandatory)][string]$TaskId, $Result, $Request)
    if (-not $Result) { return [pscustomobject]@{ valid = $false; reason = 'null result' } }
    if (-not $Result.ok) { return [pscustomobject]@{ valid = $false; reason = 'provider reported not ok' } }
    $v = $script:ReasoningValidators[$TaskId]
    if (-not $v) { return [pscustomobject]@{ valid = $false; reason = 'no validator registered (fails closed)' } }
    try {
        $r = & $v $Result.output $Request
        if ($r -is [bool]) { return [pscustomobject]@{ valid = $r; reason = $(if ($r) { '' } else { 'validator rejected' }) } }
        if ($r -and ($r.PSObject.Properties.Name -contains 'valid')) { return $r }
        return [pscustomobject]@{ valid = [bool]$r; reason = '' }
    }
    catch { return [pscustomobject]@{ valid = $false; reason = ('validator error: ' + $_.Exception.Message) } }
}

# ---- provider registry (drivers) ---------------------------------------
# Shape (deliberately close to tony-brain's provider object so the two can
# converge later without a rewrite):
#   { name, description, supports(taskId)->bool, isAvailable()->bool,
#     invoke(request)->ReasoningResult, priority (lower = preferred), isFloor }
$script:ReasoningProviders = [ordered]@{}
function Register-ReasoningProvider {
    param([Parameter(Mandatory)] $Provider)
    if (-not $Provider.name -or -not $Provider.invoke) { throw 'A reasoning provider needs a name and an invoke scriptblock.' }
    $script:ReasoningProviders[$Provider.name] = $Provider
}
function Get-ReasoningProviders { return @($script:ReasoningProviders.Values) }
function Unregister-ReasoningProvider { param([string]$Name) if ($script:ReasoningProviders.Contains($Name)) { $script:ReasoningProviders.Remove($Name) } }
function Get-ReasoningFloor { return @($script:ReasoningProviders.Values | Where-Object { $_.isFloor })[0] }

# Safe capability probes: a driver that throws from supports/isAvailable is simply
# not a candidate. It can never take the caller down.
function Test-ProviderSupports {
    param($Provider, [string]$TaskId)
    if (-not $Provider) { return $false }
    if ($Provider.PSObject.Properties.Name -notcontains 'supports' -or -not $Provider.supports) { return $false }
    try { return [bool](& $Provider.supports $TaskId) } catch { return $false }
}
function Test-ProviderAvailable {
    param($Provider)
    if (-not $Provider) { return $false }
    if ($Provider.PSObject.Properties.Name -notcontains 'isAvailable' -or -not $Provider.isAvailable) { return $true }
    try { return [bool](& $Provider.isAvailable) } catch { return $false }
}

# Candidates for a task, best first. The floor is NOT a candidate here - it is the
# guaranteed last resort, applied by the router after every accelerator has failed.
# NOTE this is deliberately different from Resolve-TonyProvider, which routes to an
# UNCONFIGURED provider on purpose so it can answer honestly ("not connected").
# That is right for conversation and wrong for structured work: for a task like
# understanding.extract the right answer to "no provider" is the deterministic
# engine's real output, not an apology. So an unavailable driver is simply skipped.
function Resolve-ReasoningProviders {
    param([Parameter(Mandatory)][string]$TaskId)
    $c = @(Get-ReasoningProviders | Where-Object { -not $_.isFloor } |
        Where-Object { Test-ProviderSupports -Provider $_ -TaskId $TaskId } |
        Where-Object { Test-ProviderAvailable -Provider $_ })
    return @($c | Sort-Object @{ Expression = { if ($_.PSObject.Properties.Name -contains 'priority') { [int]$_.priority } else { 100 } } }, @{ Expression = 'name' })
}

# ---- payload isolation ---------------------------------------------------
# Drivers never see the caller's object, and never see EACH OTHER'S copies.
# The kernel takes ONE canonical snapshot of the payload at entry, and every
# dispatch (accelerator, floor, and the validator's grounding source) works from
# its own fresh clone of that snapshot. A driver that mutates its copy - then
# fails, throws, or lies - cannot poison the fallback, another provider, a later
# validation, or the caller. JSON round-trip cloning is deliberate: the payloads
# this kernel carries are the same JSON-shaped objects GIOK already persists and
# reloads, so the round trip is shape-preserving by construction.
function Copy-ReasoningPayload {
    param($Payload)
    if ($null -eq $Payload) { return $null }
    try { return ($Payload | ConvertTo-Json -Depth 24 | ConvertFrom-Json) }
    catch { return $null }   # an uncloneable payload yields null; validators fail closed on it
}
# A per-dispatch request: same envelope, private payload clone.
function New-IsolatedRequest {
    param($Request, $CanonicalPayload)
    return [pscustomobject]@{
        version     = $Request.version
        requestId   = $Request.requestId
        taskId      = $Request.taskId
        input       = (Copy-ReasoningPayload $CanonicalPayload)
        context     = $Request.context
        constraints = $Request.constraints
        createdAt   = $Request.createdAt
    }
}

# ---- guarded dispatch --------------------------------------------------
# The kernel may not panic. Every driver call goes through here.
function Invoke-ReasoningProviderGuarded {
    param($Provider, $Request)
    try {
        $r = & $Provider.invoke $Request
        if (-not $r) { return [pscustomobject]@{ result = $null; reasonCode = 'provider-error' } }
        return [pscustomobject]@{ result = $r; reasonCode = 'ok' }
    }
    catch { return [pscustomobject]@{ result = $null; reasonCode = 'provider-error' } }
}

# ---- the router (the scheduler) ----------------------------------------
# THE entry point. Never throws. Always returns a ReasoningResult whose engine
# tells the truth about who actually served it.
# Re-entrancy is bounded: a driver that calls back into the kernel is allowed a
# few levels (nested reasoning is a legitimate future pattern), but unbounded
# recursion is cut off with a truthful reasonCode instead of a stack overflow.
$script:ReasoningDepth = 0
$script:ReasoningMaxDepth = 8
function Invoke-Reasoning {
    param([Parameter(Mandatory)] $Request)
    $taskId = [string]$Request.taskId
    if (-not (Test-ReasoningTask $taskId)) {
        return (New-ReasoningResult -TaskId $taskId -Ok $false -Output $null -Confidence 0.0 `
                -Engine 'none' -ProviderName 'none' -ReasonCode 'unknown-task')
    }
    if ($script:ReasoningDepth -ge $script:ReasoningMaxDepth) {
        return (New-ReasoningResult -TaskId $taskId -Ok $false -Output $null -Confidence 0.0 `
                -Engine 'none' -ProviderName 'none' -ReasonCode 'reentrancy-limit')
    }
    $script:ReasoningDepth++
    try {

        # ONE canonical snapshot of the payload, taken before any driver runs.
        # Every dispatch below works from a private clone of this - see the
        # payload-isolation note above.
        $canonical = Copy-ReasoningPayload $Request.input

        $tried = @(Resolve-ReasoningProviders -TaskId $taskId)
        foreach ($p in $tried) {
            $g = Invoke-ReasoningProviderGuarded -Provider $p -Request (New-IsolatedRequest -Request $Request -CanonicalPayload $canonical)
            if (-not $g.result) { continue }
            # validation grounds against a FRESH canonical clone - never against the
            # copy the driver just had its hands on
            $v = Test-ReasoningOutput -TaskId $taskId -Result $g.result -Request (New-IsolatedRequest -Request $Request -CanonicalPayload $canonical)
            if (-not $v.valid) { continue }   # invalid-output: discard, try the next driver
            # attribution is stamped BY THE KERNEL - a driver cannot forge it
            $g.result.engine = [string]$p.name
            $g.result.providerName = [string]$p.name
            $g.result.reasonCode = 'ok'
            $g.result.degraded = $false
            return $g.result
        }

        # the floor: the deterministic engine. It always answers - and it answers
        # from a clean clone of the canonical payload, untouched by any accelerator.
        $floor = Get-ReasoningFloor
        if (-not $floor) {
            return (New-ReasoningResult -TaskId $taskId -Ok $false -Output $null -Confidence 0.0 `
                    -Engine 'none' -ProviderName 'none' -ReasonCode 'no-provider')
        }
        $g = Invoke-ReasoningProviderGuarded -Provider $floor -Request (New-IsolatedRequest -Request $Request -CanonicalPayload $canonical)
        if (-not $g.result) {
            return (New-ReasoningResult -TaskId $taskId -Ok $false -Output $null -Confidence 0.0 `
                    -Engine 'local' -ProviderName $floor.name -ReasonCode 'provider-error')
        }
        # An honest "I cannot serve this task yet" from the floor is a VALID kernel
        # answer, not invalid output - pass its own reasonCode through rather than
        # relabelling it. (A declared-but-unmigrated task must say 'no-provider'.)
        if (-not $g.result.ok) {
            $g.result.engine = 'local'; $g.result.providerName = [string]$floor.name
            $g.result.degraded = ($tried.Count -gt 0)
            return $g.result
        }
        $v = Test-ReasoningOutput -TaskId $taskId -Result $g.result -Request (New-IsolatedRequest -Request $Request -CanonicalPayload $canonical)
        if (-not $v.valid) {
            # the floor itself failed its own gate: report honestly rather than pass junk on
            return (New-ReasoningResult -TaskId $taskId -Ok $false -Output $null -Confidence 0.0 `
                    -Engine 'local' -ProviderName $floor.name -ReasonCode 'invalid-output')
        }
        $g.result.engine = 'local'
        $g.result.providerName = [string]$floor.name
        $g.result.reasonCode = 'ok'
        # degraded = an accelerator was asked for and could not deliver
        $g.result.degraded = ($tried.Count -gt 0)
        return $g.result

    }
    finally { $script:ReasoningDepth-- }
}

# Convenience for callers: build + route in one line.
# ($Payload, not $Input - see New-ReasoningRequest.)
function Invoke-ReasoningTask {
    param([Parameter(Mandatory)][string]$TaskId, $Payload, $Context, [int]$MaxMs = 12000)
    return (Invoke-Reasoning -Request (New-ReasoningRequest -TaskId $TaskId -Payload $Payload -Context $Context -MaxMs $MaxMs))
}
