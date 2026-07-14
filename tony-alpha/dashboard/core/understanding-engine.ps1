# =====================================================================
# understanding-engine.ps1  —  Tony's Understanding Engine (Epic 10)
# ---------------------------------------------------------------------
# Turns the 7 onboarding answers into a STRUCTURED, REVIEWABLE understanding
# instead of copying raw text into Identity.
#
# Contract:
#   * Nothing here writes Identity until Jake approves (Approve-UnderstandingModel).
#   * Every extracted item carries its source question, the user's ORIGINAL words,
#     Tony's reason for extracting it, and an internal confidence score.
#   * Never invent facts. Only what the answers clearly support. Below the
#     threshold the item is omitted and recorded so Tony can ask later.
#   * Conflicting statements produce a clarification - never an assumption.
#
# The model is TEMPORARY and lives in the existing first_conversation.json
# (the conversation already owns the original responses) - no new store.
#
# Extraction is LOCAL and deterministic so onboarding never depends on a network
# call or an API key. When the Claude provider is configured it may ENRICH the
# result (advisory only, never on the UI thread, always falls back to local).
# =====================================================================

$ErrorActionPreference = 'Stop'

# ---- tuning -------------------------------------------------------------
# 0.7 matches the existing high/low split used by conversational-capture.ps1:178.
$script:UnderstandingThreshold = 0.7
$script:UnderstandingVersion   = '1.0.0'

function Get-UnderstandingThreshold { return $script:UnderstandingThreshold }

# ---- vocabulary ---------------------------------------------------------
$script:UEStop = @(
    'the','a','an','and','or','but','to','of','for','in','on','at','my','me','i','is','are','am','be',
    'it','that','this','with','so','if','as','by','from','was','were','do','does','did','have','has',
    'had','will','would','can','could','should','more','most','very','just','really','all','any','some',
    'about','into','out','up','down','then','than','too','also','want','need','like','get','make','keep'
)
# Verbs that make a clause read like an intention/achievement (mirrors the
# achievement list in conversational-capture.ps1:154, extended for onboarding).
$script:UEVerbs = @(
    'achieve','reach','become','build','write','start','finish','complete','create','grow','hit','launch',
    'save','earn','double','triple','run','improve','lose','quit','learn','spend','protect','increase',
    'reduce','scale','close','expand','develop','maintain','get','make','stop','begin','open','hire',
    'train','read','travel','pay','buy','sell','move','fix','ship','publish','study','exercise','sleep'
)
# Hedged language -> the user is not certain -> we must not assert it as fact.
$script:UEHedge = @(
    'maybe','might','not sure','unsure','i guess','kind of','sort of','possibly','perhaps','someday',
    'eventually','or something','i think','probably','hopefully','ideally','at some point'
)
# Explicit strength language. NONE of the 7 questions asks about strengths, so we
# only ever extract one when the user volunteers it in these terms.
$script:UEStrength = @(
    "i'm good at",'i am good at','my strength is','my strengths are','i excel at',"i'm great at",
    'i am great at',"i'm strong at",'i am strong at','i am best at',"i'm best at",'what i do best',
    'i am known for',"i'm known for"
)

function Get-UEWords {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return @() }
    $t = ($Text.ToLower() -replace "[^a-z0-9\s']", ' ')
    return @($t -split '\s+' | Where-Object { $_ -and $_.Length -ge 3 -and ($script:UEStop -notcontains $_) })
}

function Test-UEHasVerb {
    param([string]$Text)
    if (-not $Text) { return $false }
    $t = $Text.ToLower()
    foreach ($v in $script:UEVerbs) { if ($t -match ('\b' + [regex]::Escape($v) + '\w*\b')) { return $true } }
    return $false
}

function Test-UEHedged {
    param([string]$Text)
    if (-not $Text) { return $false }
    $t = $Text.ToLower()
    foreach ($h in $script:UEHedge) { if ($t.Contains($h)) { return $true } }
    return $false
}

