# =====================================================================
# morning-brief.ps1  —  Tony's Morning Briefing model (business logic)
# ---------------------------------------------------------------------
# The Morning Briefing is Tony's executive briefing that prepares Jake
# for the day. It answers one question: "What should Jake focus on today?"
#
# This is the DEDICATED model. The UI renders ONLY from what Get-MorningBrief
# returns - no dashboard logic is hardcoded in the UI. Live data where
# available; clearly-labelled placeholders (source='placeholder') elsewhere.
# =====================================================================

$ErrorActionPreference = 'Stop'

# Rotating GIOK principle - one per day, deterministic by date.
function Get-DailyPrinciple {
    param([datetime]$Now = (Get-Date))
    $principles = @(
        'People Matter More Than Money.',
        'Your brain is for thinking, not remembering.',
        'Capture first. Organize later.',
        'Progress over perfection.',
        'Discipline compounds.',
        'Better, not busy.'
    )
    return $principles[($Now.DayOfYear % $principles.Count)]
}

# Recommendation engine (placeholder). Prioritizes, in order:
#   1. open action items   2. recent/unprocessed captures   3. open issues   4. goals (future)
# Returns a ranked list of { text; source; priority }.
function Get-TonyRecommendations {
    param([int]$Max = 4)
    $recs = @()

    $openAI = if (Get-Command Get-ActionItemsData -ErrorAction SilentlyContinue) { @((Get-ActionItemsData).items | Where-Object { -not $_.archived -and -not $_.done }) } else { @() }
    if ($openAI.Count -gt 0) { $recs += [pscustomobject]@{ text = ("Triage your top action items - {0} open." -f $openAI.Count); source = 'action-items'; priority = 1 } }

    $unprocessed = if (Get-Command Get-CaptureStats -ErrorAction SilentlyContinue) { (Get-CaptureStats).unprocessed } else { 0 }
    if ($unprocessed -gt 0) { $recs += [pscustomobject]@{ text = ("Route {0} unprocessed captures out of your Inbox." -f $unprocessed); source = 'captures'; priority = 2 } }

    $issues = @(Get-IssuesSummary)
    if ($issues.Count -gt 0) { $recs += [pscustomobject]@{ text = ("Resolve {0} open registry flags." -f $issues.Count); source = 'issues'; priority = 3 } }

    # goals (future) + a business nudge - clearly sample until live
    $recs += [pscustomobject]@{ text = 'Set your #1 goal for the week.'; source = 'goals'; priority = 4 }
    $recs += [pscustomobject]@{ text = 'Reach out to a client overdue for their annual Giok Checkup.'; source = 'placeholder'; priority = 5 }

    return @($recs | Sort-Object priority | Select-Object -First $Max)
}

function Get-MorningBrief {
    param([datetime]$Now = (Get-Date))

    $reg = Get-Registry
    $agents = @($reg.agents)

    # agent health (live)
    $byStatus = [ordered]@{}
    foreach ($s in $reg.meta.status_values) { $byStatus[$s] = 0 }
    foreach ($a in $agents) { if ($byStatus.Contains($a.status)) { $byStatus[$a.status]++ } else { $byStatus[$a.status] = 1 } }
    $withIssues = @($agents | Where-Object { @($_.issues).Count -gt 0 })
    $withHealth = @($agents | Where-Object { $null -ne $_.health_score })

    # action items (live)
    $openAI = if (Get-Command Get-ActionItemsData -ErrorAction SilentlyContinue) { @((Get-ActionItemsData).items | Where-Object { -not $_.archived -and -not $_.done }) } else { @() }
    $topPriorities = @($openAI | Select-Object -First 3 | ForEach-Object { [pscustomobject]@{ id = $_.id; title = $_.title } })

    # captures (live)
    $capStats = if (Get-Command Get-CaptureStats -ErrorAction SilentlyContinue) { Get-CaptureStats } else { [pscustomobject]@{ total = 0; unprocessed = 0; today = 0; recent = @() } }

    # issues (live)
    $issues = @(Get-IssuesSummary)

    # notifications (derived from live signals + one clearly-sample item)
    $notifications = @()
    if ($capStats.unprocessed -gt 0) { $notifications += [pscustomobject]@{ text = ("{0} unprocessed captures in your Inbox." -f $capStats.unprocessed); source = 'captures' } }
    if ($issues.Count -gt 0)         { $notifications += [pscustomobject]@{ text = ("{0} open registry flags need review." -f $issues.Count); source = 'issues' } }
    if ($withIssues.Count -gt 0)     { $notifications += [pscustomobject]@{ text = ("{0} agents need attention." -f $withIssues.Count); source = 'agents' } }
    $notifications += [pscustomobject]@{ text = '1 client overdue for their annual Giok Checkup.'; source = 'placeholder' }

    return [pscustomobject]@{
        greeting   = (Get-Greeting -Now $Now)
        dateText   = $Now.ToString('dddd, MMMM d, yyyy')
        timeText   = $Now.ToString('h:mm tt')
        dailyPrinciple = (Get-DailyPrinciple -Now $Now)

        topPriorities   = $topPriorities
        openActionCount = $openAI.Count
        recentCaptures  = @($capStats.recent)
        captureUnprocessed = $capStats.unprocessed

        tonyRecommendations = @(Get-TonyRecommendations)

        agentHealth = [pscustomobject]@{ total = $agents.Count; byStatus = $byStatus; withIssues = $withIssues.Count; healthCoverage = "$($withHealth.Count)/$($agents.Count)" }

        # placeholders - clearly flagged, structured for future live integrations
        lifeScore     = [pscustomobject]@{ value = 78; trend = 'up';   source = 'placeholder' }
        businessScore = [pscustomobject]@{ value = 82; trend = 'flat'; source = 'placeholder' }
        weather       = [pscustomobject]@{ temp = '72 F'; condition = 'Sunny'; location = 'Ogden, UT'; source = 'placeholder' }
        appointments  = [pscustomobject]@{ source = 'placeholder'; items = @(
                [pscustomobject]@{ time = '9:30 AM'; title = 'Annual Giok Checkup'; who = 'The Millers' }
                [pscustomobject]@{ time = '11:00 AM'; title = 'New client intake'; who = 'David R.' }
            ) }

        notifications = $notifications
        preparedBy    = 'Tony'
    }
}
