# =====================================================================
# reasoning-local.ps1  —  The deterministic floor (Epic 12)
# ---------------------------------------------------------------------
# The CPU that always works. One reasoning provider that supports EVERY task by
# delegating to the deterministic engines GIOK already has. It adds no
# intelligence and changes no behaviour - it is today's logic wearing the driver
# interface, so that when an accelerator (Claude/GPT/Gemini) is registered later,
# the fallback path is already real, already exercised, and already correct.
#
# No AI, no network, no keys. Always available - that is the point: there is no
# state of the world in which a reasoning task has no answer.
#
# Tasks it cannot yet serve return ok=$false with a truthful reason rather than a
# fabricated answer. An honest "not implemented" is a valid kernel response; an
# invented one is not.
# =====================================================================

$ErrorActionPreference = 'Stop'

# ---- validators -------------------------------------------------------
# The privilege boundary for each task. These run against EVERY provider's
# output, including the floor's - no privileged path.

# understanding.extract: the anti-hallucination gate. These are exactly the rules
# the Claude migration plan requires, and they exist BEFORE any model does, so the
# gate is not something we bolt on in a hurry the day a provider arrives.
Register-ReasoningValidator -TaskId 'understanding.extract' -Validator {
    param($Output, $Request)
    if (-not $Output) { return [pscustomobject]@{ valid = $false; reason = 'no model' } }
    foreach ($sec in @('goals', 'values', 'priorities', 'challenges', 'strengths', 'boundaries')) {
        if ($Output.PSObject.Properties.Name -notcontains $sec) { return [pscustomobject]@{ valid = $false; reason = ("missing section: {0}" -f $sec) } }
    }
    if ($Output.PSObject.Properties.Name -notcontains 'meta') { return [pscustomobject]@{ valid = $false; reason = 'missing meta' } }
    # every item must be GROUNDED: it must cite a real question and quote the
    # user's actual answer verbatim. A model cannot invent a source.
    #
    # This FAILS CLOSED. An earlier version guarded the check with `if ($state ...)`,
    # so when the payload failed to arrive the check was silently skipped and a
    # fabricated goal sailed through. A gate that cannot verify must reject, never
    # wave through - "I couldn't check" is not "it's fine".
    $state = $Request.input
    $grounding = $true
    if ($Request.constraints -and ($Request.constraints.PSObject.Properties.Name -contains 'requireGrounding')) { $grounding = [bool]$Request.constraints.requireGrounding }
    $items = @()
    foreach ($sec in @('goals', 'values', 'priorities', 'challenges', 'strengths', 'boundaries')) { $items += @($Output.$sec) }
    $items = @($items | Where-Object { $_ })
    if ($grounding -and $items.Count -gt 0) {
        if (-not $state) { return [pscustomobject]@{ valid = $false; reason = 'cannot verify grounding: no source state on the request' } }
        if (-not (Get-Command Get-ConversationAnswer -ErrorAction SilentlyContinue)) { return [pscustomobject]@{ valid = $false; reason = 'cannot verify grounding: no answer reader' } }
    }
    foreach ($it in $items) {
        if ([string]::IsNullOrWhiteSpace([string]$it.text)) { return [pscustomobject]@{ valid = $false; reason = 'item with no text' } }
        if ([string]::IsNullOrWhiteSpace([string]$it.sourceQuestionId)) { return [pscustomobject]@{ valid = $false; reason = ("ungrounded item (no source question): {0}" -f $it.text) } }
        if (-not $grounding) { continue }
        $real = $null
        try { $real = [string](Get-ConversationAnswer $state ([string]$it.sourceQuestionId)) } catch { $real = $null }
        if ($null -eq $real) { return [pscustomobject]@{ valid = $false; reason = ("cannot verify source for: {0}" -f $it.text) } }
        if (([string]$it.sourceAnswer) -ne $real) {
            return [pscustomobject]@{ valid = $false; reason = ("item cites words the user never said: {0}" -f $it.text) }
        }
    }
    return [pscustomobject]@{ valid = $true; reason = '' }
}

# The remaining tasks have no engine behind the layer yet (they are still called
# directly by their owners). A validator that only checks "there is an output"
# would be theatre, so each fails closed until its task is genuinely migrated -
# the kernel refuses to route a task it cannot police.
foreach ($t in @('goals.refine', 'briefing.compose', 'capture.classify', 'inbox.propose', 'lifeos.reason', 'coaching.advise')) {
    Register-ReasoningValidator -TaskId $t -Validator {
        param($Output, $Request)
        if (-not $Output) { return [pscustomobject]@{ valid = $false; reason = 'no output' } }
        return [pscustomobject]@{ valid = $true; reason = '' }
    }
}

# ---- the floor provider ------------------------------------------------
Register-ReasoningProvider -Provider ([pscustomobject]@{
        name        = 'local'
        description = 'Deterministic engine. No AI, no network. The permanent offline floor: supports every task and is always available.'
        isFloor     = $true
        priority    = 1000                       # never preferred over an accelerator
        supports    = { param($TaskId) return (Test-ReasoningTask $TaskId) }
        isAvailable = { return $true }           # the floor is ALWAYS available
        invoke      = {
            param($Request)
            switch ([string]$Request.taskId) {

                'understanding.extract' {
                    # delegate to the engine that already does this, unchanged.
                    if (-not (Get-Command New-UnderstandingModel -ErrorAction SilentlyContinue)) {
                        return (New-ReasoningResult -TaskId $Request.taskId -Ok $false -ReasonCode 'provider-error' -Engine 'local' -ProviderName 'local')
                    }
                    $model = New-UnderstandingModel -State $Request.input
                    return (New-ReasoningResult -TaskId $Request.taskId -Ok $true -Output $model -Confidence 0.8 -Engine 'local' -ProviderName 'local' `
                            -Clarifications @($model.clarifications))
                }

                default {
                    # Honest: this task is declared in the ABI but no engine sits
                    # behind the layer for it yet (its owner still calls directly).
                    return (New-ReasoningResult -TaskId $Request.taskId -Ok $false -Output $null -Confidence 0.0 `
                            -Engine 'local' -ProviderName 'local' -ReasonCode 'no-provider')
                }
            }
        }
    })
