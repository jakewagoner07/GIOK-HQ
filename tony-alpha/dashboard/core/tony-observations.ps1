# =====================================================================
# tony-observations.ps1  —  Tony's Observation Engine
# ---------------------------------------------------------------------
# Tony notices patterns. Not reminders. Not notifications. OBSERVATIONS -
# the quiet, caring noticing a great chief of staff does over time.
#
# It reads existing sources (End of Day Audits, Action Items, Journal,
# Identity, Goals, Mission, Annual Theme, Morning Briefings) and looks
# for patterns: repeated postponements, positive/negative habits,
# momentum, balance, time allocation (family vs work), consistency,
# progress, and recurring obstacles.
#
# Rules (non-negotiable): never criticize, never shame. Celebrate wins,
# offer guidance, and always explain WHY the observation matters. Every
# observation carries an internal confidence (High/Medium/Low); LOW
# confidence is presented as a question, never a statement.
#
# Deterministic heuristics - no AI, no notifications, no writes. Pure
# read-and-notice over the single source of truth.
# =====================================================================

$ErrorActionPreference = 'Stop'

# Gather everything the detectors read - once, referenced not duplicated.
function Get-ObservationContext {
    $ctx = [pscustomobject]@{
        audits = @(); latest = $null; prev = $null; daysOfData = 0
        actions = @(); goals = @(); mission = $null; theme = $null; journal = @(); nonNegDefs = @()
    }
    if (Get-Command Get-AuditHistory -ErrorAction SilentlyContinue) {
        try { $ctx.audits = @(Get-AuditHistory | Where-Object { $_ -and $_.savedAt }) } catch { }
    }
    $ctx.daysOfData = @($ctx.audits).Count
    if ($ctx.daysOfData -ge 1) { $ctx.latest = $ctx.audits[0] }
    if ($ctx.daysOfData -ge 2) { $ctx.prev = $ctx.audits[1] }
    if (Get-Command Get-ActionItemsData     -ErrorAction SilentlyContinue) { try { $ctx.actions = @((Get-ActionItemsData).items) } catch { } }
    if (Get-Command Get-IdentityGoals       -ErrorAction SilentlyContinue) { try { $g = Get-IdentityGoals; if ($g) { $ctx.goals = @($g.goals) } } catch { } }
    if (Get-Command Get-IdentityMission     -ErrorAction SilentlyContinue) { try { $ctx.mission = Get-IdentityMission } catch { } }
    if (Get-Command Get-IdentityAnnualTheme -ErrorAction SilentlyContinue) { try { $ctx.theme = Get-IdentityAnnualTheme } catch { } }
    if (Get-Command Get-IdentityJournal     -ErrorAction SilentlyContinue) { try { $jj = Get-IdentityJournal; if ($jj) { $ctx.journal = @($jj.entries) } } catch { } }
    if (Get-Command Get-NonNegotiableDefs   -ErrorAction SilentlyContinue) { try { $ctx.nonNegDefs = @(Get-NonNegotiableDefs) } catch { } }
    return $ctx
}

# One observation. tone: celebrate | guide | question. Low confidence is
# always presented as a question - Tony wonders aloud, never asserts.
function New-Observation {
    param(
        [string]$Id, [string]$Category, [string]$Headline, [string]$Message, [string]$Why,
        [ValidateSet('High', 'Medium', 'Low')][string]$Confidence,
        [ValidateSet('celebrate', 'guide', 'question')][string]$Tone,
        [int]$Impact, [string[]]$Sources
    )
    if ($Confidence -eq 'Low') { $Tone = 'question' }   # low confidence -> a question, not a claim
    return [pscustomobject]@{
        id = $Id; category = $Category; headline = $Headline; message = $Message; why = $Why
        confidence = $Confidence; tone = $Tone; impact = $Impact; sources = @($Sources)
    }
}

# ------------------------------------------------------------------ #
# DETECTORS  -  each returns one observation or $null. Never criticizes.
# Confidence scales with how much history backs the pattern.
# ------------------------------------------------------------------ #

# Positive habit / consistency: are the non-negotiables getting hit?
function Find-ObsNonNegotiableStreak {
    param($Ctx)
    if (-not $Ctx.latest) { return $null }
    $defs = @($Ctx.nonNegDefs); if ($defs.Count -eq 0) { return $null }
    $nn = $Ctx.latest.nonNegotiables
    $done = @($defs | Where-Object { $nn.($_.key) }).Count
    $total = $defs.Count
    $ratio = if ($total -gt 0) { $done / [double]$total } else { 0 }
    if ($ratio -lt 0.6) { return $null }   # only the positive pattern here; struggles are handled gently elsewhere
    $conf = if ($Ctx.daysOfData -ge 3) { 'High' } else { 'Medium' }
    $famNote = if ($nn.familyTime) { ', including family time' } else { '' }
    $msg = "You've been doing a great job staying on your non-negotiables - $done of $total yesterday$famNote. That's the boring discipline that quietly compounds."
    $why = 'Consistency on the non-negotiables is what builds the life you are aiming at - it protects health, family, and momentum before the day''s noise arrives.'
    return (New-Observation -Id 'obs-nonneg-streak' -Category 'Consistency' -Headline 'Your non-negotiables are holding' -Message $msg -Why $why -Confidence $conf -Tone 'celebrate' -Impact (72 + [int]($ratio * 10)) -Sources @('End of Day Audit'))
}

