# =====================================================================
# reasoning-claude.ps1  -  The Claude understanding driver (Epic 13)
# ---------------------------------------------------------------------
# The first real external reasoning driver. It serves EXACTLY ONE task -
# understanding.extract - by asking Claude to organize the seven onboarding
# answers into the existing Understanding Model. It plugs into the Epic 12
# kernel as a driver; the kernel routes to it, validates its output, and stamps
# provenance. This file never writes a store and never sets its own attribution.
#
# Availability = Claude configured AND consent granted for THIS attempt. An
# unavailable driver is not a candidate, so when consent is declined (or never
# asked) the kernel never invokes it and the answers never leave the machine.
#
# Reuses the existing gitignored Claude config and HTTP primitive (Get-ClaudeConfig,
# Invoke-ClaudeApi). No second secrets store. Logs no prompts, answers, responses,
# identity data, or credentials - only safe counts/status/class/timing.
# =====================================================================

$ErrorActionPreference = 'Stop'

$script:ClaudeUnderstandingId = 'claude-understanding'
# The seven real question ids (frozen; the ABI of onboarding). A cited source
# question outside this set is a fabrication and rejects the whole result.
$script:ClaudeUnderstandingQuestionIds = @('q_name', 'q_areas', 'q_goal', 'q_challenge', 'q_protect', 'q_week', 'q_boundaries')
# The six sections the model carries (name is separate; summary is a paragraph).
$script:ClaudeUnderstandingSections = @('goals', 'values', 'priorities', 'challenges', 'strengths', 'boundaries')
# A single item longer than this is not an extraction - it is a paste. Rejected.
$script:ClaudeUnderstandingMaxItemChars = 400
# More RAW items than this (across all sections, BEFORE dedup) is a malfunctioning
# provider. Rejected outright, never truncated - checked before dedup so a flood of
# identical items cannot collapse under the cap.
$script:ClaudeUnderstandingMaxItems = 200
# A raw response larger than this is malfunctioning; rejected before parsing.
$script:ClaudeUnderstandingMaxResponseBytes = 200000
# Token ceiling for the extraction call. The shared config default (1024) is sized
# for chat and truncates a full six-section extraction; this gives it room.
$script:ClaudeUnderstandingMaxTokens = 4096

# ---- test seams (offline, no network) ---------------------------------
# The permanent regression suite must exercise this driver with MOCKED responses
# and MOCKED configuration - no key, no HTTP. These two overrides are the only
# way the mocks get in; production leaves them $null and the real functions run.
$script:ClaudeUnderstandingConfiguredOverride = $null   # $true/$false to force configured state in tests
$script:ClaudeUnderstandingCallOverride = $null          # scriptblock(state) -> raw text, or throw, to mock Claude

function Set-ClaudeUnderstandingConfiguredOverride { param($Value) $script:ClaudeUnderstandingConfiguredOverride = $Value }
function Set-ClaudeUnderstandingCallOverride { param([scriptblock]$ScriptBlock) $script:ClaudeUnderstandingCallOverride = $ScriptBlock }
function Clear-ClaudeUnderstandingOverrides { $script:ClaudeUnderstandingConfiguredOverride = $null; $script:ClaudeUnderstandingCallOverride = $null }

# ---- safe diagnostics: the last attempt (NO content, ever) ------------
# Records only what the epic permits in diagnostics: provider id, task id,
# request id, status, duration, safe error class, item counts, fallback reason.
# NEVER the prompt, answers, response, identity data, or credentials.
$script:ClaudeUnderstandingLastAttempt = $null
function Set-ClaudeUnderstandingAttempt {
    param($Record) $script:ClaudeUnderstandingLastAttempt = $Record
}
function Get-ClaudeUnderstandingLastAttempt { return $script:ClaudeUnderstandingLastAttempt }
function New-ClaudeUnderstandingAttempt {
    param([string]$RequestId, [string]$Status, [int]$DurationMs = 0, [string]$ErrorClass = '', [int]$ItemCount = 0, [string]$FallbackReason = '', [string]$Task = 'understanding.extract')
    return [pscustomobject]@{
        provider = $script:ClaudeUnderstandingId; task = $Task
        requestId = $RequestId; status = $Status; durationMs = $DurationMs
        errorClass = $ErrorClass; itemCount = $ItemCount; fallbackReason = $FallbackReason
    }
}

# ---- availability -----------------------------------------------------
function Test-ClaudeUnderstandingConfigured {
    if ($null -ne $script:ClaudeUnderstandingConfiguredOverride) { return [bool]$script:ClaudeUnderstandingConfiguredOverride }
    if (-not (Get-Command Test-ClaudeConfigured -ErrorAction SilentlyContinue)) { return $false }
    try { return [bool](Test-ClaudeConfigured) } catch { return $false }
}
function Test-ClaudeUnderstandingAvailable {
    if (-not (Test-ClaudeUnderstandingConfigured)) { return $false }
    if (-not (Get-Command Test-ExtractionConsent -ErrorAction SilentlyContinue)) { return $false }
    try { return [bool](Test-ExtractionConsent) } catch { return $false }
}

