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
    'train','read','travel','pay','buy','sell','move','fix','ship','publish','study','exercise','sleep',
    'take','give','find','keep','add','plan','set','call','email','meet','delegate','automate','system',
    'systemize','systematize','protect','book','handle','manage','deliver','lead','coach','mentor'
)
# Hedged language -> the user is not certain -> we must not assert it as fact.
# Tested against the RAW clause, before discourse markers are stripped (several
# hedges are also filler, e.g. "kind of" - strip first and we would lose the signal).
$script:UEHedge = @(
    'maybe','might','not sure','unsure','i guess','kind of','sort of','possibly','perhaps','someday',
    'eventually','or something','i think','probably','hopefully','ideally','at some point','i suppose'
)
# Discourse markers / filler. These are HOW people talk, not WHAT they mean, so they
# must never survive into a value, goal, priority, boundary or summary. Stripped from
# anywhere in a clause; a clause that is nothing but markers is dropped entirely.
# (This is what let "honestly" and "which I've been ignoring" become core values.)
$script:UEDiscourse = @(
    'to be honest','at the end of the day','you know','i mean','you see','kind of','sort of',
    'honestly','actually','basically','really','literally','obviously','frankly','seriously',
    'anyway','right','well','look','listen','okay','ok','um','uh','yeah','like i said','i suppose'
)
# Fragments that carry no standalone meaning - relative/trailing clauses a sentence
# splitter can strand ("...my health, which I've been ignoring").
$script:UEFragmentStart = @('which','that','who','whom','whose','where','when')
# Standalone qualifiers and non-answers. People write "Sunday dinner. Non-negotiable."
# or "Family first, always" - the qualifier is EMPHASIS on the previous statement, not
# a statement itself. Left alone these become items ("Non-negotiable" as a core value),
# which is the same class of bug as "Honestly". Also covers explicit non-answers, which
# are not something to ask about later - the user already said they don't know.
$script:UEQualifierOnly = @(
    'always','never','ever','again','forever','constantly','definitely','absolutely','truly',
    'period','non-negotiable','nonnegotiable','non negotiable','no exceptions','full stop',
    'not sure','not sure really','no idea','idk','i do not know','i dont know',"i don't know",
    'none','nothing','n/a','na','tbd','no','yes','maybe','dunno','not really','who knows',
    'mostly','in that order','i know','that is','of course','for sure','stuff','things','etc'
)
# Concept map for SEMANTIC conflict detection. Word overlap alone only caught
# near-identical wording; mapping surface words onto concepts lets "Never schedule
# anything on weekends" collide with "work weekends to grow".
$script:UEConcepts = [ordered]@{
    CONTACT  = @('contact','email','emails','emailing','call','calling','phone','reach','reaching','message','messaging','text','texting','outreach','follow up','followup')
    CLIENT   = @('client','clients','customer','customers','policyholder','policyholders','prospect','prospects','lead','leads')
    WEEKEND  = @('weekend','weekends','saturday','saturdays','sunday','sundays')
    EVENING  = @('evening','evenings','night','nights','dinner','dinners','after hours','late')
    FAMILY   = @('family','wife','husband','spouse','kid','kids','child','children','son','daughter')
    GYM      = @('gym','workout','workouts','exercise','training','run','running')
    MORNING  = @('morning','mornings','early')
    VACATION = @('vacation','holiday','holidays','time off','pto','break')
}
# Verbs that mean "spend effort/time on" - used with a TIME concept to spot a goal
# that would consume a protected commitment.
$script:UEEffort = @('work','working','works','schedule','scheduling','book','booking','meet','meeting','travel','traveling','hustle','grind','put in')
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

