# =====================================================================
# executive-context.ps1  —  Tony's Executive Context Engine
# ---------------------------------------------------------------------
# An executive chief of staff never answers a question in isolation. He
# first understands the situation - the day, the hour, the priorities,
# the momentum, the long game - and lets that shape the answer. Context
# is invisible; the user simply feels that Tony "gets it."
#
# Get-TonyExecutiveContext is the SINGLE place that assembles Tony's live
# situational awareness. It REFERENCES existing sources (Tony Brain's
# memory context, the Morning Briefing, End of Day Audits, Action Items,
# Identity, Goals, Mission, Values, Annual Theme, the Observation Engine,
# and the Decision Framework) - it never duplicates or stores their data.
# Tony Brain consumes it; the provider receives only a concise executive
# SUMMARY instead of reconstructing context itself.
#
# No cloud, no new store, no writes. Pure read-and-assemble.
# =====================================================================

$ErrorActionPreference = 'Stop'

function Get-ExecutivePartOfDay {
    param([int]$Hour)
    if ($Hour -lt 5)  { return 'night' }
    if ($Hour -lt 12) { return 'morning' }
    if ($Hour -lt 17) { return 'afternoon' }
    if ($Hour -lt 21) { return 'evening' }
    return 'night'
}

# The internal questions an executive silently answers before speaking.
# Deterministic; derived from the referenced sources, never stored.
function Get-ExecutiveAssessment {
    param($Now, $Time, $Priorities, $OpenTasks, $LatestAudit, $ActiveGoals, $Observations, $Guidance, $Question)

    # What matters most today?
    $whatMattersMost = if (@($Priorities).Count -gt 0) { $Priorities[0] }
    elseif (@($OpenTasks).Count -gt 0) { $OpenTasks[0] }
    else { 'Nothing pressing - a good moment to plan or rest.' }

    # Is anything overdue? (No due-date field exists; use items that have
    # lingered open 2+ weeks as the honest proxy.)
    $overdueItems = @()
    if (Get-Command Get-ActionItemsData -ErrorAction SilentlyContinue) {
        try {
            $cut = $Now.AddDays(-14)
            $overdueItems = @((Get-ActionItemsData).items | Where-Object {
                    -not $_.done -and -not $_.archived -and $_.created -and ([datetime]$_.created) -lt $cut
                } | ForEach-Object { $_.title })
        } catch { }
    }
    $overdue = [pscustomobject]@{ any = ($overdueItems.Count -gt 0); count = $overdueItems.Count; items = @($overdueItems | Select-Object -First 3) }

    # Is Jake off-track? (weak audit signals or a cautioning observation)
    $offReasons = @()
    if ($LatestAudit) {
        if ($null -ne $LatestAudit.scores.consistency -and [int]$LatestAudit.scores.consistency -lt 6) { $offReasons += 'consistency dipped' }
        if ($null -ne $LatestAudit.scores.overall -and [int]$LatestAudit.scores.overall -lt 6) { $offReasons += 'overall day score is low' }
    }
    # only genuine concerns count as off-track - a low-confidence question or a
    # habit/obstacle observation. Positive guidance (e.g. "a goal within reach")
    # is momentum, not a problem.
    $concernObs = @($Observations | Where-Object { $_.tone -eq 'question' -or $_.category -in @('Habits', 'Obstacles') })
    if ($concernObs.Count -gt 0) { $offReasons += ('worth a look: ' + $concernObs[0].headline) }
    $offTrack = [pscustomobject]@{ any = ($offReasons.Count -gt 0); reasons = @($offReasons) }

    # Is Jake making progress?
    $progReasons = @()
    if ($LatestAudit -and $null -ne $LatestAudit.scores.consistency -and [int]$LatestAudit.scores.consistency -ge 7) { $progReasons += ('consistency strong (' + [int]$LatestAudit.scores.consistency + '/10)') }
    $celebrate = @($Observations | Where-Object { $_.tone -eq 'celebrate' })
    if ($celebrate.Count -gt 0) { $progReasons += $celebrate[0].headline }
    $nearGoal = @($ActiveGoals | Where-Object { $null -ne $_.progress -and [int]$_.progress -ge 70 } | Select-Object -First 1)
    if ($nearGoal.Count -gt 0) { $progReasons += ('"' + $nearGoal[0].title + '" is close') }
    $makingProgress = [pscustomobject]@{ any = ($progReasons.Count -gt 0); reasons = @($progReasons) }

    # Is there a conflict between today's work and long-term goals?
    $conflicts = if ($Guidance -and $Guidance.conflicts) { @($Guidance.conflicts) } else { @() }
    $conflict = [pscustomobject]@{ any = ($conflicts.Count -gt 0); items = @($conflicts) }

    # Should I ask a clarifying question instead of assuming?
    $q = if ($Question) { $Question.Trim() } else { '' }
    $vague = ($q.Length -gt 0 -and @($q -split '\s+').Count -le 3)
    $lowConf = ($Guidance -and $null -ne $Guidance.confidence -and $Guidance.confidence -lt 0.4)
    $frameworkAsks = ($Guidance -and @($Guidance.clarifyingQuestions).Count -gt 0)
    $shouldClarify = [pscustomobject]@{
        any = [bool]($vague -or $lowConf -or $frameworkAsks)
        questions = if ($Guidance) { @($Guidance.clarifyingQuestions) } else { @() }
    }

    return [pscustomobject]@{
        whatMattersMost = $whatMattersMost
        overdue         = $overdue
        offTrack        = $offTrack
        makingProgress  = $makingProgress
        conflict        = $conflict
        shouldClarify   = $shouldClarify
    }
}