# Balance / time allocation: family vs work. Family comes before Financial.
function Find-ObsFamilyWorkBalance {
    param($Ctx)
    if (-not $Ctx.latest) { return $null }
    $s = $Ctx.latest.scores
    $fam = [int]$s.family; $biz = [int]$s.business; $fin = [int]$s.financial
    $workLead = [math]::Max($biz, $fin) - $fam
    if ($workLead -lt 2) { return $null }   # only speak up when work is clearly running ahead
    $famTimeHit = $Ctx.latest.nonNegotiables.familyTime
    $conf = if ($Ctx.daysOfData -ge 3) { 'Medium' } else { 'Low' }   # thin history -> a question
    $ackn = if ($famTimeHit) { "You still protected family time, which is the part that matters most" } else { "Family time is the margin worth guarding" }
    $msg = "It looks like work ran a little ahead of family yesterday (work $([math]::Max($biz,$fin)) vs family $fam). $ackn - worth protecting that same margin again today?"
    $why = 'Family comes before financial. The small daily margins for family are what keep the business from quietly eating the life it is meant to support.'
    return (New-Observation -Id 'obs-family-balance' -Category 'Family vs Work' -Headline 'Keeping family ahead of the work' -Message $msg -Why $why -Confidence $conf -Tone 'guide' -Impact (70 + $workLead * 2) -Sources @('End of Day Audit'))
}

# Progress: a goal that's close to the finish line.
function Find-ObsGoalProgress {
    param($Ctx)
    $goals = @($Ctx.goals | Where-Object { $null -ne $_.progress })
    if ($goals.Count -eq 0) { return $null }
    $top = $goals | Sort-Object { [int]$_.progress } -Descending | Select-Object -First 1
    $p = [int]$top.progress
    if ($p -lt 60 -or $p -ge 100) { return $null }
    $msg = "You're at $p% on ""$($top.title)"" - closer than it probably feels. Want to map the last push?"
    $why = 'Naming the goal that is nearly there turns steady progress into a finish - the final stretch is where momentum pays off.'
    return (New-Observation -Id 'obs-goal-progress' -Category 'Progress' -Headline 'A goal within reach' -Message $msg -Why $why -Confidence 'Medium' -Tone 'guide' -Impact (60 + [int]($p / 5)) -Sources @('Goals', 'Identity'))
}

# A goal that appears stalled - offered as a gentle question, never a rebuke.
function Find-ObsStalledGoal {
    param($Ctx)
    $goals = @($Ctx.goals | Where-Object { $null -ne $_.progress })
    if ($goals.Count -eq 0) { return $null }
    $low = $goals | Sort-Object { [int]$_.progress } | Select-Object -First 1
    $p = [int]$low.progress
    if ($p -gt 45 -or $p -le 0) { return $null }
    $msg = "I noticed ""$($low.title)"" is sitting around $p%. Is it waiting on something, or would a single next step get it moving?"
    $why = 'A goal that stops moving usually needs one unblocking step, not more pressure - naming it gently is how it gets unstuck.'
    return (New-Observation -Id 'obs-goal-stalled' -Category 'Progress' -Headline 'A goal that went quiet' -Message $msg -Why $why -Confidence 'Low' -Tone 'question' -Impact 54 -Sources @('Goals'))
}

# Momentum: action items getting done.
function Find-ObsActionMomentum {
    param($Ctx)
    $items = @($Ctx.actions | Where-Object { -not $_.archived })
    if ($items.Count -eq 0) { return $null }
    $done = @($items | Where-Object { $_.done }).Count
    $open = @($items | Where-Object { -not $_.done }).Count
    if ($done -lt 5) { return $null }
    $conf = 'Medium'
    $tail = if ($open -ge 20) { " There are $open still open - want me to help you pick the vital few?" } else { '' }
    $msg = "I've been seeing real momentum - $done action items done.$tail"
    $why = 'Completed work is the clearest signal of momentum; protecting a short list of the vital few keeps that momentum from scattering.'
    return (New-Observation -Id 'obs-action-momentum' -Category 'Momentum' -Headline 'Momentum on your action items' -Message $msg -Why $why -Confidence $conf -Tone 'celebrate' -Impact 60 -Sources @('Action Items'))
}

