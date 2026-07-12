# =====================================================================
# executive-briefing.ps1  —  Tony's Executive Briefing (the morning letter)
# ---------------------------------------------------------------------
# The single best moment in GIOK: Tony beginning the day as an executive
# chief of staff. Not another dashboard - a short, personal letter that
# is calm, confident, encouraging, honest, and executive. Never
# overwhelming, never robotic, never just a list.
#
# It is composed ENTIRELY from the Executive Context Engine
# (Get-TonyExecutiveContext) - the single source of situational
# awareness. It creates no new context object, stores nothing, and
# writes nothing. Pure read-and-compose over the source of truth.
#
# Sections: Greeting - Today's Executive Summary (<=3 sentences: what
# matters, biggest opportunity, biggest risk) - Top Three Priorities
# (ranked, each with a WHY) - exactly ONE Observation - Today's Focus
# (one sentence) - One Encouragement (short, human, never cheesy).
# =====================================================================

$ErrorActionPreference = 'Stop'

function Get-BriefingGreeting {
    param([string]$PartOfDay, [string]$Name)
    $n = $Name; if ($n) { $n = ", $n" }
    switch ($PartOfDay) {
        'morning'   { "Good morning$n." }
        'afternoon' { "Good afternoon$n." }
        'evening'   { "Good evening$n." }
        default     { "Still at it$n." }   # night
    }
}

# Today's Executive Summary - at most three sentences: what matters, the
# biggest opportunity, the biggest risk. Honest, never alarmist.
function Get-BriefingSummary {
    param($Exec)
    $a = $Exec.assessment
    $priorities = @($Exec.priorities)

    if ($priorities.Count -gt 0) { $s1 = ('Today is mostly about "{0}".' -f $priorities[0]) }
    else { $s1 = 'Today is open - a good day to get out ahead of what matters most.' }

    $nearGoal = @($Exec.activeGoals | Where-Object { $null -ne $_.progress -and [int]$_.progress -ge 70 } | Select-Object -First 1)
    if ($nearGoal.Count -gt 0) { $s2 = ('Your biggest opportunity is "{0}" - close enough to finish with one focused push.' -f $nearGoal[0].title) }
    elseif ($a.makingProgress.any) { $s2 = ('The momentum is real ({0}), so today is a chance to build on it.' -f $a.makingProgress.reasons[0]) }
    else { $s2 = 'The opportunity today is simply to move the vital few forward before the noise arrives.' }

    if ($a.conflict.any) { $s3 = ('The risk to watch: {0}' -f $a.conflict.items[0]) }
    elseif ($a.offTrack.any) { $s3 = ('The one thing to keep an eye on: {0}.' -f $a.offTrack.reasons[0]) }
    elseif ($a.overdue.any) { $s3 = ('The only real risk is letting {0} older item(s) keep drifting.' -f $a.overdue.count) }
    else { $s3 = 'The only real risk today is letting a full list crowd out the few things that actually matter.' }

    return [pscustomobject]@{
        text        = (($s1, $s2, $s3) -join ' ')
        mattersMost = $a.whatMattersMost
        opportunity = $s2
        risk        = $s3
    }
}

# The WHY behind a priority - grounded in a real goal when the words line
# up, otherwise in the annual theme or an honest rank-based reason. Never
# fabricated specificity.
function Get-PriorityReason {
    param([string]$Title, $Goals, $AnnualTheme, [int]$Rank)
    $tl = ($Title.ToLower() -replace '[^a-z0-9 ]', ' ')
    $words = @($tl -split '\s+' | Where-Object { $_.Length -gt 3 })
    foreach ($g in @($Goals)) {
        $gt = ([string]$g.title).ToLower()
        foreach ($w in $words) { if ($gt -match [regex]::Escape($w)) { return ('Moves your goal "{0}" forward - that''s why it earns a top slot today.' -f $g.title) } }
    }
    switch ($Rank) {
        1 { 'Your top open item - clearing it first makes everything after it easier.' }
        2 { 'Keeps real momentum going without waiting on anything else to happen.' }
        default {
            if ($AnnualTheme -and $AnnualTheme.description) { ('Worth moving today so it stays consistent with this year''s focus.') }
            else { 'Worth moving today so it doesn''t quietly become tomorrow''s fire.' }
        }
    }
}

