# =====================================================================
# executive-priority.ps1  —  Tony's Executive Priority Engine
# ---------------------------------------------------------------------
# Answers "What should Jake focus on today?" - while GUARANTEEING that no
# legitimate item is silently forgotten. Everything meaningful is
# acknowledged; not everything is treated as equally urgent.
#
# It READS the single Executive Context (which already references Calendar,
# Gmail, Action Items, approved Memory, observations, goals, current
# priorities, and the Decision Framework judgment) and ranks the REAL items
# into four levels:
#   1. Act Now          - drop-what-you-can; waiting people, family-time
#                         conflicts, imminent appointments, hard deadlines
#   2. Do Today         - important, not drop-everything
#   3. Keep Visible     - legitimate but low-urgency; NEVER discarded
#   4. Low-Value Noise  - obvious promotions/spam/duplicates; suppressed but
#                         still counted and accessible
#
# The Decision Framework retains FINAL AUTHORITY: each candidate is judged
# by Evaluate-TonyDecision (Family before Financial, People before Money,
# deadlines, consequences, commitments, blocked work), and that judgment
# shapes the tier. Pure, deterministic, testable. Stores NOTHING, creates no
# task database, and preserves each item's original source + source id.
# =====================================================================

$ErrorActionPreference = 'Stop'

# ---- signal vocabularies (deterministic) ---------------------------
$script:PriFamilyWords     = @('family', 'kids', 'kid', 'son', 'daughter', 'children', 'child', 'wife', 'husband', 'partner', 'dinner', 'date night', 'anniversary', 'birthday', 'school', 'recital', 'game night')
$script:PriWaitingWords    = @('waiting', 'awaiting', 'follow up', 'follow-up', 'get back', 'respond', 'response', 'reply', 'confirm', 'confirmation', 'coverage', 'quote', 'approval', 'sign', 'signature', 'needs your', 'per your request', 'as requested')
$script:PriConsequenceWords = @('overdue', 'past due', 'deadline', 'due', 'expire', 'expires', 'expiring', 'final notice', 'last notice', 'urgent', 'asap', 'today', 'end of day', 'cancel', 'lapse', 'penalty')
$script:PriBlockedWords    = @('blocked', 'waiting on', 'stuck', 'depends on', 'can''t proceed', 'cannot proceed', 'pending')
$script:PriApptWords       = @('appointment', 'meeting', 'call', 'consult', 'review', 'presentation', 'demo', 'interview', 'sync', 'checkup', 'closing')
$script:PriRoutineBlocks   = @('gym', 'workout', 'lunch', 'breakfast', 'dinner break', 'walk', 'shower', 'sleep', 'wake', 'commute', 'drive', 'break', 'free time', 'focus block', 'deep work', 'reading', 'journal', 'meditation')
# Strong appointment markers (a real meeting, not a generic "call"/"review").
$script:PriStrongApptWords = @('appointment', 'consult', 'presentation', 'demo', 'interview', 'closing', 'onboarding', 'kickoff', 'renewal review', '1:1', 'one-on-one')
# A conflict that includes any of these is a personal/automated time-block
# overlap, not a real conflict to resolve.
$script:PriConflictNoiseWords = @('digest', 'automated', 'audit', 'journal', 'tracker', 'trackers', 'log activity', 'block', 'reminder', 'crm time', 'pipeline', 'follow-up', 'morning', 'end-of-day', 'end of day', 'clean', 'queue', 'draft', 'symmetry', 'training')

function Test-PriWords { param([string]$Text, $Words) if ([string]::IsNullOrWhiteSpace($Text)) { return $false } $t = $Text.ToLower(); foreach ($w in @($Words)) { if ($w -and $t.Contains(([string]$w).ToLower())) { return $true } } return $false }

# Normalized signature for de-duplicating the same commitment across sources.
# Significant words (>=4 chars), lowercased, sorted - so "Call the Millers"
# (action item) and "Millers call" (calendar) collapse to one commitment.
function Get-PrioritySignature {
    param([string]$Title)
    $t = ([string]$Title).ToLower()
    $t = $t -replace '(?i)^\s*(invitation|updated invitation|re|fwd|fw)\s*:\s*', ''   # strip email/invite prefixes
    $t = $t -replace '[^a-z0-9 ]', ' '
    # keep significant words (>=4 chars) and any numeric token (a number often
    # IS the distinguishing detail: "Prospect 1" vs "Prospect 2", "policy 12479")
    $words = @($t -split '\s+' | Where-Object { $_.Length -ge 4 -or $_ -match '^\d+$' } | Sort-Object -Unique)
    if ($words.Count -eq 0) { $words = @($t -split '\s+' | Where-Object { $_ }) }
    return ($words -join ' ')
}