# ---- the prompt contract ----------------------------------------------
# STRICT JSON out, organize-never-invent in. The model id lives only in the
# Claude config; this prompt never names it and Tony never sees it.
function Get-ClaudeExtractionSystemPrompt {
    $lines = @(
        'You organize a person''s onboarding answers into structured self-knowledge. You never invent.',
        'You return a single JSON object and nothing else - no markdown, no code fences, no prose before or after.',
        '',
        'Extract these keys, each an array unless noted: goals, values, priorities, challenges, strengths, boundaries, clarifications, omitted, and summary (a string).',
        'Every item in goals/values/priorities/challenges/strengths/boundaries MUST be an object with exactly these fields:',
        '  text, sourceQuestionId, sourceQuestion, sourceAnswer, reason, confidence, band, edited.',
        '  - sourceQuestionId is one of: q_name, q_areas, q_goal, q_challenge, q_protect, q_week, q_boundaries.',
        '  - sourceAnswer is the user''s answer to that question, copied VERBATIM (exactly, character for character).',
        '  - reason is a short second-person explanation ("You named this as...").',
        '  - confidence is a number 0.0-1.0. band is "high" or "low". edited is always false.',
        '',
        'Rules:',
        '  - Organize; never invent. Every fact must be supported by the supplied answers.',
        '  - Preserve every user-provided number, date, name, company and commitment exactly. Never introduce a new one.',
        '  - Do not create new dates, dollar amounts, targets, diagnoses, relationships, or facts.',
        '  - Split a compound goal into separate goals only when they are clearly distinct.',
        '  - Compress long answers intelligently, but never change their meaning.',
        '  - Values are principles, not priorities.',
        '  - Prefer omission over unsupported inference; put hedged/unclear things in omitted[] with a reason.',
        '  - Do not diagnose personality, mental health, medical conditions, leadership style, or risk tolerance.',
        '  - A category with no support stays an empty array. Strengths is usually empty - that is correct.',
        '  - The executive summary is concise, natural, and grounded in the answers.',
        '  - Output the JSON object only.'
    )
    return ($lines -join "`n")
}

# The user content: each question and the user's verbatim answer. No system
# instructions here - just the material to organize.
function Get-ClaudeExtractionUserContent {
    param($State)
    $parts = @('Here are the answers to organize. Use each sourceQuestionId exactly as labelled, and copy each sourceAnswer verbatim.', '')
    foreach ($id in $script:ClaudeUnderstandingQuestionIds) {
        $q = ''
        if (Get-Command Get-UEQuestionText -ErrorAction SilentlyContinue) { $q = [string](Get-UEQuestionText -Id $id) }
        $a = ''
        if (Get-Command Get-ConversationAnswer -ErrorAction SilentlyContinue) { $a = [string](Get-ConversationAnswer $State $id) }
        $parts += ('[{0}] {1}' -f $id, $q)
        $parts += ('answer: {0}' -f $a)
        $parts += ''
    }
    $parts += 'Return the JSON object now.'
    return ($parts -join "`n")
}