function Get-BriefingPriorities {
    param($Exec)
    $out = @()
    $rank = 1
    foreach ($p in @($Exec.priorities | Select-Object -First 3)) {
        $out += [pscustomobject]@{ rank = $rank; title = $p; why = (Get-PriorityReason -Title $p -Goals $Exec.goals -AnnualTheme $Exec.annualTheme -Rank $rank) }
        $rank++
    }
    return @($out)
}

# Today's Focus - one sentence, shaped by the moment.
function Get-BriefingFocus {
    param($Exec)
    $a = $Exec.assessment
    if ($a.conflict.any) { return 'If today goes well, it will be because you kept family ahead of the work when it counted.' }
    if ($Exec.time.partOfDay -eq 'morning') { return 'If today goes well, it will be because you protected your morning focus before the day filled up.' }
    if (@($Exec.priorities).Count -gt 0) { return ('If today goes well, it will be because you moved "{0}" forward instead of chasing the noise.' -f $Exec.priorities[0]) }
    return 'If today goes well, it will be because you did a few important things well - not many things frantically.'
}

# One Encouragement - short, human, never cheesy. Deterministic by day so
# it varies without randomness.
function Get-BriefingEncouragement {
    param([datetime]$Now)
    $lines = @(
        'Progress compounds.',
        "You don't have to do everything today - you only need to move the important things forward.",
        "Consistency over intensity. That's the whole game.",
        'Small, on-time, boring wins add up faster than heroics.',
        "Do the next right thing. That's always enough.",
        'Better, not busy.',
        'The disciplined day is the one you barely notice - it just gets done.'
    )
    return $lines[($Now.DayOfYear % $lines.Count)]
}

# THE briefing. Consumes the single Executive Context (never creates a new
# Today's Schedule for the briefing - composed from Calendar Intelligence
# (Calendar Provider). Returns $null unless a live, ok calendar signal was
# provided (never fetched here). Calm and specific: what today holds and the
# one block worth protecting.
function Get-BriefingSchedule {
    param($Calendar)
    if (-not $Calendar -or -not $Calendar.ok -or -not $Calendar.insights) { return $null }
    $t = $Calendar.insights.today
    $firstTxt = if ($t.firstMeeting) { ('{0} at {1}' -f $t.firstMeeting.title, $t.firstMeeting.start.ToString('h:mm tt')) } else { $null }
    $freeTxt = if ($t.longestFreeBlock) { ('{0}-{1} ({2} min)' -f $t.longestFreeBlock.start.ToString('h:mm tt'), $t.longestFreeBlock.end.ToString('h:mm tt'), $t.longestFreeBlock.minutes) } else { $null }

    if ($t.totalMeetings -eq 0) {
        $line = 'No meetings on the calendar today - the day is yours to shape.'
    } else {
        $plural = if ($t.totalMeetings -eq 1) { '' } else { 's' }
        $line = ('{0} meeting{1} today' -f $t.totalMeetings, $plural)
        if ($firstTxt) { $line += (', starting with ' + $firstTxt) }
        if ($t.lastMeeting) { $line += ('; the last wraps up by ' + $t.lastMeeting.end.ToString('h:mm tt')) }
        $line += '.'
    }
    $guidance = $null
    if ($t.meetingHeavy) { $guidance = 'A meeting-heavy day - protect the gaps for recovery, not more work.' }
    elseif ($freeTxt) { $guidance = ('Your clearest focus block is ' + $freeTxt + ' - worth protecting for deep work.') }

    return [pscustomobject]@{
        line             = $line
        totalMeetings    = $t.totalMeetings
        firstMeeting     = $firstTxt
        lastMeeting      = if ($t.lastMeeting) { $t.lastMeeting.end.ToString('h:mm tt') } else { $null }
        longestFreeBlock = $freeTxt
        meetingHeavy     = $t.meetingHeavy
        guidance         = $guidance
    }
}