# A routine personal time-block is schedule, not a to-do. It is neither
# ranked nor treated as noise - it simply belongs to Today's Schedule.
function Test-PriRoutineBlock {
    param($Item)
    if ($Item.kind -ne 'event') { return $false }
    if ($Item.attendeeCount -gt 0) { return $false }          # a real meeting has attendees
    if ($Item.hasLink) { return $false }
    return (Test-PriWords $Item.title $script:PriRoutineBlocks)
}

# ---- gather candidate items from the single Executive Context ------
# Each candidate preserves its source + source id. No new storage.
function Get-PriorityCandidates {
    param($Context, [datetime]$Now)
    $cands = @()
    $add = { param($o) $script:__pc += , $o }
    $script:__pc = @()

    # 1) Calendar - only APPOINTMENTS (real meetings) become priority items;
    #    personal time-blocks (CRM time, call blocks, gym) are schedule, shown
    #    in Today's Schedule, not ranked as to-dos. Only MEANINGFUL conflicts
    #    (family time, or two real appointments) are surfaced - intentional
    #    time-block overlaps are not "conflicts to resolve".
    $cal = $Context.calendar
    if ($cal -and $cal.ok) {
        # Calendar events are SCHEDULE (already in Today's Schedule), NOT to-dos.
        # Surface at most ONE actionable calendar item: prep for the next real
        # appointment today - a genuine multi-person meeting (2+ attendees) or a
        # video meeting or a strong appointment word, and never a routine block.
        $nextAppt = @($cal.events | Where-Object {
                (-not $_.allDay) -and ($_.start.Date -eq $Now.Date) -and ($_.start -ge $Now) -and
                ((([int]$_.attendeeCount -ge 2) -or [bool]$_.meetingLink -or (Test-PriWords $_.title $script:PriStrongApptWords))) -and
                (-not (Test-PriWords $_.title ($script:PriRoutineBlocks + $script:PriConflictNoiseWords)))
            } | Sort-Object start | Select-Object -First 1)
        if ($nextAppt) {
            & $add ([pscustomobject]@{
                    kind = 'event'; source = 'calendar'; sourceId = [string]$nextAppt.id; title = ('Prepare for {0}' -f $nextAppt.title)
                    when = $nextAppt.start; attendeeCount = [int]$nextAppt.attendeeCount; hasLink = [bool]$nextAppt.meetingLink
                    text = [string]$nextAppt.title; accounts = @($nextAppt.sourceAccounts)
                })
        }
        foreach ($cf in @($cal.conflicts)) {
            $both = ("{0} {1}" -f $cf.a, $cf.b)
            $fam = Test-PriWords $both $script:PriFamilyWords
            $bothAppt = (Test-PriWords $cf.a $script:PriApptWords) -and (Test-PriWords $cf.b $script:PriApptWords)
            $noise = Test-PriWords $both $script:PriConflictNoiseWords
            if (-not ($fam -or ($bothAppt -and -not $noise))) { continue }   # skip time-block overlaps
            & $add ([pscustomobject]@{
                    kind = 'conflict'; source = 'calendar'; sourceId = $null
                    title = ("Calendar conflict: {0} overlaps {1}" -f $cf.a, $cf.b); when = $cf.at
                    text = ("{0} {1}" -f $cf.a, $cf.b); attendeeCount = 0; hasLink = $false
                })
        }
    }

    # 2) Gmail - the attention items already triaged by Email Intelligence
    $em = $Context.email
    if ($em -and $em.ok -and $em.summary) {
        foreach ($it in @($em.summary.attentionItems)) {
            & $add ([pscustomobject]@{
                    kind = ('email-' + $it.category); source = 'email'; sourceId = [string]$it.messageId
                    title = ("{0} (from {1})" -f $it.subject, $it.from); when = $null
                    text = ("{0} {1}" -f $it.subject, $it.why); attendeeCount = 0; hasLink = $false
                    emailCategory = [string]$it.category; unread = [bool]$it.unread; accounts = @($it.accounts)
                })
        }
    }

    # 3) Action Items - open (not done, not archived); real source ids
    if (Get-Command Get-ActionItemsData -ErrorAction SilentlyContinue) {
        try {
            $cut = $Now.AddDays(-14)
            foreach ($ai in @((Get-ActionItemsData).items | Where-Object { -not $_.done -and -not $_.archived })) {
                $overdue = $false; if ($ai.created) { try { $overdue = ([datetime]$ai.created) -lt $cut } catch { } }
                & $add ([pscustomobject]@{
                        kind = 'action'; source = 'action-items'; sourceId = [string]$ai.id; title = [string]$ai.title
                        when = $null; text = [string]$ai.title; overdue = $overdue; attendeeCount = 0; hasLink = $false
                    })
            }
        } catch { }
    }

    # 4) Current priorities (from the Morning Briefing) - dedup against actions
    foreach ($p in @($Context.priorities)) {
        & $add ([pscustomobject]@{ kind = 'priority'; source = 'priority'; sourceId = $null; title = [string]$p; when = $null; text = [string]$p; attendeeCount = 0; hasLink = $false })
    }

    # 5) Goals - active, not complete (long-horizon; kept visible unless near)
    foreach ($g in @($Context.activeGoals)) {
        & $add ([pscustomobject]@{ kind = 'goal'; source = 'goal'; sourceId = [string]$g.id; title = ("Goal: {0}" -f $g.title); when = $null; text = [string]$g.title; progress = [int]$g.progress; attendeeCount = 0; hasLink = $false })
    }

    # 6) Approved memory that reads like a commitment/follow-up (never a task DB)
    foreach ($m in @($Context.memory)) {
        $v = [string]$m.value
        if (Test-PriWords $v @('call', 'follow up', 'follow-up', 'promised', 'promise', 'remember to', 'reach out', 'check in', 'send', 'owe')) {
            & $add ([pscustomobject]@{ kind = 'memory'; source = 'memory'; sourceId = [string]$m.id; title = $v; when = $null; text = $v; attendeeCount = 0; hasLink = $false })
        }
    }

    # 7) Observations that GUIDE or QUESTION (celebrations are not priorities)
    foreach ($o in @($Context.observations)) {
        if ($o.tone -eq 'guide' -or $o.tone -eq 'question') {
            & $add ([pscustomobject]@{ kind = 'observation'; source = 'observation'; sourceId = $null; title = [string]$o.headline; when = $null; text = ("{0} {1}" -f $o.headline, $o.message); attendeeCount = 0; hasLink = $false })
        }
    }

    $out = @($script:__pc); $script:__pc = $null
    return @($out)
}

