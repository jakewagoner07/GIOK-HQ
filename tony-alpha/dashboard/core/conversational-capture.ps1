# =====================================================================
# conversational-capture.ps1  -  Tell Tony, and he prepares the proposal
# ---------------------------------------------------------------------
# Epic 7 (Conversational Capture). Jake says something in normal
# conversation ("I want to lose 20 pounds") and Tony recognizes the
# structured intent and prepares the RIGHT Executive Inbox proposal - he
# NEVER writes to the operating system himself.
#
# This is a PURE, PROVIDER-AGNOSTIC intent engine: no LLM call, no provider
# wording. Given a message it deterministically decides the type, a clean
# title, a confidence band, and an evidence excerpt - or that the message
# should be IGNORED, or that Tony should ask ONE clarifying question.
#
# A proposal is NOT an action. Recognizing intent writes ONLY to the pending
# Executive Inbox (via Add-InboxProposal). Approval (always Jake's) is the only
# thing that writes real data, through the existing OWNING module. Nothing is
# ever added automatically. De-duplication is content-based and idempotent.
#
# Reuses: Add-InboxProposal, Get-ProposalKey, Test-DestinationDuplicate,
# Get-InboxItems, Get-InboxDestinationLabel. No new store, no schema change.
# =====================================================================

$ErrorActionPreference = 'Stop'

# The 10 V1 capture types and a friendly label for each (what Tony calls it).
$script:CaptureLabels = @{
    'health'         = 'Health goal'
    'financial'      = 'Financial goal'
    'agency'         = 'Agency goal'
    'learning'       = 'Learning goal'
    'goal'           = 'goal'
    'task'           = 'reminder for your Action Items'
    'project'        = 'project'
    'non-negotiable' = 'Non-Negotiable'
    'family'         = 'Family item'
    'memory'         = 'note to remember'
}
function Get-CaptureLabel { param([string]$Type) if ($script:CaptureLabels.ContainsKey($Type)) { $script:CaptureLabels[$Type] } else { $Type } }

# ---- small pure helpers ----

# Strip a leading intent/commitment phrase and a trailing date phrase, trim, and
# capitalize the first letter - turning "i want to lose 20 pounds" into
# "Lose 20 pounds". Never invents words; only trims. Pure.
function Get-CaptureTitle {
    param([string]$Text)
    $s = ([string]$Text).Trim()
    $s = $s -replace '[.!?]+\s*$', ''
    # leading commitment / reminder / remember phrases
    $lead = '^(?i)\s*(please\s+)?(i\s+want\s+to|i\s+want|i\s+need\s+to|i\s+have\s+to|i''?m\s+going\s+to|i\s+am\s+going\s+to|i\s+will|i''?ll|my\s+goal\s+is\s+to|my\s+goal\s+is|i\s+plan\s+to|i\s+intend\s+to|i''?d\s+like\s+to|i\s+would\s+like\s+to|i\s+should|we\s+should|remind\s+me\s+to|remind\s+me|remember\s+to|remember\s+that|note\s+that|keep\s+in\s+mind\s+that|keep\s+in\s+mind|for\s+the\s+record,?|make\s+sure\s+i|make\s+sure\s+to|don''?t\s+let\s+me\s+forget\s+to|don''?t\s+let\s+me\s+forget)\s+'
    $s = $s -replace $lead, ''
    # trailing standalone date/time phrase -> keep it out of the title (it goes in the description)
    $s = $s -replace '(?i)[\s,]+(by\s+)?(today|tonight|tomorrow|this\s+(week|weekend)|next\s+(week|month)|on\s+\w+day|by\s+\w+day|(mon|tues|wednes|thurs|fri|satur|sun)day)\s*$', ''
    $s = ($s -replace '\s+', ' ').Trim()
    if ($s.Length -gt 0) { $s = $s.Substring(0, 1).ToUpper() + $s.Substring(1) }
    return $s
}

