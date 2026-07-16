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

# Numeric tokens in a string, normalized for comparison: integers, comma
# amounts ($50,000), decimals (7.5), percentages (12.5%), times (7:30).
# Commas are stripped so '50,000' and '50000' compare equal; currency/percent
# symbols are not part of the token. Times keep their colon.
function Get-UEGroundingNumbers {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return @() }
    $out = @()
    foreach ($m in [regex]::Matches($Text, '\d[\d,]*(?::\d+)?(?:\.\d+)?')) {
        $out += ($m.Value -replace ',', '')
    }
    return @($out | Select-Object -Unique)
}

# Significant tokens of a clause: words of 3+ chars, minus glue words. Used for
# the conservative "is this text about the cited answer AT ALL" check - stems are
# compared by 4-char prefix so 'policies'/'policy' and 'running'/'run' agree.
$script:UEGroundStop = @('the','and','for','with','that','this','from','into','your','you','are','was','were',
    'will','would','can','could','have','has','had','not','never','ever','without','about','all','any',
    'more','most','than','then','them','they','their','our','out','get','got','make','made','want','need')
function Get-UEGroundingTokens {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return @() }
    $t = ($Text.ToLower() -replace "[^a-z0-9']", ' ')
    return @($t -split '\s+' | Where-Object { $_.Length -ge 3 -and ($script:UEGroundStop -notcontains $_) } | Select-Object -Unique)
}

# Proper nouns introduced in a clause: capitalized alphabetic tokens (>= 2 chars)
# that are NOT sentence-initial (a leading capital is grammar, not a name). This is
# the FACT gate for named entities - a person, company, city, or organization that
# appears in an item but not in the cited answer is a fabrication, not a paraphrase.
# Deterministic, no dictionary: honest compression almost never introduces a novel
# proper noun, so this taxes fabrication without taxing wording. Sentence-initial
# words are skipped because we cannot tell a capitalized verb ("Reach") from a name
# there without a lexicon; that narrow blind spot is covered by the overlap floor
# (an off-topic fabrication shares no token with its source) and the review screen.
$script:UEProperNounSkip = @('I', 'A', "I'm", "I'll", "I've", "I'd")
function Get-UEProperNouns {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return @() }
    $out = @()
    $sentenceStart = $true
    foreach ($w in ($Text -split '\s+')) {
        if ([string]::IsNullOrWhiteSpace($w)) { continue }
        $core = ($w -replace "[^A-Za-z']", '')
        $isStart = $sentenceStart
        $sentenceStart = ($w -match '[.!?][""'')]*$')   # this word ends a sentence
        if ($core.Length -lt 2) { continue }
        if ($isStart) { continue }
        if ($script:UEProperNounSkip -contains $core) { continue }
        if ($core.Substring(0, 1) -cmatch '[A-Z]') { $out += $core }
    }
    return @($out | Select-Object -Unique)
}
# Does every proper noun in $Text already appear in $Source? (Case-insensitive,
# apostrophes stripped, substring match so 'Jake' grounds 'Jake''s' and 'Omaha'
# grounds 'Mutual of Omaha'.) Returns the first ungrounded proper noun, or ''.
function Get-UEUngroundedProperNoun {
    param([string]$Text, [string]$Source)
    $src = ($Source -replace "'", '').ToLower()
    foreach ($pn in (Get-UEProperNouns $Text)) {
        $needle = ($pn -replace "'", '').ToLower()
        if (-not $src.Contains($needle)) { return $pn }
    }
    return ''
}

