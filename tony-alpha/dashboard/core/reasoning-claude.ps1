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
# A raw response larger than this is malfunctioning; rejected before parsing.
$script:ClaudeUnderstandingMaxResponseBytes = 200000

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
    param([string]$RequestId, [string]$Status, [int]$DurationMs = 0, [string]$ErrorClass = '', [int]$ItemCount = 0, [string]$FallbackReason = '')
    return [pscustomobject]@{
        provider = $script:ClaudeUnderstandingId; task = 'understanding.extract'
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
            $sys = Get-ClaudeExtractionSystemPrompt
            $usr = Get-ClaudeExtractionUserContent -State $state
            $raw = Invoke-ClaudeApi -System $sys -Messages @(@{ role = 'user'; content = $usr }) -Config $cfg
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

# ---- the driver object ------------------------------------------------
$script:ClaudeUnderstandingProvider = [pscustomobject]@{
    name        = $script:ClaudeUnderstandingId
    description = 'Organizes onboarding answers into the Understanding Model via Claude. Configured + consented only. Bounded; local floor on any failure.'
    isFloor     = $false
    priority    = 10
    bounded     = $true
    supports    = { param($TaskId) return ($TaskId -eq 'understanding.extract') }
    isAvailable = { return (Test-ClaudeUnderstandingAvailable) }
    invoke      = {
        param($Request)
        $res = Invoke-ClaudeUnderstandingExtraction -Request $Request
        Set-ClaudeUnderstandingAttempt (New-ClaudeUnderstandingAttempt -RequestId ([string]$Request.requestId) `
                -Status $(if ($res.ok) { 'ok' } else { 'fallback' }) -DurationMs ([int]$res.durationMs) `
                -ErrorClass ([string]$res.errorClass) -ItemCount ([int]$res.itemCount) -FallbackReason ([string]$res.fallbackReason))
        if (Get-Command Write-TonyDiag -ErrorAction SilentlyContinue) {
            try { Write-TonyDiag -Level 'info' -Source 'reasoning-claude' -Message ('understanding.extract {0} class={1} items={2} {3}ms' -f $(if ($res.ok) { 'ok' } else { 'fallback' }), $res.errorClass, $res.itemCount, $res.durationMs) } catch { }
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