# The concise executive summary handed to the provider - dense, human, and
# situational. This is what lets the provider answer WITHOUT rebuilding
# context from raw fields.
function Get-ExecutiveSummaryText {
    param($Time, $Workspace, $Project, $Priorities, $OpenCount, $LatestAudit, $AnnualTheme, $Assessment, $Guidance, $Memory = @(), $Weather = $null, $Calendar = $null, $Email = $null)
    $parts = @()
    $parts += ("It's {0} {1}, {2}." -f $Time.dayOfWeek, $Time.partOfDay, $Time.time)
    $where = if ($Project) { "working on $Project" }
    elseif ($Workspace -and $Workspace -notin @('unknown', 'Home', 'Morning Experience')) { "in the $Workspace workspace" }
    else { 'on the home dashboard' }
    $parts += ("Jake is $where.")
    if (@($Priorities).Count -gt 0) { $parts += ('Top priority: "{0}" ({1} open action items).' -f $Priorities[0], $OpenCount) }
    elseif ($OpenCount -gt 0) { $parts += ("{0} open action items." -f $OpenCount) }
    if ($LatestAudit -and $null -ne $LatestAudit.scores.overall) { $parts += ("Most recent day score: {0}/10 (consistency {1}/10)." -f [int]$LatestAudit.scores.overall, [int]$LatestAudit.scores.consistency) }
    if ($Assessment.makingProgress.any) { $parts += ('Momentum: ' + ($Assessment.makingProgress.reasons -join '; ') + '.') }
    if ($Assessment.overdue.any) { $parts += ("{0} item(s) have lingered two weeks or more." -f $Assessment.overdue.count) }
    if ($Assessment.conflict.any) { $parts += ('Watch (values): ' + ($Assessment.conflict.items -join ' | ')) }
    if ($AnnualTheme -and $AnnualTheme.description) { $parts += ('Long game (annual theme): ' + $AnnualTheme.description) }
    if ($Weather -and $Weather.ok) { $parts += ('Weather ({0}): now {1}, {2}F; {3} high {4}/low {5}, rain {6}%.' -f $Weather.location, $Weather.current.conditions, $Weather.current.temperature, $Weather.forecast.when, $Weather.forecast.high, $Weather.forecast.low, $Weather.forecast.rainChancePct) }
    if ($Calendar -and $Calendar.ok) {
        $nextTxt = if ($Calendar.nextEvent) { ('next: "{0}" at {1}' -f $Calendar.nextEvent.title, $Calendar.nextEvent.start.ToString('ddd h:mm tt')) } else { 'nothing upcoming today' }
        $parts += ('Calendar: {0} today, {1} tomorrow; {2}.' -f $Calendar.todayCount, $Calendar.tomorrowCount, $nextTxt)
    }
    if ($Email -and $Email.ok -and $Email.summary) {
        $es = $Email.summary
        $parts += ('Inbox: {0} today, {1} need attention, {2} awaiting a reply, {3} invitation(s).' -f $es.total, $es.needsAttention, $es.waitingForReply, $es.invitations)
    }
    if (@($Memory).Count -gt 0) { $parts += ('Remembered (approved): ' + ((@($Memory) | Select-Object -First 3 | ForEach-Object { $_.value }) -join '; ') + '.') }
    if ($Guidance) { $parts += ('Tony''s judgment on this question: alignment {0}/100, priority {1}.' -f $Guidance.alignmentScore, $Guidance.priority) }
    return ($parts -join ' ')
}