# Today's Email - the Executive Email Summary folded into the briefing.
# Composed from the Email Provider's summary (Email Intelligence). Returns
# $null unless a live, ok email signal was provided (never fetched here).
# Calm and specific: what deserves attention, and permission to let the
# rest wait - never a list of every email.
function Get-BriefingInbox {
    param($Email)
    if (-not $Email -or -not $Email.ok -or -not $Email.summary) { return $null }
    $s = $Email.summary
    $guidance = if ($s.needsAttention -eq 0) { 'Your inbox is calm - nothing needs you right now.' }
    elseif ($s.needsAttention -eq 1) { 'Clear the one that needs you, then let the rest wait.' }
    else { ('Clear the {0} that need you, then let the rest wait.' -f $s.needsAttention) }
    return [pscustomobject]@{
        line           = $s.line
        sentences      = @($s.sentences)
        summaryText    = $s.summaryText
        needsAttention = $s.needsAttention
        waitingForReply = $s.waitingForReply
        invitations    = $s.invitations
        attentionItems = @($s.attentionItems)
        guidance       = $guidance
    }
}

# Today's Priorities - the Executive Priority Engine folded into the letter as
# "Act first / Also today / Still visible" (D18). Ranks the real items from
# every source, guarantees nothing legitimate is lost, and stays calm.
# Returns $null when the engine or context is unavailable.
function Get-BriefingPriorityPlan {
    param($Context, [datetime]$Now = (Get-Date))
    if (-not $Context -or -not (Get-Command Get-ExecutivePriorities -ErrorAction SilentlyContinue)) { return $null }
    $p = Get-ExecutivePriorities -Context $Context -Now $Now

    $actFirst = @(); $rank = 1
    foreach ($i in @($p.actNow)) { $actFirst += [pscustomobject]@{ rank = $rank; title = $i.title; why = $i.why }; $rank++ }

    $alsoAll = @($p.doToday)
    $alsoToday = @($alsoAll | Select-Object -First 5 | ForEach-Object { [pscustomobject]@{ title = $_.title; why = $_.why } })
    $alsoOverflow = [math]::Max(0, $alsoAll.Count - 5)

    # "Still visible" - one calm sentence that acknowledges every low-priority
    # legitimate item so nothing is silently forgotten.
    $kv = @($p.keepVisible)
    $kvCount = $kv.Count + $alsoOverflow
    $stillVisible = $null
    if ($kvCount -gt 0) {
        $reminders = @($kv | Where-Object { $_.kind -in @('memory', 'observation', 'goal') }).Count
        $followups = $kvCount - $reminders
        $parts = @()
        if ($followups -gt 0) { $parts += ('{0} smaller follow-up{1}' -f $followups, $(if ($followups -eq 1) { '' } else { 's' })) }
        if ($reminders -gt 0) { $parts += ('{0} non-urgent reminder{1}' -f $reminders, $(if ($reminders -eq 1) { '' } else { 's' })) }
        $joined = if ($parts.Count -gt 0) { $parts -join ' and ' } else { ('{0} item{1}' -f $kvCount, $(if ($kvCount -eq 1) { '' } else { 's' })) }
        $stillVisible = ('{0} {1} captured and won''t be forgotten.' -f $joined, $(if ($kvCount -eq 1) { 'is' } else { 'are' }))
    }

    $setAside = $null
    if ($p.lowValueNoise.emailCount -gt 0) { $setAside = ('{0} promotional/newsletter email{1} set aside (still counted).' -f $p.lowValueNoise.emailCount, $(if ($p.lowValueNoise.emailCount -eq 1) { '' } else { 's' })) }

    return [pscustomobject]@{
        actFirst         = @($actFirst)
        alsoToday        = @($alsoToday)
        stillVisible     = $stillVisible
        keepVisibleCount = $kvCount
        setAside         = $setAside
        reason           = $p.reason
        guidanceNote     = $p.guidanceNote
        packedDay        = $p.packedDay
        empty            = ($actFirst.Count -eq 0 -and $alsoToday.Count -eq 0 -and $kvCount -eq 0)
        counts           = $p.counts
        noLoss           = $p.noLoss
    }
}