# Strip lead-in filler AND discourse markers so an extracted item is Tony's
# INTERPRETATION, not a transcript. "I want to grow the agency" -> "Grow the agency";
# "My family, honestly" -> "My family".
function ConvertTo-UECleanClause {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return '' }
    $t = $Text.Trim()

    # discourse markers anywhere in the clause (word-bounded, longest first so
    # "to be honest" wins over "honest")
    foreach ($d in ($script:UEDiscourse | Sort-Object { $_.Length } -Descending)) {
        $t = ($t -ireplace ('\b' + [regex]::Escape($d) + '\b'), ' ')
    }
    $t = ($t -replace '\s{2,}', ' ').Trim().Trim(',', ';', '-', ' ')

    $fillers = @(
        "^i'd really like to\s+", "^i'd like to\s+", '^i would like to\s+', '^i want to\s+', '^i wanna\s+',
        '^my biggest goal is to\s+', '^my biggest goal is\s+', '^my goal is to\s+', '^my goal is\s+',
        '^i need to\s+', "^i'm trying to\s+", '^i am trying to\s+', '^i hope to\s+', '^i plan to\s+',
        '^i have to\s+', '^i must\s+', '^trying to\s+', '^hoping to\s+', '^probably\s+',
        '^just\s+', '^to\s+', '^and\s+', '^but\s+', '^also\s+', '^then\s+', '^so\s+', '^well\s+'
    )
    $changed = $true
    while ($changed) {
        $changed = $false
        foreach ($f in $fillers) {
            if ($t -imatch $f) { $t = ($t -ireplace $f, ''); $changed = $true }
        }
    }
    $t = ($t -replace '\s{2,}', ' ').Trim().Trim('.', ',', ';', '-', ' ')
    if ($t.Length -gt 0) { $t = $t.Substring(0, 1).ToUpper() + $t.Substring(1) }
    return $t
}

# A clause that is only filler, a bare qualifier ("Non-negotiable", "Always"), a
# non-answer ("I don't know"), or a stranded relative fragment ("which I've been
# ignoring") says nothing - it must never become a fact.
function Test-UEMeaningless {
    param([string]$Clean)
    if ([string]::IsNullOrWhiteSpace($Clean)) { return $true }
    $norm = ($Clean.ToLower() -replace '[^a-z0-9''/\s-]', '').Trim()
    if ($script:UEQualifierOnly -contains $norm) { return $true }
    $w = Get-UEWords $Clean
    if ($w.Count -eq 0) { return $true }
    $first = ($Clean.ToLower() -split '\s+')[0]
    if ($script:UEFragmentStart -contains $first) { return $true }
    return $false
}

# Sentences first. People end thoughts with a period, and not splitting on one is
# what merged "Work. Family. Health." into a single value.
# Decimals are protected by masking them, NOT by a look-behind on any digit: "Kids
# bedtime at 8. That is sacred." legitimately ends a sentence right after a digit,
# and a blanket (?<!\d) guard swallowed the split and produced the value
# "Kids bedtime at 8. That is".
function Split-UnderstandingSentences {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return @() }
    $masked = [regex]::Replace($Text, '(\d)\.(\d)', '$1<UEDOT>$2')
    $parts = @($masked -split '[.!?;]+(?:\s+|$)' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    return @($parts | ForEach-Object { $_.Replace('<UEDOT>', '.') })
}

# Split on " and " recursively so a run-on list yields every item, not just the
# first two ("get to 500 policies and hire an assistant and take a vacation").
# -Always is for noun lists (life areas): "family and business and health" is three
# areas even though none of them contains a verb. Elsewhere both sides must read as
# independent intentions, so "peace and quiet" stays one thing.
function Split-UEAnd {
    param([string]$Text, [bool]$Always = $false)
    if ($Text -imatch '\s+(?:and|&)\s+') {
        $l, $r = ($Text -isplit '\s+(?:and|&)\s+', 2)
        if ($Always -or ((Test-UEHasVerb $l) -and (Test-UEHasVerb $r))) {
            return @(@(Split-UEAnd -Text $l -Always $Always) + @(Split-UEAnd -Text $r -Always $Always))
        }
    }
    return @($Text)
}