# THE single source of Tony's situational awareness.
# One calm life-awareness sentence for the executive summary - Family first, then
# a non-negotiable worth protecting when the day is full. Returns '' when nothing
# is genuinely worth surfacing (never noise). Full domain data reaches Tony via
# the provider's LIFE CONTEXT block; this is only the one-line briefing nudge.
function Get-LifeAwarenessLine {
    param($Life, $ActiveGoals = @(), $OpenTasks = @(), $Calendar = $null)
    if (-not $Life) { return '' }
    $ft = @($Life.familyToday)
    if ($ft.Count -gt 0) { return ("You have a family commitment today ({0}) - keep the day shaped around it." -f [string]$ft[0].title) }
    $nn = @($Life.nonNegotiables)
    if ($nn.Count -gt 0) {
        $busy = $false
        if ($Calendar -and $Calendar.ok -and $Calendar.insights -and $Calendar.insights.today) { $busy = [bool]$Calendar.insights.today.meetingHeavy }
        if ($busy) { return ("Protect time for your non-negotiable: {0}." -f [string]$nn[0].title) }
    }
    return ''
}

function Get-TonyExecutiveContext {
    param(
        [string]$CurrentWorkspace = 'unknown',
        [string]$CurrentQuestion = '',
        [datetime]$Now = (Get-Date),
        $History = @(),
        [string]$CurrentProject = $null,
        $LiveSignals = @{}   # optional live-provider signals (weather, calendar, ...) passed in when relevant; never auto-fetched here
    )
    $has = { param($n) [bool](Get-Command $n -ErrorAction SilentlyContinue) }

    # -- base situational context (referenced from Tony Brain's memory engine; not duplicated) --
    $base = if (& $has 'Get-TonyContext') { Get-TonyContext -Now $Now } else { $null }

    # active project: reference the UI's current project if one is set (no new store)
    if (-not $CurrentProject -and (Test-Path variable:script:TonyActiveProject)) { $CurrentProject = $script:TonyActiveProject }

    # -- TIME --
    $hour = $Now.Hour
    $time = [pscustomobject]@{
        date      = $Now.ToString('yyyy-MM-dd')
        dayOfWeek = $Now.DayOfWeek.ToString()
        time      = $Now.ToString('h:mm tt')
        hour      = $hour
        partOfDay = (Get-ExecutivePartOfDay -Hour $hour)
        isWeekend = ($Now.DayOfWeek -eq [System.DayOfWeek]::Saturday -or $Now.DayOfWeek -eq [System.DayOfWeek]::Sunday)
    }

    # -- identity slices (referenced) --
    $identity    = if ($base -and $base.identity) { $base.identity.overview } else { $null }
    $goalsData   = if ($base -and $base.identity) { $base.identity.goals } else { $null }
    $goals       = if (& $has 'Get-GoalsList') { @(Get-GoalsList) } elseif ($goalsData) { @($goalsData.goals) } else { @() }
    $activeGoals = if (& $has 'Get-ActiveGoals') { @(Get-ActiveGoals) } else { @($goals | Where-Object { $null -ne $_.progress -and [int]$_.progress -lt 100 }) }
    $mission     = if ($base -and $base.identity -and $base.identity.mission) { $base.identity.mission.statement } else { '' }
    $values      = if ($base -and $base.identity -and $base.identity.values) { @($base.identity.values.values) } else { @() }
    $vision      = if ($base -and $base.identity) { $base.identity.vision } else { $null }
    $annualTheme = if (& $has 'Get-IdentityAnnualTheme') { Get-IdentityAnnualTheme } else { $null }

    # -- briefing / priorities / open work / audit (referenced) --
    $briefing    = if ($base) { $base.briefing } else { $null }
    $priorities  = if ($briefing) { @($briefing.topPriorities | ForEach-Object { $_.title }) } else { @() }
    $openTasks   = if ($base -and $base.actions) { @($base.actions.open | ForEach-Object { $_.title }) } else { @() }
    $openCount   = if ($base -and $base.actions) { @($base.actions.open).Count } else { 0 }
    $auditHist   = if ($base) { @($base.audits) } else { @() }
    $latestAudit = if ($auditHist.Count -gt 0) { $auditHist[0] } else { $null }

    # -- Observation Engine output (referenced) --
    $observations = if (& $has 'Get-TopObservations') { try { @(Get-TopObservations -Max 3) } catch { @() } } else { @() }

    # -- recent conversation (referenced) --
    $recentConversation = if (@($History).Count -gt 0) { @($History) }
    elseif (& $has 'Get-RecentConversation') { try { @(Get-RecentConversation -Count 6) } catch { @() } } else { @() }

    # -- recent document activity (no activity store yet; referenced as none) --
    $recentDocument = $null

    # -- approved permanent memory (READ ONLY; the Memory Manager is the only writer) --
    $memory = if (& $has 'Get-Memories') { try { @(Get-Memories) } catch { @() } } else { @() }

    # -- Life OS domains (READ ONLY by reference; the workspaces own the writes) --
    # Folded into the ONE context so Tony, the Priority Engine, the Briefing, and
    # the Workforce specialists all read the same source - never a second copy.
    $todayStr = $Now.ToString('yyyy-MM-dd')
    $lifeGet = { param($d) if (& $has 'Get-LifeItems') { try { @(Get-LifeItems -Domain $d -ActiveOnly) } catch { @() } } else { @() } }
    $nonNegotiables = & $lifeGet 'nonNegotiables'
    $family = & $lifeGet 'family'; $health = & $lifeGet 'health'; $financial = & $lifeGet 'financial'
    $agency = & $lifeGet 'agency'; $learning = & $lifeGet 'learning'; $projects = & $lifeGet 'projects'
    $familyToday = @($family | Where-Object { $_.date -eq $todayStr })
    # fill the reserved `project` slot from the active home project (no new store)
    if (-not $CurrentProject -and @($projects).Count -gt 0) { $CurrentProject = ('{0}{1}' -f $projects[0].title, $(if ($projects[0].nextAction) { ' - next: ' + $projects[0].nextAction } else { '' })) }
    $life = [pscustomobject]@{
        nonNegotiables = @($nonNegotiables); family = @($family); familyToday = @($familyToday)
        health = @($health); financial = @($financial); agency = @($agency); learning = @($learning); projects = @($projects)
    }

    # -- live-provider signals (passed in, never fetched here): weather, calendar, ... --
    $weather  = if ($LiveSignals -and $LiveSignals.ContainsKey('weather'))  { $LiveSignals['weather'] }  else { $null }
    $calendar = if ($LiveSignals -and $LiveSignals.ContainsKey('calendar')) { $LiveSignals['calendar'] } else { $null }
    $email    = if ($LiveSignals -and $LiveSignals.ContainsKey('email'))    { $LiveSignals['email'] }    else { $null }

    # -- Decision Framework output (Tony's judgment; retains FINAL authority downstream) --
    $guidance = $null
    if (& $has 'Evaluate-TonyDecision') {
        $nonNeg = if (& $has 'Get-NonNegotiableDefs') { Get-NonNegotiableDefs } else { @() }
        try {
            $guidance = Evaluate-TonyDecision -Identity $identity -Vision $vision -Goals $goals -Mission $mission -CoreValues $values `
                -AnnualTheme $annualTheme -NonNegotiables $nonNeg -Family $null -Health $null -Financial $null `
                -CurrentWorkspace $CurrentWorkspace -CurrentQuestion $CurrentQuestion -OpenTasks $openTasks -RecentAudits $auditHist
        } catch { }
    }

    # -- the silent executive assessment + the concise summary for the provider --
    $assessment = Get-ExecutiveAssessment -Now $Now -Time $time -Priorities $priorities -OpenTasks $openTasks `
        -LatestAudit $latestAudit -ActiveGoals $activeGoals -Observations $observations -Guidance $guidance -Question $CurrentQuestion
    $summary = Get-ExecutiveSummaryText -Time $time -Workspace $CurrentWorkspace -Project $CurrentProject `
        -Priorities $priorities -OpenCount $openCount -LatestAudit $latestAudit -AnnualTheme $annualTheme `
        -Assessment $assessment -Guidance $guidance -Memory $memory -Weather $weather -Calendar $calendar -Email $email
    # one calm life-awareness sentence, only when something is genuinely relevant today
    $lifeLine = Get-LifeAwarenessLine -Life $life -ActiveGoals $activeGoals -OpenTasks $openTasks -Calendar $calendar
    if ($lifeLine) { $summary = ($summary.TrimEnd() + ' ' + $lifeLine) }

    return [pscustomobject]@{
        source             = 'executive-context'
        generatedAt        = $Now
        time               = $time
        workspace          = $CurrentWorkspace
        project            = $CurrentProject
        question           = $CurrentQuestion
        briefing           = $briefing
        latestAudit        = $latestAudit
        auditHistoryCount  = $auditHist.Count
        priorities         = $priorities
        openTasks          = $openTasks
        openCount          = $openCount
        goals              = $goals
        activeGoals        = $activeGoals
        life               = $life           # Life OS domains (read-only reference; workspaces own writes)
        nonNegotiables     = @($nonNegotiables)
        familyToday        = @($familyToday)
        projects           = @($projects)
        identity           = $identity
        mission            = $mission
        values             = $values
        vision             = $vision
        annualTheme        = $annualTheme
        observations       = $observations
        guidance           = $guidance
        recentConversation = $recentConversation
        recentDocument     = $recentDocument
        memory             = $memory       # approved memories (read-only reference; Memory Manager owns writes)
        liveSignals        = $LiveSignals  # generic live-provider signals map (weather, calendar, email, ...)
        weather            = $weather      # derived convenience references (or null); provided, never fetched here
        calendar           = $calendar
        email              = $email
        assessment         = $assessment
        executiveSummary   = $summary
        base               = $base   # the referenced base context, reused by the reasoning engine (no re-assembly)
    }
}