# Negative habit, handled with care: the couple of non-negotiables that slipped.
function Find-ObsSlippedHabits {
    param($Ctx)
    if (-not $Ctx.latest) { return $null }
    $defs = @($Ctx.nonNegDefs); if ($defs.Count -eq 0) { return $null }
    $nn = $Ctx.latest.nonNegotiables
    $missed = @($defs | Where-Object { -not $nn.($_.key) } | ForEach-Object { $_.name })
    if ($missed.Count -eq 0 -or $missed.Count -gt 3) { return $null }   # a targeted nudge, not a pile-on
    $list = ($missed -join ' and ')
    $msg = "I noticed $list didn't get checked off yesterday. One full day, or something worth protecting tonight?"
    $why = 'The quiet compounders - sleep, reading, recovery - are easy to skip and expensive to lose over time; a gentle check keeps them from slipping unnoticed.'
    return (New-Observation -Id 'obs-slipped-habits' -Category 'Habits' -Headline 'A couple of habits slipped' -Message $msg -Why $why -Confidence 'Low' -Tone 'question' -Impact 56 -Sources @('End of Day Audit'))
}

# Repeated postponement / recurring obstacle: the same task pushed across days,
# or an item that has lingered open a long time.
function Find-ObsRepeatedPostponement {
    param($Ctx)
    # 1) tasks moved to tomorrow across multiple audit days
    $counts = @{}
    foreach ($a in @($Ctx.audits)) { foreach ($id in @($a.movedToTomorrow)) { if ($id) { $counts[$id] = 1 + [int]$counts[$id] } } }
    $repeated = @($counts.GetEnumerator() | Where-Object { $_.Value -ge 2 })
    if ($repeated.Count -gt 0) {
        $worst = ($repeated | Sort-Object Value -Descending | Select-Object -First 1)
        $title = $worst.Key
        if (Get-Command Get-ActionItemsData -ErrorAction SilentlyContinue) {
            $match = @((Get-ActionItemsData).items | Where-Object { $_.id -eq $worst.Key }) | Select-Object -First 1
            if ($match) { $title = $match.title }
        }
        $conf = if ($worst.Value -ge 3) { 'Medium' } else { 'Low' }
        $msg = "I've been seeing ""$title"" move to tomorrow a few times now. No judgment - is it stuck, too big, or maybe not really a yes?"
        $why = 'A task that keeps getting postponed is usually blocked, oversized, or secretly a no - naming it kindly lets you unblock it, shrink it, or let it go.'
        return (New-Observation -Id 'obs-postponed' -Category 'Obstacles' -Headline 'A task that keeps moving' -Message $msg -Why $why -Confidence $conf -Tone 'question' -Impact 64 -Sources @('End of Day Audit', 'Action Items'))
    }
    return $null
}

# Pure celebration: wins were named yesterday.
function Find-ObsWins {
    param($Ctx)
    if (-not $Ctx.latest) { return $null }
    $wins = @($Ctx.latest.wins)
    if ($wins.Count -lt 2) { return $null }
    $msg = "You logged $($wins.Count) wins yesterday. Naming what went right is how momentum turns into a habit - nice work."
    $why = 'Noticing wins trains your attention toward progress, not just gaps - it is quietly one of the highest-return habits there is.'
    return (New-Observation -Id 'obs-wins' -Category 'Momentum' -Headline 'You named your wins' -Message $msg -Why $why -Confidence 'High' -Tone 'celebrate' -Impact 48 -Sources @('End of Day Audit'))
}

# ------------------------------------------------------------------ #
# ENGINE  -  run detectors, rank by impact (highest first).
# ------------------------------------------------------------------ #
function Get-TonyObservations {
    param($Context)
    if (-not $Context) { $Context = Get-ObservationContext }
    $detectors = @(
        'Find-ObsNonNegotiableStreak', 'Find-ObsFamilyWorkBalance', 'Find-ObsGoalProgress',
        'Find-ObsStalledGoal', 'Find-ObsActionMomentum', 'Find-ObsSlippedHabits',
        'Find-ObsRepeatedPostponement', 'Find-ObsWins'
    )
    $obs = @()
    foreach ($d in $detectors) {
        try { $o = & $d -Ctx $Context; if ($o) { $obs += $o } } catch { }
    }
    return @($obs | Sort-Object -Property @{ Expression = 'impact'; Descending = $true })
}

# The dashboard shows at most 3, highest impact first.
function Get-TopObservations {
    param([int]$Max = 3, $Context)
    return @(Get-TonyObservations -Context $Context | Select-Object -First $Max)
}