# Extract a human date phrase from the text, if any (for an action item's
# "when"). Returns '' when none. Pure - no parsing to a real date (Tony proposes,
# Jake sets the exact date on approval).
function Get-CaptureWhen {
    param([string]$Text)
    $m = [regex]::Match($Text, '(?i)\b(today|tonight|tomorrow|this (week|weekend)|next (week|month)|(on |by )?(mon|tues|wednes|thurs|fri|satur|sun)day)\b')
    if ($m.Success) { return $m.Value.Trim() }
    return ''
}

# The DETERMINISTIC classifier. Returns a candidate object, or $null when the
# message carries no structured intent. Bands: 'high' | 'moderate' | 'low'.
#   $Prior - the previous user message, used only to resolve "this/that" for a
#            bare "this sounds like a project" (never invented otherwise).
function Get-CaptureCandidate {
    param([string]$Text, [datetime]$Now = (Get-Date), [string]$Prior = '')
    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
    $raw = ($Text.Trim() -replace '\s+', ' ')
    $t = ' ' + $raw.ToLower() + ' '

    # ---- signals ----
    $isQuestion  = ($raw -match '\?\s*$')
    $weak        = ($t -match '\b(maybe|some ?day|one day|eventually|at some point|might|possibly|thinking about|kind of|sort of|not sure|i guess|hypothetically|in theory|wish i|would be nice|could be nice|dreaming|if i ever|toying with)\b')
    $reminder    = ($t -match '\b(remind me|don''t let me forget|do not let me forget|make sure i|make sure to|note to self)\b')
    $rememberTo  = ($t -match '\bremember to\b')
    $rememberFact= ($t -match '\b(remember that|keep in mind|for the record|for future reference|note that|make a note)\b')
    $nonneg      = ($t -match '\b(non-?negotiable|no matter what)\b')
    $strong      = ($t -match '\b(i want to|i want|i need to|i have to|i''m going to|i am going to|i will|i''ll|my goal is|i plan to|i intend to|i''d like to|i would like to|i should|we should|commit to|i''m committing|let''s)\b')
    $routine     = ($t -match '\b(every (day|morning|night|evening|week|weekend|month|sunday|monday|tuesday|wednesday|thursday|friday|saturday)|each (day|week|morning|night)|daily|nightly|weekly)\b')
    $projectHint = ($t -match '\b(project|initiative|build (out|a|an|the)|launch|roll ?out|set up a|stand up a|revamp|redesign|overhaul|onboarding system|new system|program)\b')

    # ---- gate: no intent marker at all -> ignore (casual talk, jokes, chit-chat) ----
    if (-not ($strong -or $reminder -or $rememberTo -or $rememberFact -or $nonneg -or $routine -or $projectHint)) { return $null }
    # a bare question with no reminder/remember is not a commitment ("should I lose weight?")
    if ($isQuestion -and -not ($reminder -or $rememberTo -or $rememberFact)) { return $null }

    # ---- domain detectors ----
    $health    = ($t -match '\b(lose|drop|gain|weight|pounds?|lbs|kg|work ?out|exercis|gym|jog|run(ning)?|marathon|diet|calorie|sleep|muscle|fitness|steps|meditat|hydrate|health|stretch|cardio|lift(ing)?)\b')
    $financial = ($t -match '(\$|\bsave(d|s|ings)?\b|\bbudget|\binvest|\bdebt|\bpay off\b|\bretire|\bnet worth\b|\bemergency fund\b|\bmortgage\b|\bmoney\b|\bfinanc)')
    $agency    = ($t -match '\b(giok|the agency|my agency|agency|subscribers?|clients?|polic(y|ies)|book of business|commission|premium|leads?|pipeline|new business|producers?|renewals?)\b')
    $learning  = ($t -match '\b(learn|study|read \d+|read (a|the|some|more)|books?|course|certification|certif|masterclass|degree|master (the|a|spanish|french)|language|spanish|french|german|coding|programming|skill|piano|guitar)\b')
    $family    = ($t -match '\b(family|wife|husband|spouse|kids?|son|daughter|children|anniversary|date night|movie night|mom|dad|parents|dinner (with|every))\b')

    $when = Get-CaptureWhen -Text $raw
    $title = Get-CaptureTitle -Text $raw

    # ---------------------------------------------------------------- #
    # ROUTING (precedence matters). Each branch sets $type/$conf/$desc.
    # ---------------------------------------------------------------- #
    $type = $null; $conf = 0.0; $desc = ''; $clarify = $null

    # 1) explicit reminder / single next action -> action item
    if ($reminder -or $rememberTo) {
        $type = 'task'; $conf = 0.85
        $desc = if ($when) { ('When: {0} (confirm the exact date on approval).' -f $when) } else { '' }
    }
    # 2) non-negotiable (wins over family/routine)
    elseif ($nonneg) {
        $type = 'non-negotiable'; $conf = 0.85
    }
    # 3) a fact/preference to preserve -> memory
    elseif ($rememberFact) {
        $type = 'memory'; $conf = 0.8
    }
    # 4) explicit project (multi-step build, or "this sounds like a project")
    elseif ($projectHint -and ($t -match '\bproject\b' -or $t -match '\b(build|launch|roll ?out|set up a|stand up a|revamp|redesign|overhaul)\b')) {
        $type = 'project'; $conf = 0.75
        # resolve a bare "this/that ... project" from the prior message if we have one
        if ($t -match '\b(this|that|it) (sounds like|is|could be|might be|would be) (a |an )?project\b') {
            if ($Prior -and -not [string]::IsNullOrWhiteSpace($Prior)) { $title = Get-CaptureTitle -Text $Prior; $desc = 'From the conversation.' }
            else { $title = ''; $conf = 0.6 }   # nothing to title yet -> clarify below
        }
    }
    # 5) domain / general goal (requires a commitment marker)
    elseif ($strong -or $routine) {
        $hits = @()
        if ($health)    { $hits += 'health' }
        if ($financial) { $hits += 'financial' }
        if ($agency)    { $hits += 'agency' }
        if ($learning)  { $hits += 'learning' }
        if ($family)    { $hits += 'family' }
        if ($hits.Count -eq 1) {
            $type = $hits[0]; $conf = 0.8
        }
        elseif ($hits.Count -ge 2) {
            # two plausible domains -> moderate, clarify between the top two
            $type = $hits[0]; $conf = 0.55
            $clarify = ('Is that a {0} or a {1}? I can prepare it either way for your Executive Inbox.' -f (Get-CaptureLabel $hits[0]), (Get-CaptureLabel $hits[1]))
        }
        elseif ($family -and $routine) {
            $type = 'family'; $conf = 0.75
        }
        else {
            # a commitment with no domain: a general goal ONLY if it reads like an
            # achievement; otherwise it's an errand/chit-chat we should not capture.
            $achievement = ($t -match '\b(achieve|reach|become|build|write|start|finish|complete|create|grow|hit|launch|get to|make it to|run a|save|earn|double|triple)\b')
            if ($achievement) { $type = 'goal'; $conf = 0.7 }
            else { return $null }
        }
    }
    else { return $null }

    if (-not $type) { return $null }

    # ---- weak language demotes a would-be goal to a clarify (never a silent proposal) ----
    $goalish = @('goal', 'health', 'financial', 'agency', 'learning')
    if ($weak -and ($type -in $goalish) -and -not $clarify) {
        $conf = 0.55
        $clarify = ('Should I treat that as a {0}, or just remember it as a future idea? I''ll prepare whichever you pick.' -f (Get-CaptureLabel $type))
    }

    # ---- a project we couldn't title -> ask what it's about ----
    if ($type -eq 'project' -and [string]::IsNullOrWhiteSpace($title)) {
        $conf = 0.55
        $clarify = 'That could be a project - what should I call it? I''ll prepare it for your Executive Inbox.'
    }

    if ([string]::IsNullOrWhiteSpace($title) -and -not $clarify) { return $null }

    $band = if ($clarify) { 'moderate' } elseif ($conf -ge 0.7) { 'high' } else { 'low' }

    return [pscustomobject]@{
        type        = $type
        title       = $title
        description = $desc
        confidence  = [math]::Round($conf, 2)
        band        = $band
        clarify     = $clarify
        evidence    = ($raw.Substring(0, [math]::Min(200, $raw.Length)))
        label       = (Get-CaptureLabel $type)
        destination = $(if (Get-Command Get-InboxDestinationLabel -ErrorAction SilentlyContinue) { Get-InboxDestinationLabel -Type $type } else { '' })
    }
}