# Generic task words that, shared alone, do NOT identify the same commitment
# (so "Review carrier update" and "Review sprint update" stay separate, and
# "Small follow-up number 1..8" stay eight distinct items).
$script:PriGenericWords = @('call', 'meeting', 'review', 'update', 'follow', 'followup', 'task', 'todo', 'prep', 'prepare', 'check', 'send', 'email', 'reply', 'respond', 'note', 'item', 'items', 'work', 'today', 'appointment', 'sync', 'discuss', 'about', 'from', 'with', 'this', 'that', 'your', 'need', 'needs', 'small', 'smaller', 'number', 'reminder', 'reminders', 'thing', 'things', 'stuff', 'misc', 'later', 'soon', 'again')

function Get-PriDistinctiveWords {
    param([string]$Title)
    $words = @((Get-PrioritySignature -Title $Title) -split ' ' | Where-Object { $_ })
    return @($words | Where-Object { $script:PriGenericWords -notcontains $_ })
}

# De-duplicate the SAME commitment appearing in multiple sources. Two items
# merge only when they share DISTINCTIVE words (a name/topic, not a generic
# verb) by subset - so "Call the Millers" (action) + "Millers renewal call"
# (calendar) + "Re: Millers renewal" (email) collapse to one, while unrelated
# or purely-generic titles stay separate. An item with no distinctive word
# never merges (kept separate - no-loss beats a wrong merge). Keeps one
# representative and records every (source, sourceId).
function Merge-PriorityCandidates {
    param($Candidates)
    $clusters = @()
    $rankKind = { param($k) switch -Regex ($k) { 'conflict' { 5 } 'event' { 4 } 'email' { 3 } 'action' { 2 } default { 1 } } }
    foreach ($c in @($Candidates)) {
        $distC = @(Get-PriDistinctiveWords -Title $c.title)
        $matched = $null
        if ($distC.Count -gt 0) {
            foreach ($cl in $clusters) {
                if (@($cl.distinct).Count -eq 0) { continue }
                $inClusterAll = (@($distC | Where-Object { $cl.distinct -contains $_ }).Count -eq $distC.Count)
                $clusterInAll = (@($cl.distinct | Where-Object { $distC -contains $_ }).Count -eq @($cl.distinct).Count)
                if ($inClusterAll -or $clusterInAll) { $matched = $cl; break }
            }
        }
        $ref = [pscustomobject]@{ source = $c.source; sourceId = $c.sourceId }
        if ($matched) {
            $matched.sources = @($matched.sources + $ref)
            $matched.distinct = @(@($matched.distinct + $distC) | Sort-Object -Unique)
            if ((& $rankKind $c.kind) -gt (& $rankKind $matched.rep.kind)) { $matched.rep = $c }
        } else {
            $clusters += [pscustomobject]@{ rep = $c; sources = @($ref); distinct = @($distC) }
        }
    }
    return @($clusters)
}