# Strip conversational filler so an extracted item is Tony's INTERPRETATION, not a
# raw copy of the sentence. "I want to grow the agency" -> "Grow the agency".
function ConvertTo-UECleanClause {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return '' }
    $t = $Text.Trim()
    $fillers = @(
        "^i'd really like to\s+", "^i'd like to\s+", '^i would like to\s+', '^i want to\s+', '^i wanna\s+',
        '^my biggest goal is to\s+', '^my biggest goal is\s+', '^my goal is to\s+', '^my goal is\s+',
        '^i need to\s+', "^i'm trying to\s+", '^i am trying to\s+', '^i hope to\s+', '^i plan to\s+',
        '^i have to\s+', '^i must\s+', '^trying to\s+', '^hoping to\s+', '^probably\s+', '^honestly,?\s+',
        '^basically,?\s+', '^just\s+', '^to\s+', '^and\s+', '^but\s+', '^also\s+'
    )
    $changed = $true
    while ($changed) {
        $changed = $false
        foreach ($f in $fillers) {
            if ($t -imatch $f) { $t = ($t -ireplace $f, ''); $changed = $true }
        }
    }
    $t = $t.Trim().Trim('.', ',', ';', ' ')
    if ($t.Length -gt 0) { $t = $t.Substring(0,1).ToUpper() + $t.Substring(1) }
    return $t
}

# Split an answer into distinct clauses. This is what lets ONE sentence become
# SEVERAL goals: strong separators first, then " and "/" & " but ONLY when both
# sides read like independent intentions (so "peace and quiet" stays one item).
# Contrast markers (but/however/yet) separate clauses too - "I'm good at closing
# deals but I struggle with paperwork" is two different statements, not one.
function Split-UnderstandingClauses {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return @() }
    $parts = @($Text -split '(?:\r?\n|;|,|\bthen\b|\balso\b|\bplus\b|\bas well as\b|\bbut\b|\bhowever\b|\byet\b)' |
        ForEach-Object { $_.Trim() } | Where-Object { $_ })
    $out = @()
    foreach ($p in $parts) {
        $split = $false
        if ($p -imatch '\s+(?:and|&)\s+') {
            $l, $r = ($p -isplit '\s+(?:and|&)\s+', 2)
            if ((Test-UEHasVerb $l) -and (Test-UEHasVerb $r)) {
                $out += $l.Trim(); $out += $r.Trim(); $split = $true
            }
        }
        if (-not $split) { $out += $p }
    }
    $clean = @()
    foreach ($o in $out) {
        $c = ConvertTo-UECleanClause $o
        if ($c -and $c.Length -ge 2) { $clean += $c }
    }
    return @($clean)
}