# Split an answer into distinct clauses: sentences -> commas/transitions -> " and "
# only when both sides are independent intentions (so "peace and quiet" stays one).
# Contrast/exception markers (but/however/although/except/though/while) separate
# statements: "good at closing deals but I struggle with paperwork" is two things.
# Returns {raw, text}: hedging is judged on RAW (before filler is stripped), while
# `text` is what the user actually sees.
function Split-UnderstandingClauses {
    param([string]$Text, [switch]$SplitAnd)
    if ([string]::IsNullOrWhiteSpace($Text)) { return @() }
    # a spaced dash is punctuation ("the agency - I've got 300 policies"), but a
    # hyphen inside a word is not ("non-negotiable"), hence the required spaces.
    $sep = '(?:\r?\n|,|\s+[-–—]\s+|\bthen\b|\balso\b|\bplus\b|\bas well as\b|\bbut\b|\bhowever\b|\balthough\b|\bthough\b|\bexcept\b|\bwhereas\b|\byet\b|\bwhile\b)'
    $out = @()
    foreach ($sentence in (Split-UnderstandingSentences $Text)) {
        foreach ($p in @($sentence -split $sep | ForEach-Object { $_.Trim() } | Where-Object { $_ })) {
            foreach ($a in (Split-UEAnd -Text $p -Always ([bool]$SplitAnd))) { $out += $a.Trim() }
        }
    }
    $res = @()
    foreach ($o in $out) {
        $c = ConvertTo-UECleanClause $o
        if ($c.Length -ge 2 -and -not (Test-UEMeaningless $c)) {
            $res += [pscustomobject]@{ raw = $o; text = $c }
        }
    }
    return @($res)
}