# Over time - the Executive Timeline folded into the letter as a few calm
# notes about what is new / aging / overdue / waiting / expiring (D19). Reads
# only existing timestamps (Action Items, Calendar RSVP, aging unread Gmail,
# the last audit); fetches aging mail read-only only when Gmail is connected.
# Returns $null when there's nothing worth noticing (no noise).
function Get-BriefingTimeline {
    param($Context, [datetime]$Now = (Get-Date))
    if (-not $Context -or -not (Get-Command Get-ExecutiveTimeline -ErrorAction SilentlyContinue)) { return $null }
    $waiting = $null
    if ((Get-Command Get-EmailWaiting -ErrorAction SilentlyContinue) -and (Get-Command Get-GmailStatus -ErrorAction SilentlyContinue)) {
        try { if ((Get-GmailStatus).state -eq 'connected') { $waiting = Get-EmailWaiting -Now $Now } } catch { $waiting = $null }
    }
    $tl = Get-ExecutiveTimeline -Context $Context -Now $Now -WaitingEmails $waiting
    if (-not $tl.hasAny) { return $null }
    return [pscustomobject]@{ notes = @($tl.notes | ForEach-Object { $_.text }); counts = $tl.counts }
}

# Waiting for review - one calm line about the Executive Inbox (Stage 8). Reads
# the read-only inbox awareness the context already carries; mentions the count
# and how many are time-sensitive, never a list of proposals. Returns $null when
# nothing is pending (Tony simply says nothing about it).
function Get-BriefingInboxReview {
    param($Exec)
    $ib = if ($Exec -and ($Exec.PSObject.Properties.Name -contains 'inbox')) { $Exec.inbox } else { $null }
    if (-not $ib -or [int]$ib.pending -le 0) { return $null }
    $n = [int]$ib.pending
    $ts = [int]$ib.timeSensitiveCount
    $line = ('The Workforce prepared {0} item{1} for your review.' -f $n, $(if ($n -eq 1) { '' } else { 's' }))
    if ($ts -gt 0) { $line += (' {0} {1} time-sensitive.' -f $ts, $(if ($ts -eq 1) { 'is' } else { 'are' })) }
    else { $line += ' None are urgent - review them when it suits you.' }
    return [pscustomobject]@{ line = $line; pending = $n; timeSensitive = $ts }
}

# Life focus - one calm, life-aware line (occasionally two), surfaced ONLY when
# something is genuinely worth Jake's attention now (Tier 1 feedback loop). Reads
# the read-only life digest the context already carries. Never medical/legal/tax/
# investment advice, never invented urgency; omitted when nothing is relevant. To
# avoid repeating the same unchanged line daily it rotates among eligible
# observations by day-of-year and leans on date/`updated` timestamps (no new store).
function Get-BriefingLifeFocus {
    param($Exec)
    $ld = if ($Exec -and ($Exec.PSObject.Properties.Name -contains 'lifeDigest')) { $Exec.lifeDigest } else { $null }
    if (-not $ld) { return $null }
    $now = if ($Exec.generatedAt) { [datetime]$Exec.generatedAt } else { (Get-Date) }
    $busy = $false
    $cal = if ($Exec.PSObject.Properties.Name -contains 'calendar') { $Exec.calendar } else { $null }
    if ($cal -and $cal.ok -and $cal.insights -and $cal.insights.today) { $busy = [bool]$cal.insights.today.meetingHeavy }
    $whenTxt = { param($d) if ($d -eq 0) { 'today' } elseif ($d -eq 1) { 'tomorrow' } else { ('in {0} days' -f $d) } }
    $obs = @()
    # 1) a family commitment this week worth protecting (Family before Financial)
    $fam = @($ld.family.upcoming | Where-Object { $null -ne $_.daysAway -and $_.daysAway -le 7 } | Sort-Object daysAway)
    if ($fam.Count -gt 0) { $obs += [pscustomobject]@{ p = 1; text = ('You have a family commitment this week worth protecting: {0} ({1}).' -f $fam[0].title, (& $whenTxt $fam[0].daysAway)) } }
    # 2) a financial due/review date approaching (<= 14 days) - surfaced, never advised on
    $fin = @($ld.financial.items | Where-Object { $null -ne $_.daysAway -and $_.daysAway -ge 0 -and $_.daysAway -le 14 } | Sort-Object daysAway)
    if ($fin.Count -gt 0) { $obs += [pscustomobject]@{ p = 2; text = ('A financial item is coming up: {0}{1} - due {2}.' -f $fin[0].title, $(if ($fin[0].amount) { ' ' + $fin[0].amount } else { '' }), (& $whenTxt $fin[0].daysAway)) } }
    # 3) a health goal with a clear next step but a full day
    $hg = @($ld.health.goals | Where-Object { $_.nextStep })
    if ($hg.Count -gt 0 -and $busy) { $obs += [pscustomobject]@{ p = 3; text = ('Your health goal "{0}" has a clear next step, but the day is full - protect a little time for it.' -f $hg[0].title) } }
    # 4) a learning goal that hasn't moved recently (uses the goal's own `updated` timestamp)
    foreach ($g in @($ld.learning.goals | Where-Object { [int]$_.progress -lt 100 })) {
        $stale = $false; try { $stale = ((($now - [datetime]$g.updated).TotalDays) -ge 14) } catch { $stale = $false }
        if ($stale) { $obs += [pscustomobject]@{ p = 4; text = ('Your learning goal "{0}" hasn''t moved recently - one small next step would keep momentum.' -f $g.title) }; break }
    }
    if (@($obs).Count -eq 0) { return $null }
    $obs = @($obs | Sort-Object p)
    $picks = @($obs[0].text)   # the highest-value (date-anchored where present)
    if (@($obs).Count -gt 1) { $rest = @($obs[1..($obs.Count - 1)]); $picks += $rest[[int]($now.DayOfYear % $rest.Count)].text }   # rotate the second to avoid daily sameness
    return @($picks)
}