# ---- strict-JSON parsing ----------------------------------------------
# Pull the outermost {...} span out of a blob. This is the ONE tolerance: a model
# that wraps its object in a fence or a sentence still parses. Anything with no
# balanced object yields $null (whole-response rejection -> floor).
function Get-JsonObjectSpan {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
    $start = $Text.IndexOf('{')
    if ($start -lt 0) { return $null }
    $depth = 0; $inStr = $false; $esc = $false
    for ($i = $start; $i -lt $Text.Length; $i++) {
        $ch = $Text[$i]
        if ($inStr) {
            if ($esc) { $esc = $false }
            elseif ($ch -eq '\') { $esc = $true }
            elseif ($ch -eq '"') { $inStr = $false }
            continue
        }
        if ($ch -eq '"') { $inStr = $true; continue }
        if ($ch -eq '{') { $depth++ }
        elseif ($ch -eq '}') { $depth--; if ($depth -eq 0) { return $Text.Substring($start, $i - $start + 1) } }
    }
    return $null
}

# Parse raw Claude text into the EXISTING Understanding Model shape, or $null on
# any whole-response rejection. This does SHAPE + field-presence + clean-item
# construction only; verbatim/numeric grounding is the kernel validator's job and
# the tighter token-fraction gate is Test-ClaudeExtractionGrounded (stage 3).
# ONE malformed item rejects the WHOLE result - never a partial merge.
function ConvertFrom-ClaudeExtraction {
    param([string]$RawText, $State)
    if ([string]::IsNullOrWhiteSpace($RawText)) { return $null }
    if ([System.Text.Encoding]::UTF8.GetByteCount($RawText) -gt $script:ClaudeUnderstandingMaxResponseBytes) { return $null }

    $obj = $null
    try { $obj = $RawText | ConvertFrom-Json } catch { $obj = $null }
    if (-not $obj) {
        $span = Get-JsonObjectSpan -Text $RawText
        if (-not $span) { return $null }
        try { $obj = $span | ConvertFrom-Json } catch { return $null }
    }
    if (-not $obj -or ($obj -isnot [pscustomobject])) { return $null }

    # top-level shape: all six sections + summary must be present.
    foreach ($sec in $script:ClaudeUnderstandingSections) {
        if ($obj.PSObject.Properties.Name -notcontains $sec) { return $null }
    }
    if ($obj.PSObject.Properties.Name -notcontains 'summary') { return $null }

    # build clean items section by section. New-UnderstandingItem forces edited=false
    # and recomputes band from confidence, so a provider cannot forge either.
    $built = @{}
    $total = 0
    foreach ($sec in $script:ClaudeUnderstandingSections) {
        $items = @($obj.$sec)
        $clean = @()
        foreach ($it in $items) {
            if (-not $it -or ($it -isnot [pscustomobject])) { return $null }
            # 'edited' is the user's own fact, never a provider's to assert. A driver
            # sending edited=true is forging provenance - reject the WHOLE result
            # (one unsafe item rejects everything), rather than silently neutralizing
            # it and trusting the same lying provider's other items.
            if (($it.PSObject.Properties.Name -contains 'edited') -and [bool]$it.edited) { return $null }
            $text = [string]$it.text
            $sqid = [string]$it.sourceQuestionId
            $sans = [string]$it.sourceAnswer
            # required item fields present + a real question id + sane length.
            if ([string]::IsNullOrWhiteSpace($text)) { return $null }
            if ($script:ClaudeUnderstandingQuestionIds -notcontains $sqid) { return $null }
            if ([string]::IsNullOrWhiteSpace($sans)) { return $null }
            if ($text.Length -gt $script:ClaudeUnderstandingMaxItemChars) { return $null }
            $reason = [string]$it.reason
            $conf = 0.0; try { $conf = [double]$it.confidence } catch { $conf = 0.0 }
            $sq = ''
            if (Get-Command Get-UEQuestionText -ErrorAction SilentlyContinue) { $sq = [string](Get-UEQuestionText -Id $sqid) }
            if (Get-Command New-UnderstandingItem -ErrorAction SilentlyContinue) {
                $clean += (New-UnderstandingItem -Text $text -SourceQuestionId $sqid -SourceQuestion $sq -SourceAnswer $sans -Reason $reason -Confidence $conf)
            }
            else { return $null }
            $total++
        }
        $built[$sec] = $clean
    }
    # excessive TOTAL response size: reject the whole result (never truncate). Checked
    # on the RAW count, before dedup, so a flood of duplicates cannot slip under it.
    if ($total -gt $script:ClaudeUnderstandingMaxItems) { return $null }

    # clarifications + omitted are supplementary; default empty, shapes matched.
    $clar = @()
    foreach ($c in @($obj.clarifications)) {
        if (-not $c) { continue }
        if ($c -is [string]) { $clar += [pscustomobject]@{ question = $c; sourceQuestionId = ''; text = '' } }
        elseif ($c.PSObject.Properties.Name -contains 'question') { $clar += [pscustomobject]@{ question = [string]$c.question; sourceQuestionId = [string]$c.sourceQuestionId; text = [string]$c.text } }
    }
    $omit = @()
    foreach ($o in @($obj.omitted)) {
        if (-not $o) { continue }
        if ($o -is [string]) { $omit += [pscustomobject]@{ text = $o; reason = 'Not clearly enough stated for me to assume it.'; confidence = 0.0; sourceQuestionId = '' } }
        elseif ($o.PSObject.Properties.Name -contains 'text') { $omit += [pscustomobject]@{ text = [string]$o.text; reason = [string]$o.reason; confidence = 0.0; sourceQuestionId = [string]$o.sourceQuestionId } }
    }

    # meta: pure functions of the input + constants - engine-independent, so reusing
    # them is not "combining engines", it is structural. engine is a placeholder; the
    # kernel overwrites it with the true provenance.
    $ver = if ($null -ne $script:UnderstandingVersion) { $script:UnderstandingVersion } else { '1.0.0' }
    $thr = if ($null -ne $script:UnderstandingThreshold) { $script:UnderstandingThreshold } else { 0.7 }
    $fp = ''
    if (Get-Command Get-UEAnswersFingerprint -ErrorAction SilentlyContinue) { $fp = [string](Get-UEAnswersFingerprint -State $State) }
    $name = ''
    if (Get-Command Get-ConversationAnswer -ErrorAction SilentlyContinue) { $name = [string](Get-ConversationAnswer $State 'q_name') }
    if (Get-Command ConvertTo-UECleanClause -ErrorAction SilentlyContinue) { $name = [string](ConvertTo-UECleanClause $name) }

    $model = [pscustomobject]@{
        meta = [pscustomobject]@{
            version            = $ver
            builtAt            = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
            engine             = 'claude-understanding'
            threshold          = $thr
            approvedAt         = ''
            answersFingerprint = $fp
        }
        name             = $name
        goals            = @($built['goals'])
        values           = @($built['values'])
        priorities       = @($built['priorities'])
        challenges       = @($built['challenges'])
        strengths        = @($built['strengths'])
        boundaries       = @($built['boundaries'])
        executiveSummary = [pscustomobject]@{ text = [string]$obj.summary; reason = 'Summarized from your own answers.'; confidence = 0.8; sources = @($script:ClaudeUnderstandingQuestionIds) }
        clarifications   = ([array]$clar)
        omitted          = ([array]$omit)
    }
    return $model
}

# ---- the Claude-only grounding gate: FACTS, not wording -----------------
# Epic 13A. The machine validates facts; the human validates meaning. This gate
# enforces the fact conditions on Claude output as a WHOLE-RESULT check (one lying
# item rejects everything and the kernel falls to the floor), and it deliberately
# does NOT judge paraphrase quality - semantic compression is exactly why Claude
# exists, and the mandatory review screen is where the user approves wording.
#
# What it enforces (all deterministic, all FACTS):
#   * verbatim citation - the item quotes a real answer byte-for-byte;
#   * numeric grounding - every number/amount/percent/time in the text is in the
#     cited answer (an invented figure cannot ride a real quote);
#   * proper-noun grounding - every name/company/city in the text is in the cited
#     answer (an invented entity is a fabrication);
#   * the absurdity floor - the text shares at least ONE significant token with the
#     answer it claims to come from. "Buy a yacht" from "I want 500 policies" still
#     rejects. This is a tripwire for output that is about something the answer
#     never mentioned - NOT a paraphrase-quality threshold.
# What it NO LONGER enforces: the multi-anchor / token-fraction rule. A reasonable
# paraphrase ("Protect evenings at home" from "Home by six most nights") now passes.
function Test-ClaudeExtractionGrounded {
    param($Model, $State)
    foreach ($sec in $script:ClaudeUnderstandingSections) {
        foreach ($it in @($Model.$sec)) {
            if (-not $it) { continue }
            $text = [string]$it.text
            $sqid = [string]$it.sourceQuestionId
            $real = ''
            if (Get-Command Get-ConversationAnswer -ErrorAction SilentlyContinue) { $real = [string](Get-ConversationAnswer $State $sqid) }
            if ([string]::IsNullOrWhiteSpace($real)) { return [pscustomobject]@{ ok = $false; reason = 'no source answer' } }
            # verbatim citation (the kernel checks this too; the driver rejects the
            # WHOLE result rather than one item)
            if (([string]$it.sourceAnswer) -ne $real) { return [pscustomobject]@{ ok = $false; reason = 'sourceAnswer not verbatim' } }
            # FACT: every number in the text must appear in the cited answer
            if (Get-Command Get-UEGroundingNumbers -ErrorAction SilentlyContinue) {
                $srcNums = @(Get-UEGroundingNumbers $real)
                foreach ($n in @(Get-UEGroundingNumbers $text)) {
                    if ($srcNums -notcontains $n) { return [pscustomobject]@{ ok = $false; reason = ("fabricated number: {0}" -f $n) } }
                }
            }
            # FACT: every proper noun in the text must appear in the cited answer
            if (Get-Command Get-UEUngroundedProperNoun -ErrorAction SilentlyContinue) {
                $badPn = Get-UEUngroundedProperNoun -Text $text -Source $real
                if ($badPn) { return [pscustomobject]@{ ok = $false; reason = ("fabricated proper noun: {0}" -f $badPn) } }
            }
            # ABSURDITY FLOOR (tripwire, not a quality gate): the text must share at
            # least one significant token with the cited answer. Zero overlap means
            # the item is about something the answer never mentioned - a fabrication,
            # not a paraphrase.
            if (Get-Command Get-UEGroundingTokens -ErrorAction SilentlyContinue) {
                $toks = @(Get-UEGroundingTokens $text)
                if ($toks.Count -gt 0) {
                    $low = $real.ToLower()
                    $anchored = $false
                    foreach ($tok in $toks) {
                        $stem = if ($tok.Length -ge 4) { $tok.Substring(0, 4) } else { $tok }
                        if ($low.Contains($stem)) { $anchored = $true; break }
                    }
                    if (-not $anchored) { return [pscustomobject]@{ ok = $false; reason = ("no meaningful grounding (shares nothing with the answer): {0}" -f $text) } }
                }
            }
        }
    }
    return [pscustomobject]@{ ok = $true; reason = '' }
}

# ---- deterministic, documented dedup ----------------------------------
# Duplicates are removed section by section: normalize each item's text
# (lowercase, collapse whitespace, strip trailing punctuation) and keep the FIRST
# occurrence. Never merged into one ambiguous item; never silent - this runs
# before the review screen and the kept items are exactly the survivors.
function Get-ClaudeDedupKey {
    param([string]$Text)
    $t = ($Text -replace '\s+', ' ').Trim().TrimEnd('.', ',', '!', '?', ';', ':').ToLower()
    return $t
}
function Remove-ClaudeExtractionDuplicates {
    param($Model)
    foreach ($sec in $script:ClaudeUnderstandingSections) {
        $seen = @{}
        $kept = @()
        foreach ($it in @($Model.$sec)) {
            if (-not $it) { continue }
            $k = Get-ClaudeDedupKey ([string]$it.text)
            if ($k -and $seen.ContainsKey($k)) { continue }
            if ($k) { $seen[$k] = $true }
            $kept += $it
        }
        $Model.$sec = ([array]$kept)
    }
    return $Model
}

# ---- the portable extraction work -------------------------------------
# Call Claude (or the mock), parse, and return a PLAIN result hashtable the driver
# wraps into a ReasoningResult. This function is deliberately self-contained so
# stage 3 can run it inside a bounded runspace unchanged. It never throws to its
# caller; every failure class maps to ok=$false + a truthful fallbackReason.
function Invoke-ClaudeUnderstandingExtraction {
    param($Request)
    $state = $Request.input
    $reqId = [string]$Request.requestId
    $sw = [System.Diagnostics.Stopwatch]::StartNew()

    # get the raw text: mock override, or the real bounded-config HTTP primitive.
    $raw = $null
    try {
        if ($null -ne $script:ClaudeUnderstandingCallOverride) {
            $raw = & $script:ClaudeUnderstandingCallOverride $state
        }
        else {
            if (-not (Get-Command Get-ClaudeConfig -ErrorAction SilentlyContinue) -or -not (Get-Command Invoke-ClaudeApi -ErrorAction SilentlyContinue)) {
                $sw.Stop()
                return @{ ok = $false; reasonCode = 'unavailable'; fallbackReason = 'not-configured'; errorClass = 'not-configured'; durationMs = $sw.ElapsedMilliseconds; itemCount = 0 }
            }
            $cfg = Get-ClaudeConfig
            if (-not $cfg.configured) {
                $sw.Stop()
                return @{ ok = $false; reasonCode = 'unavailable'; fallbackReason = 'not-configured'; errorClass = 'not-configured'; durationMs = $sw.ElapsedMilliseconds; itemCount = 0 }
            }
            # Extraction needs room for all six sections + a summary; the shared config's
            # chat-sized default (1024) TRUNCATES the JSON mid-item and the parser then
            # (correctly) rejects it as malformed. Raise the ceiling for THIS call only,
            # on a private copy so the chat provider's config is untouched.
            $exCfg = [pscustomobject]@{ apiKey = $cfg.apiKey; model = $cfg.model; endpoint = $cfg.endpoint; apiVersion = $cfg.apiVersion; maxTokens = ([int][math]::Max([int]$cfg.maxTokens, $script:ClaudeUnderstandingMaxTokens)); configured = $cfg.configured }
            $sys = Get-ClaudeExtractionSystemPrompt
            $usr = Get-ClaudeExtractionUserContent -State $state
            $raw = Invoke-ClaudeApi -System $sys -Messages @(@{ role = 'user'; content = $usr }) -Config $exCfg
        }
    }
    catch {
        $sw.Stop()
        $class = 'network-error'
        if (Get-Command Get-ClaudeErrorInfo -ErrorAction SilentlyContinue) { try { $class = [string](Get-ClaudeErrorInfo $_).class } catch { $class = 'network-error' } }
        return @{ ok = $false; reasonCode = 'provider-error'; fallbackReason = $class; errorClass = $class; durationMs = $sw.ElapsedMilliseconds; itemCount = 0 }
    }

    if ([string]::IsNullOrWhiteSpace([string]$raw)) {
        $sw.Stop()
        return @{ ok = $false; reasonCode = 'invalid-output'; fallbackReason = 'empty'; errorClass = 'empty'; durationMs = $sw.ElapsedMilliseconds; itemCount = 0 }
    }

    $model = ConvertFrom-ClaudeExtraction -RawText ([string]$raw) -State $state
    if (-not $model) {
        $sw.Stop()
        return @{ ok = $false; reasonCode = 'invalid-output'; fallbackReason = 'malformed'; errorClass = 'malformed'; durationMs = $sw.ElapsedMilliseconds; itemCount = 0 }
    }

    # tighter, Claude-only grounding gate (stage 3). Whole-result reject -> floor.
    if (Get-Command Test-ClaudeExtractionGrounded -ErrorAction SilentlyContinue) {
        $g = Test-ClaudeExtractionGrounded -Model $model -State $state
        if (-not $g.ok) {
            $sw.Stop()
            return @{ ok = $false; reasonCode = 'invalid-output'; fallbackReason = 'grounding'; errorClass = 'grounding'; durationMs = $sw.ElapsedMilliseconds; itemCount = 0 }
        }
    }
    # dedup after grounding, before returning (deterministic; documented).
    if (Get-Command Remove-ClaudeExtractionDuplicates -ErrorAction SilentlyContinue) {
        $model = Remove-ClaudeExtractionDuplicates -Model $model
    }

    $sw.Stop()
    $count = 0
    foreach ($sec in $script:ClaudeUnderstandingSections) { $count += @($model.$sec).Count }
    return @{ ok = $true; reasonCode = 'ok'; output = $model; confidence = 0.85; clarifications = @($model.clarifications); fallbackReason = ''; errorClass = ''; durationMs = $sw.ElapsedMilliseconds; itemCount = $count }
}

# =====================================================================
# briefing.compose (Epic 14): the SAME driver composes the Daily Executive Plan.
# Same architecture - configured + task-scoped consent + bounded + kernel-validated
# + local floor on any failure. No separate provider path.
# =====================================================================
$script:ClaudePlanCallOverride = $null   # scriptblock(planSources) -> raw text, or throw, to mock in tests
function Set-ClaudePlanCallOverride { param([scriptblock]$ScriptBlock) $script:ClaudePlanCallOverride = $ScriptBlock }

function Get-ClaudePlanSystemPrompt {
    $lines = @(
        'You are an executive chief of staff composing a calm, realistic Daily Plan. You never invent.',
        'You return a single JSON object and nothing else - no markdown, no code fences, no prose.',
        '',
        'Return these keys: topOutcomes, protect, followUps, canWait, recommendations (arrays), clarifications (array of strings), and workload (an object { level, reason }).',
        'level is one of: light, balanced, heavy, overloaded. reason states the evidence plainly.',
        'Every item in the five arrays MUST be an object with exactly these fields:',
        '  text, sourceType, sourceId, reason, priority (1-9), confidence (0.0-1.0), requiresApproval (bool), proposedAction (object or null).',
        '  - sourceType + sourceId MUST reference a supplied source below. Use them EXACTLY as given.',
        '  - proposedAction, when present, is { type, title, detail } where type is one of:',
        '    create-action, schedule-followup, prepare-message, move-to-inbox, protect-calendar, defer-item.',
        '',
        'Rules:',
        '  - Organize what is supplied; never invent a goal, appointment, deadline, name, amount, or commitment.',
        '  - Every item must reference a supplied source. Preserve all user numbers/dates/names exactly.',
        '  - Family and personal commitments come before financial ones. People before money.',
        '  - You may RECOMMEND actions but you NEVER perform one and NEVER claim one happened.',
        '  - Any recommendation that would write sets requiresApproval=true with a proposedAction.',
        '  - Keep it small and calm: 1-3 top outcomes, only what is worth protecting, only real follow-ups.',
        '  - workload is conservative and evidence-based; never diagnose stress, burnout, or any condition.',
        '  - Output the JSON object only.'
    )
    return ($lines -join "`n")
}

function Get-ClaudePlanUserContent {
    param($PlanSources)
    $parts = @('Compose the Daily Plan from these sources and signals. Use each sourceType/sourceId exactly as labelled.', '')
    $t = $PlanSources.time
    $parts += ("Today: {0}, {1} ({2})." -f $t.dayOfWeek, $t.date, $t.partOfDay)
    $s = $PlanSources.signals
    $parts += ("Signals: {0} calendar events today, {1} time-sensitive follow-ups, {2} conflicts, {3} do-today priorities, {4} minutes longest free block." -f $s.calendarToday, $s.timeSensitiveCount, $s.conflicts, $s.doTodayCount, $s.longestFreeMinutes)
    $parts += ''
    $parts += 'Sources:'
    foreach ($src in @($PlanSources.sources)) {
        $extra = ''
        if ($src.PSObject.Properties.Name -contains 'when' -and $src.when) { $extra += (" when=" + [string]$src.when) }
        if ($src.PSObject.Properties.Name -contains 'daysAway') { $extra += (" daysAway=" + [string]$src.daysAway) }
        if ($src.PSObject.Properties.Name -contains 'why' -and $src.why) { $extra += (" why=" + [string]$src.why) }
        $parts += ("[{0} / {1}] {2}{3}" -f $src.sourceType, $src.sourceId, $src.text, $extra)
    }
    if (@($PlanSources.clarifications).Count -gt 0) {
        $parts += ''
        $parts += 'Open questions the day raises:'
        foreach ($c in @($PlanSources.clarifications)) { $parts += ('- ' + [string]$c) }
    }
    $parts += ''
    $parts += 'Return the JSON object now.'
    return ($parts -join "`n")
}

# Parse Claude's Daily Plan JSON into the model shape, or $null on whole-response
# rejection. Shape + clean-item construction only; grounding (source membership,
# claim/approval checks) is the kernel briefing.compose validator's job and is
# ALSO re-checked in Invoke-ClaudePlanCompose for a truthful fallbackReason. A
# fabricated action type rejects the whole result here.
function ConvertFrom-ClaudePlan {
    param([string]$RawText, $PlanSources)
    if ([string]::IsNullOrWhiteSpace($RawText)) { return $null }
    if ([System.Text.Encoding]::UTF8.GetByteCount($RawText) -gt $script:ClaudeUnderstandingMaxResponseBytes) { return $null }
    $obj = $null
    try { $obj = $RawText | ConvertFrom-Json } catch { $obj = $null }
    if (-not $obj) {
        $span = Get-JsonObjectSpan -Text $RawText
        if (-not $span) { return $null }
        try { $obj = $span | ConvertFrom-Json } catch { return $null }
    }
    if (-not $obj -or ($obj -isnot [pscustomobject])) { return $null }
    $sections = if ($null -ne $script:DailyPlanSections) { $script:DailyPlanSections } else { @('topOutcomes', 'protect', 'followUps', 'canWait', 'recommendations') }
    $types = if ($null -ne $script:DailyPlanSourceTypes) { $script:DailyPlanSourceTypes } else { @() }
    $actionTypes = if ($null -ne $script:DailyPlanActionTypes) { $script:DailyPlanActionTypes } else { @() }
    $levels = if ($null -ne $script:DailyPlanWorkloadLevels) { $script:DailyPlanWorkloadLevels } else { @('light', 'balanced', 'heavy', 'overloaded') }
    $maxChars = if ($null -ne $script:DailyPlanMaxItemChars) { $script:DailyPlanMaxItemChars } else { 300 }

    foreach ($sec in $sections) { if ($obj.PSObject.Properties.Name -notcontains $sec) { return $null } }
    if ($obj.PSObject.Properties.Name -notcontains 'workload' -or -not $obj.workload) { return $null }
    if ($levels -notcontains [string]$obj.workload.level) { return $null }

    $built = @{}
    foreach ($sec in $sections) {
        $clean = @()
        foreach ($it in @($obj.$sec)) {
            if (-not $it -or ($it -isnot [pscustomobject])) { return $null }
            $text = [string]$it.text
            if ([string]::IsNullOrWhiteSpace($text)) { return $null }
            if ($text.Length -gt $maxChars) { return $null }
            $st = [string]$it.sourceType; $sid = [string]$it.sourceId
            if ($types -notcontains $st) { return $null }
            $conf = 0.7; try { $conf = [double]$it.confidence } catch { $conf = 0.7 }
            $pri = 5; try { $pri = [int]$it.priority } catch { $pri = 5 }
            $reqAppr = $false; try { $reqAppr = [bool]$it.requiresApproval } catch { $reqAppr = $false }
            $pa = $null
            if (($it.PSObject.Properties.Name -contains 'proposedAction') -and $it.proposedAction) {
                $atype = [string]$it.proposedAction.type
                if ($actionTypes -notcontains $atype) { return $null }   # fabricated action -> whole reject
                $pa = New-DailyPlanAction -Type $atype -Title ([string]$it.proposedAction.title) -Detail ([string]$it.proposedAction.detail)
                $reqAppr = $true
            }
            $clean += (New-DailyPlanItem -Text $text -SourceType $st -SourceId $sid -Reason ([string]$it.reason) -Priority $pri -Confidence $conf -RequiresApproval $reqAppr -ProposedAction $pa)
        }
        $built[$sec] = $clean
    }
    $clar = @(); foreach ($c in @($obj.clarifications)) { if ($c) { $clar += [string]$c } }

    $model = New-EmptyDailyPlan -Engine 'claude-understanding' -RequestId '' -ContextVersion ([string]$PlanSources.contextVersion)
    foreach ($sec in $sections) { $model.$sec = @($built[$sec]) }
    $model.clarifications = @($clar)
    $model.workload = [pscustomobject]@{ level = [string]$obj.workload.level; reason = [string]$obj.workload.reason }
    return $model
}

# Portable Daily Plan work: call (or mock), parse, ground, return a plain result.
function Invoke-ClaudePlanCompose {
    param($Request)
    $ps = $Request.input
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $raw = $null
    try {
        if ($null -ne $script:ClaudePlanCallOverride) { $raw = & $script:ClaudePlanCallOverride $ps }
        else {
            if (-not (Get-Command Get-ClaudeConfig -ErrorAction SilentlyContinue) -or -not (Get-Command Invoke-ClaudeApi -ErrorAction SilentlyContinue)) {
                $sw.Stop(); return @{ ok = $false; reasonCode = 'unavailable'; fallbackReason = 'not-configured'; errorClass = 'not-configured'; durationMs = $sw.ElapsedMilliseconds; itemCount = 0 }
            }
            $cfg = Get-ClaudeConfig
            if (-not $cfg.configured) { $sw.Stop(); return @{ ok = $false; reasonCode = 'unavailable'; fallbackReason = 'not-configured'; errorClass = 'not-configured'; durationMs = $sw.ElapsedMilliseconds; itemCount = 0 } }
            $exCfg = [pscustomobject]@{ apiKey = $cfg.apiKey; model = $cfg.model; endpoint = $cfg.endpoint; apiVersion = $cfg.apiVersion; maxTokens = ([int][math]::Max([int]$cfg.maxTokens, $script:ClaudeUnderstandingMaxTokens)); configured = $cfg.configured }
            $raw = Invoke-ClaudeApi -System (Get-ClaudePlanSystemPrompt) -Messages @(@{ role = 'user'; content = (Get-ClaudePlanUserContent -PlanSources $ps) }) -Config $exCfg
        }
    }
    catch {
        $sw.Stop()
        $class = 'network-error'
        if (Get-Command Get-ClaudeErrorInfo -ErrorAction SilentlyContinue) { try { $class = [string](Get-ClaudeErrorInfo $_).class } catch { $class = 'network-error' } }
        return @{ ok = $false; reasonCode = 'provider-error'; fallbackReason = $class; errorClass = $class; durationMs = $sw.ElapsedMilliseconds; itemCount = 0 }
    }
    if ([string]::IsNullOrWhiteSpace([string]$raw)) { $sw.Stop(); return @{ ok = $false; reasonCode = 'invalid-output'; fallbackReason = 'empty'; errorClass = 'empty'; durationMs = $sw.ElapsedMilliseconds; itemCount = 0 } }
    $plan = ConvertFrom-ClaudePlan -RawText ([string]$raw) -PlanSources $ps
    if (-not $plan) { $sw.Stop(); return @{ ok = $false; reasonCode = 'invalid-output'; fallbackReason = 'malformed'; errorClass = 'malformed'; durationMs = $sw.ElapsedMilliseconds; itemCount = 0 } }
    # driver-side grounding sweep (truthful fallbackReason; the kernel validator is
    # still the authority and re-checks everything). Mirrors the kernel gates: source
    # membership, text-fact grounding (Epic 14A), and completed-action claims - so the
    # UI's fallbackReason is 'grounding' rather than a generic 'invalid-output'.
    $count = 0
    foreach ($sec in @('topOutcomes', 'protect', 'followUps', 'canWait', 'recommendations')) {
        foreach ($it in @($plan.$sec)) {
            if (-not $it) { continue }
            $count++
            if (Get-Command Find-DailyPlanSource -ErrorAction SilentlyContinue) {
                $srcEntry = Find-DailyPlanSource -PlanSources $ps -SourceType ([string]$it.sourceType) -SourceId ([string]$it.sourceId)
                if (-not $srcEntry) {
                    $sw.Stop(); return @{ ok = $false; reasonCode = 'invalid-output'; fallbackReason = 'grounding'; errorClass = 'grounding'; durationMs = $sw.ElapsedMilliseconds; itemCount = 0 }
                }
                if (Get-Command Test-DailyPlanItemFacts -ErrorAction SilentlyContinue) {
                    if (-not (Test-DailyPlanItemFacts -Text ([string]$it.text) -Reason ([string]$it.reason) -SourceEntry $srcEntry).ok) {
                        $sw.Stop(); return @{ ok = $false; reasonCode = 'invalid-output'; fallbackReason = 'grounding'; errorClass = 'grounding'; durationMs = $sw.ElapsedMilliseconds; itemCount = 0 }
                    }
                }
            }
            if (Get-Command Test-DailyPlanActionClaim -ErrorAction SilentlyContinue) {
                if ((Test-DailyPlanActionClaim -Text ([string]$it.text)) -or (Test-DailyPlanActionClaim -Text ([string]$it.reason))) {
                    $sw.Stop(); return @{ ok = $false; reasonCode = 'invalid-output'; fallbackReason = 'grounding'; errorClass = 'grounding'; durationMs = $sw.ElapsedMilliseconds; itemCount = 0 }
                }
            }
        }
    }
    $sw.Stop()
    return @{ ok = $true; reasonCode = 'ok'; output = $plan; confidence = 0.85; clarifications = @($plan.clarifications); fallbackReason = ''; errorClass = ''; durationMs = $sw.ElapsedMilliseconds; itemCount = $count }
}

# The dispatcher: one entry, routes by task. Same for inline and bounded paths.
function Invoke-ClaudeReasoning {
    param($Request)
    switch ([string]$Request.taskId) {
        'understanding.extract' { return (Invoke-ClaudeUnderstandingExtraction -Request $Request) }
        'briefing.compose' { return (Invoke-ClaudePlanCompose -Request $Request) }
        default { return @{ ok = $false; reasonCode = 'provider-error'; fallbackReason = 'unsupported-task'; errorClass = 'unsupported-task'; durationMs = 0; itemCount = 0 } }
    }
}

# ---- the driver object ------------------------------------------------
$script:ClaudeUnderstandingProvider = [pscustomobject]@{
    name        = $script:ClaudeUnderstandingId
    description = 'The Claude reasoning driver. Serves understanding.extract and briefing.compose. Configured + task-scoped consent only. Bounded; local floor on any failure.'
    isFloor     = $false
    priority    = 10
    bounded     = $true
    supports    = { param($TaskId) return ($TaskId -eq 'understanding.extract' -or $TaskId -eq 'briefing.compose') }
    # coarse (task-agnostic) availability, kept for any non-task-aware caller.
    isAvailable = { return (Test-ClaudeUnderstandingConfigured) -and ((Test-ExtractionConsent) -or (Get-Command Test-ExecutiveReasoningConsent -ErrorAction SilentlyContinue) -and (Test-ExecutiveReasoningConsent)) }
    # TASK-AWARE availability: consent is scoped to the task. This runs at ROUTING
    # time on the caller's thread - so a task whose consent is not granted is never a
    # candidate, and no data is prepared or sent (the bounded worker never starts).
    isAvailableForTask = {
        param($TaskId)
        if (-not (Test-ClaudeUnderstandingConfigured)) { return $false }
        if (-not (Get-Command Test-TaskConsent -ErrorAction SilentlyContinue)) { return $false }
        try { return [bool](Test-TaskConsent -TaskId $TaskId) } catch { return $false }
    }
    # The portable, self-contained work the kernel runs in a bounded runspace
    # (stage 3). It closes over NOTHING - it loads its own modules from $DashRoot,
    # rebuilds the request from JSON, and returns a PLAIN result carrying the
    # requestId so a late/stale completion can be discarded. It reuses the SAME
    # Invoke-ClaudeUnderstandingExtraction that the inline invoke uses, so the
    # driver's reasoning is identical whether run inline (tests) or bounded (prod).
    boundedWork = {
        param($RequestJson, $DashRoot)
        $ErrorActionPreference = 'Stop'
        try {
            if (-not $global:GiokReasoningWorkerLoaded) {
                $core = Join-Path $DashRoot 'core'; $prov = Join-Path $DashRoot 'providers'
                # a load-time stub so claude-provider's Register-TonyProvider is a no-op
                # in this bare runspace; the raw Invoke-ClaudeApi primitive needs none of
                # the chat contract.
                if (-not (Get-Command Register-TonyProvider -ErrorAction SilentlyContinue)) { function global:Register-TonyProvider { param($Provider) } }
                foreach ($m in @('reasoning-layer', 'first-conversation', 'identity', 'understanding-engine', 'reasoning-local', 'daily-plan', 'reasoning-claude')) { . (Join-Path $core ("$m.ps1")) }
                . (Join-Path $prov 'claude-provider.ps1')
                $global:GiokReasoningWorkerLoaded = $true
            }
            $req = $RequestJson | ConvertFrom-Json
            $res = Invoke-ClaudeReasoning -Request $req
            $res['requestId'] = [string]$req.requestId
            return $res
        }
        catch {
            return @{ ok = $false; reasonCode = 'provider-error'; fallbackReason = 'worker-error'; requestId = '' }
        }
    }
    invoke      = {
        param($Request)
        $res = Invoke-ClaudeReasoning -Request $Request
        Set-ClaudeUnderstandingAttempt (New-ClaudeUnderstandingAttempt -RequestId ([string]$Request.requestId) -Task ([string]$Request.taskId) `
                -Status $(if ($res.ok) { 'ok' } else { 'fallback' }) -DurationMs ([int]$res.durationMs) `
                -ErrorClass ([string]$res.errorClass) -ItemCount ([int]$res.itemCount) -FallbackReason ([string]$res.fallbackReason))
        if (Get-Command Write-TonyDiag -ErrorAction SilentlyContinue) {
            try { Write-TonyDiag -Level 'info' -Source 'reasoning-claude' -Message ('{0} {1} class={2} items={3} {4}ms' -f ([string]$Request.taskId), $(if ($res.ok) { 'ok' } else { 'fallback' }), $res.errorClass, $res.itemCount, $res.durationMs) } catch { }
        }
        if (-not $res.ok) {
            # honest failure -> the kernel discards this and falls to the floor.
            return (New-ReasoningResult -TaskId $Request.taskId -Ok $false -Output $null -Confidence 0.0 `
                    -Engine $script:ClaudeUnderstandingId -ProviderName $script:ClaudeUnderstandingId -ReasonCode ([string]$res.reasonCode))
        }
        # attribution is left to the kernel; engine here is a placeholder it overwrites.
        return (New-ReasoningResult -TaskId $Request.taskId -Ok $true -Output $res.output -Confidence ([double]$res.confidence) `
                -Engine $script:ClaudeUnderstandingId -ProviderName $script:ClaudeUnderstandingId -ReasonCode 'ok' `
                -Clarifications @($res.clarifications))
    }
}

if (Get-Command Register-ReasoningProvider -ErrorAction SilentlyContinue) {
    Register-ReasoningProvider -Provider $script:ClaudeUnderstandingProvider
}