# ---- concepts (semantic conflict detection) ----
function Get-UEConceptSet {
    param([string]$Text)
    $t = ' ' + ($Text.ToLower() -replace "[^a-z0-9\s']", ' ') + ' '
    $hits = @()
    foreach ($c in $script:UEConcepts.Keys) {
        foreach ($w in $script:UEConcepts[$c]) {
            if ($t -match ('\b' + [regex]::Escape($w) + '\b')) { $hits += $c; break }
        }
    }
    return @($hits | Select-Object -Unique)
}
function Test-UEHasEffort {
    param([string]$Text)
    $t = $Text.ToLower()
    foreach ($v in $script:UEEffort) { if ($t -match ('\b' + [regex]::Escape($v) + '\b')) { return $true } }
    return $false
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

# ---- conflict detection (concept-based) ---------------------------------
# The user tells us two kinds of thing:
#   * a PROHIBITION  (q_boundaries, negated: "never contact a client...")
#   * a COMMITMENT   (q_protect, positive: "Sunday dinner with my wife and kids")
# Matching on shared WORDS only ever caught near-identical wording, so a real
# conflict phrased differently ("never schedule anything on weekends" vs "work
# weekends to grow") passed silently and Tony accepted a goal that broke a stated
# boundary. We now compare CONCEPTS instead of words.
function Get-UEProhibitions {
    param($State)
    $out = @()
    foreach ($qid in @('q_boundaries', 'q_protect')) {
        $ans = Get-ConversationAnswer $State $qid
        if (-not $ans) { continue }
        foreach ($c in (Split-UnderstandingClauses $ans)) {
            $negated = ($c.raw -imatch "\b(never|don't|do not|dont|no|not|avoid|without)\b")
            $con = Get-UEConceptSet $c.raw
            if ($con.Count -eq 0) { continue }
            $out += [pscustomobject]@{
                text = $c.text; concepts = @($con); negated = $negated; sourceQuestionId = $qid
            }
        }
    }
    return @($out)
}

# Conflict when EITHER:
#   A. a negated boundary shares a concept with a clause that asserts doing it, or
#   B. a positive commitment shares a TIME concept with a clause that wants to spend
#      effort in that same time ("Sunday dinner" vs "work Sundays").
# Rule B deliberately requires an effort verb: "protect Sunday dinner with family"
# must NOT collide with "spend more time with family" - those AGREE. Sharing a
# concept is not the same as contradicting it.
$script:UETimeConcepts = @('WEEKEND', 'EVENING', 'MORNING', 'VACATION')
function Test-UEClauseConflict {
    param([string]$Clause, $Prohibitions)
    $cc = Get-UEConceptSet $Clause
    if ($cc.Count -eq 0) { return $null }
    foreach ($p in @($Prohibitions)) {
        $shared = @($cc | Where-Object { $p.concepts -contains $_ })
        if ($shared.Count -eq 0) { continue }
        if ($p.negated) { return $p }                                   # rule A
        $timeShared = @($shared | Where-Object { $script:UETimeConcepts -contains $_ })
        if ($timeShared.Count -gt 0 -and (Test-UEHasEffort $Clause)) { return $p }   # rule B
    }
    return $null
}

# ---- extraction ---------------------------------------------------------
# Shared worker: turn one answer into items for a category. Applies hedging,
# conflict detection and the confidence threshold uniformly.
function Get-UEItemsFromAnswer {
    param(
        $State, [string]$QuestionId, [string]$ReasonTemplate, [double]$BaseConfidence,
        $Prohibitions, [switch]$RequireVerb, [switch]$NounPhrase
    )
    $answer = Get-ConversationAnswer $State $QuestionId
    if ([string]::IsNullOrWhiteSpace($answer)) { return @() }
    $question = Get-UEQuestionText $QuestionId
    $items = @()
    foreach ($c in (Split-UnderstandingClauses -Text $answer -SplitAnd:$NounPhrase)) {
        $clause = $c.text
        $conf = $BaseConfidence
        $clarify = ''

        # a conflicting statement is never assumed - Tony asks
        $hit = Test-UEClauseConflict -Clause $c.raw -Prohibitions $Prohibitions
        if ($hit) {
            $clarify = ('You told me "{0}", but this sounds like "{1}". Which should I follow?' -f $hit.text, $clause)
        }
        else {
            # hedging is judged on the RAW clause: several hedges ("kind of") are also
            # discourse markers and would be gone from the cleaned text.
            if (Test-UEHedged $c.raw) { $conf = $conf - 0.25 }
            if ($RequireVerb -and -not (Test-UEHasVerb $clause)) { $conf = $conf - 0.2 }
            if ($clause -match '\d') { $conf = $conf + 0.05 }                        # a number = concrete
            # A bare word is a weak GOAL ("health" is not a goal), but it is a
            # perfectly complete AREA - "Family" is the whole answer. So this only
            # demotes categories that require an intention.
            if ($RequireVerb -and (Get-UEWords $clause).Count -le 1) { $conf = $conf - 0.15 }
            # An AREA is a noun phrase ("My family", "The agency"). A first-person
            # sentence in that answer is commentary ABOUT an area, not the area
            # itself - "I've got 300 policies and I want more" is not a life area.
            if ($NounPhrase -and $clause -imatch "^(i|i'm|i am|i've|we|we're|we've)\b") { $conf = $conf - 0.2 }
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
                    $items += (New-UnderstandingItem -Text $clause[0].text -SourceQuestionId $step.id `
                        -SourceQuestion $step.tony -SourceAnswer $ans `
                        -Reason ('You said "{0}" when describing yourself.' -f $m) -Confidence 0.75)
                }
                break
            }
        }
    }
    return @($items)
}