# one) and composes the letter model. Data only - no UI, no writes.
function Get-TonyExecutiveBriefing {
    param(
        [string]$CurrentWorkspace = 'Home',
        [datetime]$Now = (Get-Date),
        [string]$Name = 'Jake',
        $ExecutiveContext = $null,
        $Calendar = $null,  # optional live calendar signal (passed in when connected); never fetched here
        $Email = $null      # optional live email signal (passed in when connected); never fetched here
    )
    $exec = $ExecutiveContext
    if (-not $exec -and (Get-Command Get-TonyExecutiveContext -ErrorAction SilentlyContinue)) {
        $ls = @{}
        if ($Calendar) { $ls['calendar'] = $Calendar }
        if ($Email) { $ls['email'] = $Email }
        $exec = Get-TonyExecutiveContext -CurrentWorkspace $CurrentWorkspace -CurrentQuestion 'Prepare my executive briefing for today.' -Now $Now -LiveSignals $ls
    }
    if (-not $exec) { return $null }

    $first = (([string]$Name).Trim() -split '\s+')[0]
    $partOfDay = $exec.time.partOfDay

    $observation = $null
    $topObs = @($exec.observations | Select-Object -First 1)
    if ($topObs.Count -gt 0) {
        $o = $topObs[0]
        $observation = [pscustomobject]@{ headline = $o.headline; message = $o.message; why = $o.why; tone = $o.tone; confidence = $o.confidence; category = $o.category }
    }

    return [pscustomobject]@{
        source        = 'executive-briefing'
        generatedAt   = $Now
        dateText      = $Now.ToString('dddd, MMMM d, yyyy')
        timeText      = $Now.ToString('h:mm tt')
        partOfDay     = $partOfDay
        greeting      = (Get-BriefingGreeting -PartOfDay $partOfDay -Name $first)
        summary       = (Get-BriefingSummary -Exec $exec)
        schedule      = (Get-BriefingSchedule -Calendar $Calendar)
        emailSummary  = (Get-BriefingInbox -Email $Email)
        priorityPlan  = (Get-BriefingPriorityPlan -Context $exec -Now $Now)
        priorities    = (Get-BriefingPriorities -Exec $exec)
        timeline      = (Get-BriefingTimeline -Context $exec -Now $Now)
        observation   = $observation
        inboxReview   = (Get-BriefingInboxReview -Exec $exec)
        lifeFocus     = (Get-BriefingLifeFocus -Exec $exec)
        focus         = (Get-BriefingFocus -Exec $exec)
        encouragement = (Get-BriefingEncouragement -Now $Now)
        # reference back to the single context (not a copy) for any consumer that wants detail
        context       = $exec
    }
}