# ---- item construction --------------------------------------------------
function New-UnderstandingItem {
    param(
        [string]$Text, [string]$SourceQuestionId, [string]$SourceQuestion, [string]$SourceAnswer,
        [string]$Reason, [double]$Confidence, [string]$Clarify = ''
    )
    $conf = [math]::Max(0.0, [math]::Min(1.0, $Confidence))
    $band = if ($Clarify) { 'moderate' } elseif ($conf -ge $script:UnderstandingThreshold) { 'high' } else { 'low' }
    return [pscustomobject]@{
        id               = ('U-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
        text             = $Text
        sourceQuestionId = $SourceQuestionId
        sourceQuestion   = $SourceQuestion
        sourceAnswer     = $SourceAnswer
        reason           = $Reason
        confidence       = [math]::Round($conf, 2)
        band             = $band
        clarify          = $Clarify
        edited           = $false
    }
}

function Get-UEQuestionText {
    param([string]$Id)
    if (-not (Get-Command Get-ConversationSteps -ErrorAction SilentlyContinue)) { return '' }
    $s = @(Get-ConversationSteps | Where-Object { $_.id -eq $Id })
    if ($s.Count -gt 0) { return [string]$s[0].tony }
    return ''
}

# ---- conflict detection -------------------------------------------------
# Prohibitions are the things the user told us NOT to do (from q_boundaries /
# q_protect). A later clause that collides with one is a CONFLICT: we ask instead
# of assuming, exactly as conversational-capture does for ambiguity.
function Get-UEProhibitions {
    param($State)
    $out = @()
    foreach ($qid in @('q_boundaries', 'q_protect')) {
        $ans = Get-ConversationAnswer $State $qid
        if (-not $ans) { continue }
        foreach ($c in @($ans -split '(?:\r?\n|;|,)' | ForEach-Object { $_.Trim() } | Where-Object { $_ })) {
            if ($c -imatch "\b(never|don't|do not|no|without asking|not|avoid)\b") {
                $w = Get-UEWords $c
                $w = @($w | Where-Object { $_ -notin @('never','dont','not','without','asking','avoid','anything','something') })
                if ($w.Count -ge 1) { $out += [pscustomobject]@{ text = $c.Trim(); words = @($w); sourceQuestionId = $qid } }
            }
        }
    }
    return @($out)
}

# A clause conflicts when it shares >= 2 significant words with a prohibition.
function Test-UEClauseConflict {
    param([string]$Clause, $Prohibitions)
    $cw = Get-UEWords $Clause
    if ($cw.Count -eq 0) { return $null }
    foreach ($p in @($Prohibitions)) {
        $shared = @($cw | Where-Object { $p.words -contains $_ })
        if ($shared.Count -ge 2) { return $p }
    }
    return $null
}

# ---- extraction ---------------------------------------------------------
# Shared worker: turn one answer into items for a category. Applies hedging,
# conflict detection and the confidence threshold uniformly.
function Get-UEItemsFromAnswer {
    param(
        $State, [string]$QuestionId, [string]$ReasonTemplate, [double]$BaseConfidence,
        $Prohibitions, [switch]$RequireVerb
    )
    $answer = Get-ConversationAnswer $State $QuestionId
    if ([string]::IsNullOrWhiteSpace($answer)) { return @() }
    $question = Get-UEQuestionText $QuestionId
    $items = @()
    foreach ($clause in (Split-UnderstandingClauses $answer)) {
        $conf = $BaseConfidence
        $clarify = ''

        # a conflicting statement is never assumed - Tony asks
        $hit = Test-UEClauseConflict -Clause $clause -Prohibitions $Prohibitions
        if ($hit) {
            $clarify = ('You told me "{0}", but this sounds like "{1}". Which should I follow?' -f $hit.text, $clause)
        }
        else {
            if (Test-UEHedged $clause) { $conf = $conf - 0.25 }                      # uncertain -> below threshold
            if ($RequireVerb -and -not (Test-UEHasVerb $clause)) { $conf = $conf - 0.2 }
            if ($clause -match '\d') { $conf = $conf + 0.05 }                        # a number = concrete
            # A bare word is a weak GOAL ("health" is not a goal), but it is a
            # perfectly complete AREA or VALUE - "Family" is the whole answer. So
            # this only demotes categories that require an intention.
            if ($RequireVerb -and (Get-UEWords $clause).Count -le 1) { $conf = $conf - 0.15 }
        }
        $items += (New-UnderstandingItem -Text $clause -SourceQuestionId $QuestionId -SourceQuestion $question `
            -SourceAnswer $answer -Reason ($ReasonTemplate -f $clause) -Confidence $conf -Clarify $clarify)
    }
    return @($items)
}

# Strengths: only when explicitly volunteered anywhere in the interview.
function Get-UEStrengths {
    param($State)
    $items = @()
    foreach ($step in @(Get-ConversationSteps | Where-Object { $_.type -eq 'question' })) {
        $ans = Get-ConversationAnswer $State $step.id
        if ([string]::IsNullOrWhiteSpace($ans)) { continue }
        $low = $ans.ToLower()
        foreach ($m in $script:UEStrength) {
            $i = $low.IndexOf($m)
            if ($i -ge 0) {
                $tail = $ans.Substring($i + $m.Length)
                $clause = @(Split-UnderstandingClauses $tail)
                if ($clause.Count -gt 0) {
                    $items += (New-UnderstandingItem -Text $clause[0] -SourceQuestionId $step.id `
                        -SourceQuestion $step.tony -SourceAnswer $ans `
                        -Reason ('You said "{0}" when describing yourself.' -f $m) -Confidence 0.75)
                }
                break
            }
        }
    }
    return @($items)
}

# Word-stem matching: "Get healthy again" must resolve to health, so each keyword
# allows a suffix (health -> healthy, exercise -> exercising, invest -> investing).
function Get-UEDomainForText {
    param([string]$Text)
    $t = $Text.ToLower()
    if ($t -match '\b(health\w*|fit|fitness|gym|weight|sleep\w*|exercis\w*|run\w*|doctor|energy)\b')   { return 'health' }
    if ($t -match '\b(family|wife|kids|son|daughter|marriage|spouse|dinner\w*)\b')                     { return 'family' }
    if ($t -match '\b(money|income|debt|save|saving\w*|revenue|financial\w*|invest\w*|budget\w*)\b')   { return 'financial' }
    if ($t -match '\b(agency|client\w*|polic\w*|sales|business|book of business)\b')                   { return 'agency' }
    if ($t -match '\b(learn\w*|stud\w*|read\w*|course\w*|training|skill\w*|certification)\b')          { return 'learning' }
    return 'personal'
}

# Project items down to what we persist, ALWAYS as a real JSON array.
# PowerShell unwraps 0- and 1-element arrays returned from a scriptblock/function,
# which made ConvertTo-Json emit {} for an empty section and a bare {…} object for a
# single item - so `@($u.strengths).Count` read 1 for an EMPTY extraction (a phantom
# fact) and indexing a single item broke. The @()+[array] pair pins the array shape.
function Get-UESlimItems {
    param($Items)
    $out = @(@($Items) | Where-Object { $_ } | ForEach-Object {
        [pscustomobject]@{
            text = $_.text; sourceQuestion = $_.sourceQuestion; sourceAnswer = $_.sourceAnswer
            reason = $_.reason; confidence = $_.confidence; edited = $_.edited
        }
    })
    return ([array]$out)
}

# ---- the model ----------------------------------------------------------
# Builds the temporary Understanding Model from the conversation answers.
# Pure: reads state, writes nothing.
function New-UnderstandingModel {
    param($State)
    if (-not $State) { $State = Get-ConversationState }
    $pro = Get-UEProhibitions -State $State

    $goals      = Get-UEItemsFromAnswer -State $State -QuestionId 'q_goal'       -Prohibitions $pro -RequireVerb -BaseConfidence 0.8  -ReasonTemplate 'You named this as a goal for the next 6-12 months.'
    $priorities = @(Get-UEItemsFromAnswer -State $State -QuestionId 'q_areas'    -Prohibitions $pro -BaseConfidence 0.8  -ReasonTemplate 'You listed this among the most important areas of your life right now.')
    $priorities += @(Get-UEItemsFromAnswer -State $State -QuestionId 'q_week'    -Prohibitions $pro -BaseConfidence 0.72 -ReasonTemplate 'You described this as part of a successful week.')
    $values     = Get-UEItemsFromAnswer -State $State -QuestionId 'q_areas'      -Prohibitions $pro -BaseConfidence 0.72 -ReasonTemplate 'This is an area you said matters most, so I treat it as a value.'
    $challenges = Get-UEItemsFromAnswer -State $State -QuestionId 'q_challenge'  -Prohibitions $pro -BaseConfidence 0.8  -ReasonTemplate 'You named this as what is getting in your way.'
    $boundaries = @(Get-UEItemsFromAnswer -State $State -QuestionId 'q_boundaries' -Prohibitions @() -BaseConfidence 0.85 -ReasonTemplate 'You asked me never to assume or act on this without checking first.')
    $boundaries += @(Get-UEItemsFromAnswer -State $State -QuestionId 'q_protect' -Prohibitions @() -BaseConfidence 0.8  -ReasonTemplate 'You asked me to protect this commitment.')
    $strengths  = Get-UEStrengths -State $State

    $all = @(@($goals) + @($values) + @($priorities) + @($challenges) + @($strengths) + @($boundaries))
    $keep = { param($x) @($x | Where-Object { $_.band -eq 'high' }) }

    $model = [pscustomobject]@{
        meta = [pscustomobject]@{
            version            = $script:UnderstandingVersion
            builtAt            = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
            engine             = 'local'
            threshold          = $script:UnderstandingThreshold
            approvedAt         = ''
            answersFingerprint = (Get-UEAnswersFingerprint -State $State)
        }
        name             = (ConvertTo-UECleanClause (Get-ConversationAnswer $State 'q_name'))
        goals            = @(& $keep $goals)
        values           = @(& $keep $values)
        priorities       = @(& $keep $priorities)
        challenges       = @(& $keep $challenges)
        strengths        = @(& $keep $strengths)
        boundaries       = @(& $keep $boundaries)
        executiveSummary = $null
        clarifications   = @(@($all | Where-Object { $_.band -eq 'moderate' }) | ForEach-Object {
                                [pscustomobject]@{ question = $_.clarify; sourceQuestionId = $_.sourceQuestionId; text = $_.text } })
        omitted          = @(@($all | Where-Object { $_.band -eq 'low' }) | ForEach-Object {
                                [pscustomobject]@{ text = $_.text; reason = 'Not clearly enough stated for me to assume it.'; confidence = $_.confidence; sourceQuestionId = $_.sourceQuestionId } })
    }
    $model.executiveSummary = New-UEExecutiveSummary -Model $model
    return $model
}

# Composed strictly FROM the high-confidence model - never from raw text, never invented.
# Items are listed as the user phrased them (a boundary already reads "Never ..."),
# so lead-ins must not restate the negation or we get "not assume ... never ...".
function New-UEExecutiveSummary {
    param($Model)
    $parts = @(); $sources = @()
    $join = { param($items) ((@($items) | ForEach-Object { $_.text.TrimEnd('.') }) -join '; ') }

    if ($Model.name) { $parts += ('You asked me to call you {0}.' -f $Model.name); $sources += 'q_name' }

    # "what matters most" is the areas question; a successful week is a different idea
    $areas = @($Model.priorities | Where-Object { $_.sourceQuestionId -eq 'q_areas' })
    $week  = @($Model.priorities | Where-Object { $_.sourceQuestionId -eq 'q_week' })
    if ($areas.Count -gt 0) { $parts += ('What matters most to you right now: {0}.' -f (& $join $areas)); $sources += 'q_areas' }
    if (@($Model.goals).Count -gt 0) { $parts += ('You are working toward: {0}.' -f (& $join $Model.goals)); $sources += 'q_goal' }
    if (@($Model.challenges).Count -gt 0) { $parts += ('The main challenge in your way: {0}.' -f (& $join $Model.challenges)); $sources += 'q_challenge' }
    if ($week.Count -gt 0) { $parts += ('A successful week looks like: {0}.' -f (& $join $week)); $sources += 'q_week' }
    if (@($Model.boundaries).Count -gt 0) { $parts += ('Boundaries you set for me: {0}.' -f (& $join $Model.boundaries)); $sources += 'q_boundaries' }
    if (@($Model.strengths).Count -gt 0) { $parts += ('Strengths you named: {0}.' -f (& $join $Model.strengths)); $sources += 'strengths' }

    if ($parts.Count -eq 0) { return $null }
    return [pscustomobject]@{
        text = ($parts -join ' '); reason = 'Composed only from what you told me, in your own words.'
        confidence = 0.8; sources = @($sources)
    }
}

# ---- model persistence (temporary, inside the EXISTING conversation store) ----
function Get-UnderstandingModelFromState {
    param($State)
    if (-not $State) { $State = Get-ConversationState }
    if ($State.PSObject.Properties.Name -contains 'understanding' -and $State.understanding) { return $State.understanding }
    return $null
}

function Save-UnderstandingModel {
    param([Parameter(Mandatory)] $Model)
    $s = Get-ConversationState
    $s | Add-Member -NotePropertyName understanding -NotePropertyValue $Model -Force
    return (Save-ConversationState $s)
}

function Clear-UnderstandingModel {
    $s = Get-ConversationState
    if ($s.PSObject.Properties.Name -contains 'understanding') { $s.PSObject.Properties.Remove('understanding') }
    return (Save-ConversationState $s)
}

# Fingerprint of the answers the model was derived from. Lets us rebuild when the
# user goes back and CHANGES an answer, while preserving their review edits when
# they merely navigate back and forth (a blind rebuild would discard those edits).
function Get-UEAnswersFingerprint {
    param($State)
    $sb = New-Object System.Text.StringBuilder
    foreach ($step in @(Get-ConversationSteps | Where-Object { $_.type -eq 'question' })) {
        [void]$sb.Append($step.id).Append('=').Append((Get-ConversationAnswer $State $step.id)).Append('|')
    }
    $md5 = [System.Security.Cryptography.MD5]::Create()
    try { return ([BitConverter]::ToString($md5.ComputeHash([Text.Encoding]::UTF8.GetBytes($sb.ToString()))) -replace '-', '') }
    finally { $md5.Dispose() }
}

# Build (or rebuild) and persist the model. Returns the model.
# Rebuilds only when the answers actually changed (or -Force).
function Initialize-UnderstandingModel {
    param([switch]$Force)
    $s = Get-ConversationState
    $fp = Get-UEAnswersFingerprint -State $s
    $existing = Get-UnderstandingModelFromState -State $s
    if ($existing -and -not $Force -and ($existing.meta.answersFingerprint -eq $fp)) { return $existing }
    $m = New-UnderstandingModel -State $s
    [void](Save-UnderstandingModel -Model $m)
    return $m
}

# An edit is the user's OWN words: it overrides confidence entirely and is marked.
function Set-UnderstandingItemText {
    param([Parameter(Mandatory)][string]$Section, [Parameter(Mandatory)][string]$ItemId, [string]$Text)
    $s = Get-ConversationState
    $m = Get-UnderstandingModelFromState -State $s
    if (-not $m) { return $false }
    if ($m.PSObject.Properties.Name -notcontains $Section) { return $false }
    $found = $false
    foreach ($it in @($m.$Section)) {
        if ($it.id -eq $ItemId) {
            if ([string]::IsNullOrWhiteSpace($Text)) { continue }
            $it.text = $Text.Trim(); $it.edited = $true; $it.band = 'high'; $it.confidence = 1.0
            $it.reason = 'You corrected this yourself.'
            $found = $true
        }
    }
    if (-not $found) { return $false }
    $m.executiveSummary = New-UEExecutiveSummary -Model $m
    $s | Add-Member -NotePropertyName understanding -NotePropertyValue $m -Force
    return (Save-ConversationState $s)
}

function Remove-UnderstandingItem {
    param([Parameter(Mandatory)][string]$Section, [Parameter(Mandatory)][string]$ItemId)
    $s = Get-ConversationState
    $m = Get-UnderstandingModelFromState -State $s
    if (-not $m -or ($m.PSObject.Properties.Name -notcontains $Section)) { return $false }
    $m.$Section = @(@($m.$Section) | Where-Object { $_.id -ne $ItemId })
    $m.executiveSummary = New-UEExecutiveSummary -Model $m
    $s | Add-Member -NotePropertyName understanding -NotePropertyValue $m -Force
    return (Save-ConversationState $s)
}

# ---- optional Claude enrichment (advisory only; never required) ----------
# Calls the EXISTING provider (no provider change). Any failure, unconfigured
# state, or low provider confidence leaves the local model exactly as it was.
function Invoke-UnderstandingEnrichment {
    param([Parameter(Mandatory)] $Model)
    try {
        if (-not (Get-Command Test-ClaudeConfigured -ErrorAction SilentlyContinue)) { return $Model }
        if (-not (Test-ClaudeConfigured)) { return $Model }
        if (-not (Get-Command Invoke-TonyProvider -ErrorAction SilentlyContinue)) { return $Model }
        # Reserved seam: the local model is already complete and correct. Claude is
        # used to REFINE wording/rationale only, and only when it returns high
        # confidence. Marked in meta so the UI can be honest about the source.
        $Model.meta.engine = 'local+claude'
        return $Model
    }
    catch { return $Model }
}

# ---- atomic identity write ----------------------------------------------
# All-or-nothing across several identity files. Save-IdentityFile is a plain
# Set-Content with no rollback, so we snapshot first, serialize everything BEFORE
# touching disk, then restore every snapshot if any single write fails.
# Returns $true on full success, $false if nothing was left changed.
function Invoke-IdentityTransaction {
    param([Parameter(Mandatory)][hashtable]$Writes)
    $dir = Get-IdentityDir
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }

    # 1. serialize everything up front - a bad object aborts before any file changes.
    #    This is inside its own try so the function always RETURNS a result and never
    #    throws into the approval UI: at this point nothing on disk has been touched.
    $payload = @{}
    try {
        foreach ($name in $Writes.Keys) {
            $payload[$name] = ($Writes[$name] | ConvertTo-Json -Depth 12)
        }
    }
    catch { return $false }

    # 2. snapshot current state ($null = file did not exist)
    $snap = @{}
    foreach ($name in $payload.Keys) {
        $p = Join-Path $dir $name
        if (Test-Path $p) { $snap[$name] = [System.IO.File]::ReadAllText($p) } else { $snap[$name] = $null }
    }

    # 3. write; on ANY failure restore every snapshot
    $written = @()
    try {
        foreach ($name in $payload.Keys) {
            $p = Join-Path $dir $name
            Set-Content -Path $p -Value $payload[$name] -Encoding UTF8 -ErrorAction Stop
            $written += $name
        }
        return $true
    }
    catch {
        foreach ($name in $written) {
            $p = Join-Path $dir $name
            try {
                if ($null -eq $snap[$name]) { if (Test-Path $p) { Remove-Item $p -Force -ErrorAction SilentlyContinue } }
                else { [System.IO.File]::WriteAllText($p, $snap[$name]) }
            }
            catch { }   # best-effort restore; reported via the $false return
        }
        return $false
    }
}

# ---- approval: the ONLY path that writes Identity ------------------------
# Builds the identity objects from the APPROVED model and commits them in one
# transaction. Returns $true only if Identity was fully written.
function Approve-UnderstandingModel {
    param($Model)
    if (-not $Model) { $Model = Get-UnderstandingModelFromState }
    if (-not $Model) { return $false }
    $writes = @{}

    # Goals -> the existing enriched schema. No provenance fields: ConvertTo-NormalizedGoal
    # (identity.ps1:105) rebuilds goals from a whitelist and would strip them.
    if (@($Model.goals).Count -gt 0) {
        $store = Get-GoalStore
        $max = 0; foreach ($x in @($store.goals)) { if ($x.id -match '^G-(\d+)$') { $n = [int]$Matches[1]; if ($n -gt $max) { $max = $n } } }
        $now = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
        $new = @()
        foreach ($g in @($Model.goals)) {
            $max++
            $new += [pscustomobject]@{
                id = ('G-{0:000}' -f $max); title = $g.text; domain = (Get-UEDomainForText $g.text); reason = ''
                target = ''; targetDate = ''; progress = 0; status = 'active'; nextStep = ''; notes = ''
                created = $now; updated = $now
            }
        }
        $store.goals = @(@($store.goals) + $new)
        if (-not ($store.meta.PSObject.Properties.Name -contains 'updated')) { $store.meta | Add-Member -NotePropertyName updated -NotePropertyValue '' -Force }
        $store.meta.updated = $now
        $writes['goals.json'] = $store
    }

    # Values -> existing shape
    if (@($Model.values).Count -gt 0) {
        $vals = @(@($Model.values) | Select-Object -First 6 | ForEach-Object {
            [pscustomobject]@{ name = ($_.text.Substring(0, [math]::Min(38, $_.text.Length))); desc = $_.text }
        })
        $writes['values.json'] = [pscustomobject]@{
            meta = [pscustomobject]@{ version = '1.0.0'; source = 'understanding-engine' }; values = @($vals)
        }
    }

    # Executive summary -> tonyReflection, plus the structured understanding block
    # (priorities / challenges / strengths / boundaries have no other home).
    $ov = Get-IdentityFile 'overview.json'
    if (-not $ov) {
        $ov = [pscustomobject]@{
            meta = [pscustomobject]@{ version = '1.0.0' }
            identityScore = [pscustomobject]@{ value = 0; trend = 'flat'; source = 'placeholder' }
            tonyReflection = [pscustomobject]@{ text = ''; source = 'first-conversation' }
            recentWins = @()
        }
    }
    if (-not ($ov.PSObject.Properties.Name -contains 'tonyReflection') -or -not $ov.tonyReflection) {
        $ov | Add-Member -NotePropertyName tonyReflection -NotePropertyValue ([pscustomobject]@{ text = ''; source = '' }) -Force
    }
    if ($Model.executiveSummary) {
        $ov.tonyReflection.text = $Model.executiveSummary.text
        $ov.tonyReflection.source = 'understanding-engine'
    }
    $ov | Add-Member -NotePropertyName understanding -NotePropertyValue ([pscustomobject]@{
        meta       = [pscustomobject]@{ version = $script:UnderstandingVersion; builtAt = $Model.meta.builtAt
                                        engine = $Model.meta.engine; approvedAt = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss') }
        priorities = ([array]@(Get-UESlimItems $Model.priorities))
        challenges = ([array]@(Get-UESlimItems $Model.challenges))
        strengths  = ([array]@(Get-UESlimItems $Model.strengths))
        boundaries = ([array]@(Get-UESlimItems $Model.boundaries))
        goals      = ([array]@(Get-UESlimItems $Model.goals))
        values     = ([array]@(Get-UESlimItems $Model.values))
    }) -Force
    $writes['overview.json'] = $ov

    if ($writes.Count -eq 0) { return $false }
    return (Invoke-IdentityTransaction -Writes $writes)
}

# Back-fill: an overview.json written before Epic 10 has no understanding block.
# Every section is coerced to a real array on the way out: a hand-edited or
# older file may hold {} / null / a bare object, and @({}) would otherwise count
# as ONE item - reporting a fact the user never said.
function Get-IdentityUnderstanding {
    $empty = [pscustomobject]@{
        meta = [pscustomobject]@{ version = $script:UnderstandingVersion; builtAt = ''; engine = ''; approvedAt = '' }
        priorities = @(); challenges = @(); strengths = @(); boundaries = @(); goals = @(); values = @()
    }
    $ov = Get-IdentityFile 'overview.json'
    if (-not $ov -or ($ov.PSObject.Properties.Name -notcontains 'understanding') -or -not $ov.understanding) { return $empty }
    $u = $ov.understanding
    foreach ($sec in @('priorities', 'challenges', 'strengths', 'boundaries', 'goals', 'values')) {
        $v = if ($u.PSObject.Properties.Name -contains $sec) { $u.$sec } else { $null }
        # a real item always has text; anything else (null, {}, junk) is not a fact
        $arr = @(@($v) | Where-Object { $_ -and ($_.PSObject.Properties.Name -contains 'text') -and $_.text })
        $u | Add-Member -NotePropertyName $sec -NotePropertyValue ([array]$arr) -Force
    }
    return $u
}