# ---- values: inferred, never a copy of the priorities list ----
# Listing your life areas ("family, health, the agency") tells me what you're FOCUSED
# on - it does not tell me what you VALUE. Deriving values from that answer produced
# a byte-identical duplicate of priorities, which is not understanding.
# A value is only extracted where the user marked something as a principle: they
# called it non-negotiable, said it comes first, or said it matters most / they
# believe in it. If nothing qualifies, Values stays EMPTY - low confidence beats
# incorrect confidence.
$script:UEValueMarkers = @(
    @{ rx = '\bnon-?negotiable\b';                       why = 'You called this non-negotiable.' }
    @{ rx = '\bcomes first\b|\bfirst,?\s+always\b|\balways\s+comes?\s+first\b'; why = 'You said this comes first.' }
    @{ rx = '\bi value\b|\bi really value\b';            why = 'You said you value this.' }
    @{ rx = '\bmatters? most\b|\bmost important\b|\bimportant to me\b'; why = 'You said this matters most to you.' }
    @{ rx = '\bi believe in\b|\bi stand for\b';          why = 'You said you believe in this.' }
    @{ rx = '\bnever compromise\b|\bwon.t compromise\b'; why = 'You said you will not compromise on this.' }
    @{ rx = '\bsacred\b|\buntouchable\b|\bprotected\b';  why = 'You described this as protected.' }
)
# Markers are matched on whole SENTENCES, because the emphasis usually sits in its
# own sentence ("Sunday dinner with my wife and kids. Non-negotiable.") or spans a
# comma ("Family first, always"). When the marker sentence carries no content of its
# own, the value is the statement it was emphasising - the PREVIOUS sentence.
function Get-UEValues {
    param($State)
    $items = @()
    $seen = @{}
    foreach ($step in @(Get-ConversationSteps | Where-Object { $_.type -eq 'question' })) {
        $ans = Get-ConversationAnswer $State $step.id
        if ([string]::IsNullOrWhiteSpace($ans)) { continue }
        $sentences = @(Split-UnderstandingSentences $ans)
        for ($i = 0; $i -lt $sentences.Count; $i++) {
            $s = $sentences[$i]
            foreach ($m in $script:UEValueMarkers) {
                if ($s -inotmatch $m.rx) { continue }
                # the marker is the SIGNAL, not the value - strip it and see what remains
                $txt = ConvertTo-UECleanClause (($s -ireplace $m.rx, ' ') -replace '\s{2,}', ' ')
                if (-not $txt -or (Test-UEMeaningless $txt)) {
                    # pure emphasis ("Non-negotiable.") -> it qualifies the sentence before it
                    $txt = ''
                    if ($i -gt 0) { $txt = ConvertTo-UECleanClause $sentences[$i - 1] }
                }
                if (-not $txt -or (Test-UEMeaningless $txt)) { break }
                $key = $txt.ToLower()
                if ($seen.ContainsKey($key)) { break }
                $seen[$key] = $true
                $conf = 0.8
                if (Test-UEHedged $s) { $conf = $conf - 0.25 }
                $items += (New-UnderstandingItem -Text $txt -SourceQuestionId $step.id `
                    -SourceQuestion $step.tony -SourceAnswer $ans -Reason $m.why -Confidence $conf)
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

# A conflict can hide inside a fragment we would never extract as an item:
# "Grow the agency, which means I'll probably have to work weekends for a while."
# That clause is correctly dropped for EXTRACTION (it is not a goal), but it still
# states intent - so conflicts are ALSO scanned at the sentence level across the
# intent-bearing answers. Tony records the real goal and asks about the tension,
# rather than silently accepting something that breaks a stated boundary.
function Get-UEAnswerConflicts {
    param($State, $Prohibitions)
    $out = @()
    foreach ($qid in @('q_goal', 'q_areas', 'q_week', 'q_challenge')) {
        $ans = Get-ConversationAnswer $State $qid
        if ([string]::IsNullOrWhiteSpace($ans)) { continue }
        foreach ($s in (Split-UnderstandingSentences $ans)) {
            $hit = Test-UEClauseConflict -Clause $s -Prohibitions $Prohibitions
            if (-not $hit) { continue }
            $said = ConvertTo-UECleanClause $s
            if (-not $said) { continue }
            $out += [pscustomobject]@{
                question         = ('You told me "{0}", but you also said "{1}". Which should win?' -f $hit.text, $said)
                sourceQuestionId = $qid
                text             = $said
            }
        }
    }
    return @($out)
}

# ---- the model ----------------------------------------------------------
# Builds the temporary Understanding Model from the conversation answers.
# Pure: reads state, writes nothing.
function New-UnderstandingModel {
    param($State)
    if (-not $State) { $State = Get-ConversationState }
    $pro = Get-UEProhibitions -State $State

    $goals      = Get-UEItemsFromAnswer -State $State -QuestionId 'q_goal'       -Prohibitions $pro -RequireVerb -BaseConfidence 0.8  -ReasonTemplate 'You named this as a goal for the next 6-12 months.'
    $priorities = @(Get-UEItemsFromAnswer -State $State -QuestionId 'q_areas'    -Prohibitions $pro -NounPhrase -BaseConfidence 0.8  -ReasonTemplate 'You listed this among the most important areas of your life right now.')
    $priorities += @(Get-UEItemsFromAnswer -State $State -QuestionId 'q_week'    -Prohibitions $pro -BaseConfidence 0.72 -ReasonTemplate 'You described this as part of a successful week.')
    $values     = Get-UEValues -State $State
    $challenges = Get-UEItemsFromAnswer -State $State -QuestionId 'q_challenge'  -Prohibitions $pro -BaseConfidence 0.8  -ReasonTemplate 'You named this as what is getting in your way.'
    $boundaries = @(Get-UEItemsFromAnswer -State $State -QuestionId 'q_boundaries' -Prohibitions @() -BaseConfidence 0.85 -ReasonTemplate 'You asked me never to assume or act on this without checking first.')
    $boundaries += @(Get-UEItemsFromAnswer -State $State -QuestionId 'q_protect' -Prohibitions @() -BaseConfidence 0.8  -ReasonTemplate 'You asked me to protect this commitment.')
    $strengths  = Get-UEStrengths -State $State

    # "I'm good at selling but terrible at delegating" splits into two clauses on the
    # CHALLENGE question - but the first half is a strength, and listing "I am good at
    # selling" as a challenge is exactly the kind of literal-minded mistake that makes
    # Tony look like he is parsing rather than listening. A clause already understood
    # as a strength is not also a challenge.
    if (@($strengths).Count -gt 0) {
        $sTexts = @(@($strengths) | ForEach-Object { $_.text.ToLower() })
        $challenges = @(@($challenges) | Where-Object {
            $t = $_.text.ToLower()
            -not (@($sTexts | Where-Object { $t -eq $_ -or $t.Contains($_) }).Count -gt 0)
        })
    }

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
        clarifications   = @()
        omitted          = @(@($all | Where-Object { $_.band -eq 'low' }) | ForEach-Object {
                                [pscustomobject]@{ text = $_.text; reason = 'Not clearly enough stated for me to assume it.'; confidence = $_.confidence; sourceQuestionId = $_.sourceQuestionId } })
    }
    # Clarifications come from two passes: items we refused to assume (moderate band)
    # and conflicts found in sentences that never became items. The two passes phrase
    # the question differently, so they must be deduped by the CONFLICTING CLAUSE -
    # keying on the question text let the same conflict be asked twice.
    $clar = @()
    $seenC = @{}
    foreach ($c in @(@($all | Where-Object { $_.band -eq 'moderate' }) | ForEach-Object {
                [pscustomobject]@{ question = $_.clarify; sourceQuestionId = $_.sourceQuestionId; text = $_.text } })) {
        $k = ($c.text -as [string]).ToLower()
        if ($c.question -and -not $seenC.ContainsKey($k)) { $seenC[$k] = $true; $clar += $c }
    }
    foreach ($c in (Get-UEAnswerConflicts -State $State -Prohibitions $pro)) {
        $k = ($c.text -as [string]).ToLower()
        # an item-level ask already covers this clause if either contains the other
        $dup = @($seenC.Keys | Where-Object { $k -eq $_ -or $k.Contains($_) -or $_.Contains($k) }).Count -gt 0
        if ($c.question -and -not $dup) { $seenC[$k] = $true; $clar += $c }
    }
    $model.clarifications = ([array]$clar)

    $model.executiveSummary = New-UEExecutiveSummary -Model $model
    return $model
}

# Natural-language list: "A", "A and B", "A, B and C" - never "A; B; C", which read
# like a database dump rather than someone who listened.
function Join-UENatural {
    param($Items)
    $t = @(@($Items) | ForEach-Object { $_.text.TrimEnd('.', ',', ' ') } | Where-Object { $_ })
    if ($t.Count -eq 0) { return '' }
    if ($t.Count -eq 1) { return $t[0] }
    if ($t.Count -eq 2) { return ('{0} and {1}' -f $t[0], $t[1]) }
    return ('{0} and {1}' -f (($t[0..($t.Count - 2)]) -join ', '), $t[-1])
}
# NOTE: an earlier version lowercased items for mid-sentence use. It could not tell a
# proper noun ("Faith") from a common word ("Mostly") and so left casing inconsistent
# ("my kids, Mostly and Sort out my sleep"). Since the summary is colon-style, items
# are LIST entries and keeping the user's own capitalisation is both correct and
# consistent - so no inline transform is applied at all.

# Composed strictly from the CLEANED, high-confidence model - never raw fragments,
# never invented. Reads like an assistant recapping what he heard.
function New-UEExecutiveSummary {
    param($Model)
    $parts = @(); $sources = @()
    $inline = { param($items) (Join-UENatural $items) }

    # Colon-style recap. Items are the user's own phrasings with mixed grammatical
    # person ("I close 3 new policies", "Hit 500 policies"), so inlining them after a
    # verb produces "focused on hit 500 policies" / "getting in your way are I'm the
    # bottleneck". A lead-in plus a colon reads naturally with ANY phrasing, which is
    # how an assistant would actually write these notes back to you.
    if ($Model.name) { $parts += ('You asked me to call you {0}.' -f $Model.name); $sources += 'q_name' }

    $areas = @($Model.priorities | Where-Object { $_.sourceQuestionId -eq 'q_areas' })
    $week  = @($Model.priorities | Where-Object { $_.sourceQuestionId -eq 'q_week' })
    if ($areas.Count -gt 0) {
        $parts += ('What matters most to you right now: {0}.' -f (& $inline $areas)); $sources += 'q_areas'
    }
    if (@($Model.goals).Count -gt 0) {
        $parts += ('Your goals for the next 6-12 months: {0}.' -f (& $inline $Model.goals)); $sources += 'q_goal'
    }
    if (@($Model.challenges).Count -gt 0) {
        $parts += ('What is getting in your way: {0}.' -f (& $inline $Model.challenges)); $sources += 'q_challenge'
    }
    if ($week.Count -gt 0) {
        $parts += ('A good week looks like: {0}.' -f (& $inline $week)); $sources += 'q_week'
    }
    if (@($Model.values).Count -gt 0) {
        $parts += ('You hold these as principles, not preferences: {0}.' -f (Join-UENatural $Model.values)); $sources += 'values'
    }
    if (@($Model.strengths).Count -gt 0) {
        $parts += ('Strengths you named: {0}.' -f (Join-UENatural $Model.strengths)); $sources += 'strengths'
    }
    if (@($Model.boundaries).Count -gt 0) {
        $parts += ('And I will not act on these without asking you first: {0}.' -f (Join-UENatural $Model.boundaries)); $sources += 'q_boundaries'
    }

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

# ---- on Claude enrichment (deliberately absent) --------------------------
# There was an Invoke-UnderstandingEnrichment seam here. It was never called, and
# if it had been it would have stamped meta.engine = 'local+claude' while doing NO
# enrichment - putting Claude's name on work Claude never did. Dead code that
# misreports provenance is worse than no code, so it is removed rather than left
# as a placeholder. meta.engine is therefore always 'local' and always true.
# Making Claude the PRIMARY extractor (local as the offline fallback) is the next
# sprint; the Understanding Model shape is already provider-agnostic and will take
# LLM-produced items unchanged, so nothing here needs to be redesigned for it.

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