# Cap on total items across all sections of one understanding.extract result.
# Real interviews yield well under 50; a provider returning more than this is
# malfunctioning, and the result is REJECTED outright (never silently truncated -
# a trimmed result pretending to be complete would be a quiet lie).
$script:UEMaxExtractItems = 200
function Get-UEMaxExtractItems { return $script:UEMaxExtractItems }

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
    # size sanity: a provider returning thousands of items is malfunctioning.
    # Reject the whole result - never truncate-and-pretend.
    if ($items.Count -gt $script:UEMaxExtractItems) {
        return [pscustomobject]@{ valid = $false; reason = ("result too large: {0} items (cap {1})" -f $items.Count, $script:UEMaxExtractItems) }
    }
    foreach ($it in $items) {
        # 'edited' is a USER fact, never a provider's to assert. An earlier version
        # exempted edited items from grounding (mirroring Epic 10, where an edit is
        # the user's own words) - but a provider could simply stamp edited=true on a
        # fabrication and skip the entire gate. The exemption was also pointless
        # here: extraction always emits edited=false, and a model the user HAS
        # edited is returned by Initialize-UnderstandingModel's fingerprint
        # early-return without ever routing through the kernel. So at reasoning
        # time, edited=true in provider output is illegitimate by construction and
        # rejects the whole result. User edits are unaffected: they happen in the
        # review workflow, AFTER extraction, and never pass through here.
        if (($it.PSObject.Properties.Name -contains 'edited') -and [bool]$it.edited) {
            return [pscustomobject]@{ valid = $false; reason = ("provider output cannot be marked edited: {0}" -f $it.text) }
        }
        if ([string]::IsNullOrWhiteSpace([string]$it.text)) { return [pscustomobject]@{ valid = $false; reason = 'item with no text' } }
        if ([string]::IsNullOrWhiteSpace([string]$it.sourceQuestionId)) { return [pscustomobject]@{ valid = $false; reason = ("ungrounded item (no source question): {0}" -f $it.text) } }
        if (-not $grounding) { continue }
        $real = $null
        try { $real = [string](Get-ConversationAnswer $state ([string]$it.sourceQuestionId)) } catch { $real = $null }
        if ($null -eq $real) { return [pscustomobject]@{ valid = $false; reason = ("cannot verify source for: {0}" -f $it.text) } }
        if (([string]$it.sourceAnswer) -ne $real) {
            return [pscustomobject]@{ valid = $false; reason = ("item cites words the user never said: {0}" -f $it.text) }
        }
        # TEXT grounding (the subtle-liar gate): a truthful citation does not
        # license an invented interpretation.
        # 1. every number in the text must exist in the cited answer - an invented
        #    "$999,999" cannot ride on a real quote.
        $srcNums = @(Get-UEGroundingNumbers $real)
        foreach ($n in @(Get-UEGroundingNumbers ([string]$it.text))) {
            if ($srcNums -notcontains $n) {
                return [pscustomobject]@{ valid = $false; reason = ("number '{0}' does not appear in the cited answer: {1}" -f $n, $it.text) }
            }
        }
        # 1b. every PROPER NOUN in the text must appear in the cited answer - an
        #     invented person/company/city ("Acme", "Sarah", "Chicago") cannot ride
        #     on a real quote. This is a FACT gate, not a wording gate: names are
        #     facts, and honest compression does not introduce new ones.
        $badPn = Get-UEUngroundedProperNoun -Text ([string]$it.text) -Source $real
        if ($badPn) {
            return [pscustomobject]@{ valid = $false; reason = ("proper noun '{0}' does not appear in the cited answer: {1}" -f $badPn, $it.text) }
        }
        # 2. conservative token overlap: at least one significant word of the text
        #    must appear in the cited answer (4-char stem match, so paraphrase and
        #    inflection survive). Fails closed only when the interpretation shares
        #    NOTHING with the answer it claims to come from.
        $toks = @(Get-UEGroundingTokens ([string]$it.text))
        if ($toks.Count -gt 0) {
            $srcLow = $real.ToLower()
            $anchored = $false
            foreach ($tok in $toks) {
                $stem = if ($tok.Length -ge 4) { $tok.Substring(0, 4) } else { $tok }
                if ($srcLow.Contains($stem)) { $anchored = $true; break }
            }
            if (-not $anchored) {
                return [pscustomobject]@{ valid = $false; reason = ("text shares nothing with the cited answer: {0}" -f $it.text) }
            }
        }
    }
    return [pscustomobject]@{ valid = $true; reason = '' }
}

# The remaining tasks have no engine behind the layer yet (they are still called
# directly by their owners), so their validators FAIL CLOSED unconditionally: no
# result for an unmigrated task is acceptable, from ANY provider, because the
# kernel has no way to police one. A provider claiming broad support therefore
# cannot smuggle junk through an unmigrated task - the gate rejects it and the
# router falls to the floor, whose honest answer for these tasks is 'no-provider'.
# (The CTO review caught the first version of this failing OPEN - it accepted any
# non-null output while this very comment claimed otherwise. Code and comment now
# agree, which is the entire point.)
# When a task is genuinely migrated, REPLACE its validator with a real one in the
# same commit that gives the floor its engine - never before.
foreach ($t in @('goals.refine', 'briefing.compose', 'capture.classify', 'inbox.propose', 'lifeos.reason', 'coaching.advise')) {
    Register-ReasoningValidator -TaskId $t -Validator {
        param($Output, $Request)
        return [pscustomobject]@{ valid = $false; reason = 'task not migrated' }
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