# Content-based duplicate check (idempotency). A capture proposal keeps the
# message id as sourceId for provenance, but two different messages that MEAN the
# same thing must not both become proposals - so we compare by type + normalized
# title against pending proposals AND the destination owner's active records.
function Test-CaptureDuplicate {
    param([string]$Type, [string]$Title)
    if (-not (Get-Command Get-ProposalKey -ErrorAction SilentlyContinue)) { return $false }
    $key = Get-ProposalKey -Type $Type -Title $Title    # no sourceId -> content key
    foreach ($it in @(Get-InboxItems -Status 'pending')) {
        if ((Get-ProposalKey -Type $it.type -Title $it.title) -eq $key) { return $true }
    }
    if (Get-Command Test-DestinationDuplicate -ErrorAction SilentlyContinue) {
        if (Test-DestinationDuplicate -Type $Type -Title $Title) { return $true }
    }
    return $false
}

# THE entry point the conversation calls. Classifies the message and, on high
# confidence, prepares ONE Executive Inbox proposal (discoveredBy=Tony). Returns
# a result the UI surfaces as one calm, TRUTHFUL line - never claims a direct
# write. On moderate confidence it asks one question and creates nothing; on low
# it does nothing.
#   action: 'proposed' | 'clarify' | 'duplicate' | 'none'
function Invoke-ConversationalCapture {
    param(
        [Parameter(Mandatory)][string]$Text,
        [string]$MessageId = '',
        [datetime]$Now = (Get-Date),
        [string]$Prior = ''
    )
    $none = [pscustomobject]@{ action = 'none'; type = $null; label = $null; proposalId = $null; tonyLine = $null }
    $cand = Get-CaptureCandidate -Text $Text -Now $Now -Prior $Prior
    if (-not $cand) { return $none }

    if ($cand.band -eq 'moderate') {
        return [pscustomobject]@{ action = 'clarify'; type = $cand.type; label = $cand.label; proposalId = $null; tonyLine = $cand.clarify }
    }
    if ($cand.band -ne 'high') { return $none }

    # idempotent: a repeat of the same thing does not create a second proposal
    if (Test-CaptureDuplicate -Type $cand.type -Title $cand.title) {
        return [pscustomobject]@{ action = 'duplicate'; type = $cand.type; label = $cand.label; proposalId = $null
            tonyLine = ('You''ve already got that waiting in your Executive Inbox - I won''t add it twice.') }
    }

    if (-not (Get-Command Add-InboxProposal -ErrorAction SilentlyContinue)) { return $none }
    $ev = @([pscustomobject]@{ source = 'conversation'; sourceId = [string]$MessageId; detail = $cand.evidence })
    $item = Add-InboxProposal -DiscoveredBy 'Tony' -Type $cand.type -Title $cand.title -Description $cand.description `
        -ProposedDestination $cand.destination -Evidence $ev -Confidence $cand.confidence -Source 'conversation' -SourceId ([string]$MessageId)
    if (-not $item) { return $none }

    $tonyLine = ('That sounds like a {0}. I''ve prepared it for your Executive Inbox to approve, edit, or reject - nothing is added until you say so.' -f $cand.label)
    return [pscustomobject]@{ action = 'proposed'; type = $cand.type; label = $cand.label; proposalId = $item.id; tonyLine = $tonyLine }
}