# Judge one merged item with the Decision Framework (FINAL AUTHORITY) and the
# deterministic signals, and assign a tier + score + a short honest "why".
function Get-PriorityRanking {
    param($Merged, $Context, [datetime]$Now, [bool]$PackedDay = $false)
    $rep = $Merged.rep
    $title = [string]$rep.title
    $text = [string]$rep.text

    # signals
    $isFamily = Test-PriWords $text $script:PriFamilyWords
    $isWaiting = Test-PriWords $text $script:PriWaitingWords
    $isConsequence = Test-PriWords $text $script:PriConsequenceWords
    $isBlocked = Test-PriWords $text $script:PriBlockedWords
    $isOverdue = [bool]($rep.PSObject.Properties.Name -contains 'overdue' -and $rep.overdue)
    $multiSource = (@($Merged.sources).Count -gt 1)

    # Decision Framework judgment (final authority)
    $align = 60; $fwPriority = 'Medium'; $familyConflict = $false
    if (Get-Command Evaluate-TonyDecision -ErrorAction SilentlyContinue) {
        try {
            $j = Evaluate-TonyDecision -Identity $Context.identity -Vision $Context.vision -Goals $Context.goals -Mission $Context.mission `
                -CoreValues $Context.values -AnnualTheme $Context.annualTheme -NonNegotiables @() -Family $null -Health $null -Financial $null `
                -CurrentWorkspace 'Home' -CurrentQuestion $title -OpenTasks $Context.openTasks -RecentAudits @()
            $align = [int]$j.alignmentScore; $fwPriority = [string]$j.priority
            $familyConflict = [bool](@($j.dimensions | Where-Object { $_.name -eq 'Family Impact' -and $_.conflict }).Count -gt 0)
        } catch { }
    }

    # imminent real appointment today (has attendees / is an appointment-type event)
    $isAppt = $false; $apptSoon = $false
    if ($rep.kind -eq 'event') {
        $isAppt = ($rep.attendeeCount -gt 0) -or $rep.hasLink -or (Test-PriWords $title $script:PriApptWords)
        if ($rep.when -and $rep.when -ge $Now -and $rep.when -le $Now.AddHours(3)) { $apptSoon = $true }
    }
    $isClientWaiting = ($rep.kind -like 'email-*' -and ($rep.emailCategory -in @('needs-reply', 'important-contact')) -and ($isWaiting -or $rep.unread)) `
        -or ($isWaiting -and (Test-PriWords $text @('client', 'customer', 'insured', 'prospect', 'policyholder')))

    # ---- tier assignment (Decision Framework shapes it; signals decide urgency) ----
    $tier = 'keep-visible'; $why = 'Captured so it will not be forgotten.'; $flags = @()

    if ($rep.kind -in @('observation', 'memory')) {
        # awareness / standing commitments - kept visible, never elevated to
        # "act now" (they are not dated tasks or waiting people).
        $tier = 'keep-visible'
        $why = if ($rep.kind -eq 'observation') { 'Worth noticing when you have a moment.' } else { 'A commitment you asked me to remember.' }
    }
    elseif ($rep.kind -eq 'conflict') {
        if ($isFamily -or $familyConflict) { $tier = 'act-now'; $why = 'Resolve this conflict - it touches family time (Family before Financial).'; $flags += 'family' }
        else { $tier = 'do-today'; $why = 'A scheduling conflict to resolve before it bites.' }
        $flags += 'conflict'
    }
    elseif ($isFamily -and ($isConsequence -or $familyConflict)) {
        $tier = 'act-now'; $why = 'Protects family time - People matter more than money.'; $flags += 'family'
    }
    elseif ($isClientWaiting -and ($isConsequence -or $isWaiting)) {
        $tier = 'act-now'; $why = 'Someone is waiting on your response.'; $flags += 'waiting'
    }
    elseif ($isAppt -and $apptSoon) {
        $tier = 'act-now'; $why = ('Prepare for the {0} appointment.' -f $rep.when.ToString('h:mm tt')); $flags += 'appointment'
    }
    elseif ($isOverdue -and $isConsequence) {
        $tier = 'act-now'; $why = 'Overdue with a real consequence if it slips further.'; $flags += 'overdue'
    }
    elseif ($rep.kind -like 'email-*' -and $rep.emailCategory -eq 'carrier-underwriting') {
        $tier = 'do-today'; $why = 'Carrier / underwriting update to review.'; $flags += 'carrier'
    }
    elseif ($isAppt) {
        $tier = 'do-today'; $why = ('An appointment later today{0}.' -f $(if ($rep.when) { ' at ' + $rep.when.ToString('h:mm tt') } else { '' })); $flags += 'appointment'
    }
    elseif ($isClientWaiting -or ($rep.kind -like 'email-*' -and $rep.emailCategory -in @('needs-reply', 'important-contact', 'urgent'))) {
        $tier = 'do-today'; $why = 'A person is expecting a reply.'; $flags += 'waiting'
    }
    elseif ($isOverdue) {
        $tier = 'do-today'; $why = 'Has been open a while - worth closing today.'; $flags += 'overdue'
    }
    elseif ($isBlocked) {
        $tier = 'do-today'; $why = 'Blocked work - unblocking it frees other things.'; $flags += 'blocked'
    }
    elseif ($rep.kind -in @('action', 'priority') -and $fwPriority -eq 'High') {
        $tier = 'do-today'; $why = 'Aligned with what matters most right now.'
    }
    elseif ($rep.kind -eq 'goal') {
        if ($rep.PSObject.Properties.Name -contains 'progress' -and $rep.progress -ge 70) { $tier = 'do-today'; $why = ('Close to done ({0}%) - a focused push finishes it.' -f $rep.progress) }
        else { $tier = 'keep-visible'; $why = 'A goal to keep alive - no action forced today.' }
    }
    else {
        $tier = 'keep-visible'
        $why = switch ($rep.kind) {
            'observation' { 'Worth noticing when you have a moment.' }
            'memory' { 'A commitment you asked me to remember.' }
            'email-newsletter-promo' { 'Low priority.' }
            default { 'Captured and visible; not urgent.' }
        }
    }

    # framework can DEMOTE (never silently drop): a low-alignment, low-priority
    # item with no urgency signal settles into Keep Visible.
    if ($tier -eq 'do-today' -and $fwPriority -eq 'Low' -and -not ($isConsequence -or $isWaiting -or $isOverdue -or $isBlocked)) { $tier = 'keep-visible'; $why = 'Legitimate but not pressing - kept visible.' }

    # A stated morning priority is at least "Do today" - it is the day's plan.
    if ($tier -eq 'keep-visible' -and (@($Merged.sources | Where-Object { $_.source -eq 'priority' }).Count -gt 0)) { $tier = 'do-today'; $why = "One of today's stated priorities." }

    # score for ordering within a tier
    $score = $align
    if ($isFamily) { $score += 40 }
    if ('waiting' -in $flags) { $score += 30 }
    if ($isConsequence) { $score += 25 }
    if ($apptSoon) { $score += 20 }
    if ($isOverdue) { $score += 15 }
    if ($multiSource) { $score += 10 }

    return [pscustomobject]@{
        title = $title; why = $why; tier = $tier; score = $score; flags = @($flags)
        kind = $rep.kind; when = $rep.when; sources = @($Merged.sources); alignment = $align; frameworkPriority = $fwPriority
    }
}

# ---- THE engine: the ranked, deduped, no-loss priority plan --------
function Get-ExecutivePriorities {
    param($Context, [datetime]$Now = (Get-Date))
    $packed = $false
    try { if ($Context.calendar -and $Context.calendar.ok -and $Context.calendar.insights.today.meetingHeavy) { $packed = $true } } catch { }

    $candidates = @(Get-PriorityCandidates -Context $Context -Now $Now)
    # separate routine time-blocks (schedule, not to-dos) - neither ranked nor noise
    $routine = @($candidates | Where-Object { Test-PriRoutineBlock $_ })
    $rankable = @($candidates | Where-Object { -not (Test-PriRoutineBlock $_) })

    $merged = @(Merge-PriorityCandidates -Candidates $rankable)
    $ranked = @($merged | ForEach-Object { Get-PriorityRanking -Merged $_ -Context $Context -Now $Now -PackedDay $packed })

    # obvious noise (promotions/newsletters) is already separated by Email
    # Intelligence; represent its COUNT so it is acknowledged, never silently
    # dropped. Anything the engine tagged low-value also lands here.
    $lowValueEmailCount = 0
    try { if ($Context.email -and $Context.email.ok -and $Context.email.summary) { $lowValueEmailCount = [int]$Context.email.summary.lowPriority } } catch { }

    $actNow = @($ranked | Where-Object { $_.tier -eq 'act-now' } | Sort-Object score -Descending)
    $doToday = @($ranked | Where-Object { $_.tier -eq 'do-today' } | Sort-Object score -Descending)
    $keepVisible = @($ranked | Where-Object { $_.tier -eq 'keep-visible' } | Sort-Object score -Descending)

    # Avoid making a packed day busier: cap "Act first" (2 on a heavy day, else
    # 3); overflow drops to "Also today" - it is NOT lost.
    $actCap = if ($packed) { 2 } else { 3 }
    if ($actNow.Count -gt $actCap) { $overflow = @($actNow | Select-Object -Skip $actCap); $actNow = @($actNow | Select-Object -First $actCap); $doToday = @($doToday + $overflow | Sort-Object score -Descending) }

    # brief "why the top were selected"
    $topFlags = @($actNow | ForEach-Object { $_.flags } | ForEach-Object { $_ } | Select-Object -Unique)
    $reasonBits = @()
    if ('family' -in $topFlags) { $reasonBits += 'a family-time conflict' }
    if ('waiting' -in $topFlags) { $reasonBits += 'someone waiting on you' }
    if ('appointment' -in $topFlags) { $reasonBits += 'an imminent appointment' }
    if ('overdue' -in $topFlags -or 'conflict' -in $topFlags) { $reasonBits += 'a real deadline or conflict' }
    $reason = if ($reasonBits.Count -gt 0) { 'Chosen because they involve ' + ((($reasonBits | Select-Object -First 3) -join ', ') -replace ',([^,]*)$', ' and$1') + '.' } else { $null }

    $guidanceNote = if ($packed) { "It's a full day - I kept 'Act first' short so today doesn't get busier." } else { $null }

    $legitimateCount = $actNow.Count + $doToday.Count + $keepVisible.Count
    return [pscustomobject]@{
        source          = 'executive-priority'
        generatedAt     = $Now
        actNow          = @($actNow)
        doToday         = @($doToday)
        keepVisible     = @($keepVisible)
        lowValueNoise   = [pscustomobject]@{ emailCount = $lowValueEmailCount; note = 'Promotions/newsletters and clear noise, set aside but counted.' }
        scheduleBlocks  = @($routine | ForEach-Object { $_.title })   # routine blocks live in Today's Schedule
        counts          = [pscustomobject]@{ actNow = $actNow.Count; doToday = $doToday.Count; keepVisible = $keepVisible.Count; lowValueNoise = $lowValueEmailCount; legitimate = $legitimateCount; candidates = $candidates.Count }
        reason          = $reason
        guidanceNote    = $guidanceNote
        packedDay       = $packed
        # no-loss invariant: every rankable candidate lands in a visible tier
        noLoss          = ($legitimateCount -eq @($merged).Count)
    }
}
