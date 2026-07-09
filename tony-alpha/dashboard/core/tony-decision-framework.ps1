# =====================================================================
# tony-decision-framework.ps1  —  Tony's judgment layer (NOT AI)
# ---------------------------------------------------------------------
# Intelligence answers the question. JUDGMENT decides whether the answer
# is good for THIS person, THIS life, right now. This framework is Tony's
# judgment: a deterministic evaluation of a decision against the user's
# identity, goals, non-negotiables, and the Project Diamond principles -
# run BEFORE any AI provider is asked, and handed to the provider as
# guidance. Tony always makes the final recommendation.
#
# No AI, no APIs, no cloud. Pure evaluation logic.
# =====================================================================

$ErrorActionPreference = 'Stop'

function Test-DecisionKeyword {
    param([string]$Text, [string[]]$Words)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
    foreach ($w in $Words) { if ($Text -like "*$w*") { return $true } }
    return $false
}

# The one function. Evaluates a decision/question and returns structured judgment.
function Evaluate-TonyDecision {
    param(
        $Identity, $Vision, $Goals, $Mission, $CoreValues, $AnnualTheme, $NonNegotiables,
        $Family, $Health, $Financial,
        [string]$CurrentWorkspace, [string]$CurrentQuestion,
        $OpenTasks, $RecentAudits
    )

    $q = if ($CurrentQuestion) { $CurrentQuestion.ToLower() } else { '' }
    $goalTitles = @($Goals | ForEach-Object { if ($_.title) { $_.title } else { [string]$_ } })
    $valueNames = @($CoreValues | ForEach-Object { if ($_.name) { $_.name } else { [string]$_ } })
    $hasIdentity = ($null -ne $Identity)

    $dims = @()
    function _Dim { param($Name, $Score, $Weight, $Note, [bool]$Conflict = $false) return [pscustomobject]@{ name = $Name; score = [math]::Round([math]::Max(0.0, [math]::Min(1.0, $Score)), 2); weight = $Weight; note = $Note; conflict = $Conflict } }

    # 1. Identity Alignment
    $s = 0.5; $n = 'Assessed against who you are becoming.'
    if ($hasIdentity) { $s += 0.15 }
    if ($valueNames.Count -gt 0 -and (Test-DecisionKeyword $q $valueNames)) { $s += 0.25; $n = 'Directly relates to your core values.' }
    $dims += (_Dim 'Identity Alignment' $s 1.2 $n)

    # 2. Vision Alignment
    $s = 0.5; $n = 'Checked against your long-term vision.'
    if ($Vision -and $Vision.statement) { $s += 0.1 }
    if (Test-DecisionKeyword $q @('future', 'long term', 'vision', 'five year', 'become', 'build', 'legacy')) { $s += 0.2; $n = 'Points at your long-term vision.' }
    $dims += (_Dim 'Vision Alignment' $s 1.0 $n)

    # 3. Goal Alignment
    $s = 0.5; $n = 'No direct link to a stated goal.'; $goalHit = $false
    foreach ($g in $goalTitles) { foreach ($w in @($g -split '\s+' | Where-Object { $_.Length -ge 4 })) { if ($q -like "*$($w.ToLower())*") { $goalHit = $true } } }
    if ($goalHit) { $s = 0.9; $n = 'Advances one of your goals.' }
    $dims += (_Dim 'Goal Alignment' $s 1.2 $n)

    # 4. Family Impact
    $neg = Test-DecisionKeyword $q @('work late', 'late night', 'weekend work', 'skip family', 'miss dinner', 'overtime', 'travel', 'away from home')
    $pos = Test-DecisionKeyword $q @('family', 'kids', 'wife', 'husband', 'date night', 'dinner with', 'time with')
    if ($neg) { $dims += (_Dim 'Family Impact' 0.25 1.5 'May cost family time - protect it.' $true) }
    elseif ($pos) { $dims += (_Dim 'Family Impact' 0.9 1.5 'Invests in family.') }
    else { $dims += (_Dim 'Family Impact' 0.6 1.5 'Neutral for family.') }

    # 5. Health Impact
    $neg = Test-DecisionKeyword $q @('skip workout', 'skip gym', 'no sleep', 'stay up', 'all nighter', 'stress', 'junk food')
    $pos = Test-DecisionKeyword $q @('workout', 'gym', 'train', 'sleep', 'walk', 'run', 'healthy', 'recovery')
    if ($neg) { $dims += (_Dim 'Health Impact' 0.3 1.3 'May cost your health/rest.' $true) }
    elseif ($pos) { $dims += (_Dim 'Health Impact' 0.85 1.3 'Supports your health.') }
    else { $dims += (_Dim 'Health Impact' 0.6 1.3 'Neutral for health.') }

    # 6. Financial Impact (GIOK informs; it never moves money)
    if (Test-DecisionKeyword $q @('buy', 'purchase', 'spend', 'pay for', 'invest', 'subscription', 'cost')) { $dims += (_Dim 'Financial Impact' 0.55 0.8 'Has a cost - review it against your budget (I inform; you decide).') }
    elseif (Test-DecisionKeyword $q @('save', 'budget', 'cut cost', 'cancel', 'reduce spend')) { $dims += (_Dim 'Financial Impact' 0.8 0.8 'Improves your financial position.') }
    else { $dims += (_Dim 'Financial Impact' 0.6 0.8 'Neutral financially.') }

    # 7. Relationship Impact
    $pos = Test-DecisionKeyword $q @('client', 'referral', 'call', 'reach out', 'follow up', 'check in', 'checkup', 'mentor', 'friend', 'connect')
    if ($pos) { $dims += (_Dim 'Relationship Impact' 0.85 1.2 'Strengthens a relationship - people first.') }
    elseif (Test-DecisionKeyword $q @('ignore', 'ghost', 'skip follow')) { $dims += (_Dim 'Relationship Impact' 0.3 1.2 'May neglect a relationship.' $true) }
    else { $dims += (_Dim 'Relationship Impact' 0.6 1.2 'Neutral for relationships.') }

    # 8. Time Savings
    $pos = Test-DecisionKeyword $q @('automate', 'capture', 'batch', 'template', 'delegate', 'plan', 'system', 'routine', 'schedule')
    if ($pos) { $dims += (_Dim 'Time Savings' 0.85 1.0 'Likely to save you time.') }
    elseif (Test-DecisionKeyword $q @('manual', 'redo', 'by hand', 'again')) { $dims += (_Dim 'Time Savings' 0.4 1.0 'May cost time - look for leverage.') }
    else { $dims += (_Dim 'Time Savings' 0.55 1.0 'Time impact unclear.') }

    # 9. Project Diamond Compliance
    if (Test-DecisionKeyword $q @('shortcut', 'hack', 'ignore people', 'maximize money', 'at all costs', 'cut corner')) { $dims += (_Dim 'Project Diamond Compliance' 0.3 1.3 'Risks People Matter More Than Money / the ten-year rule.' $true) }
    else { $dims += (_Dim 'Project Diamond Compliance' 0.8 1.3 'Consistent with Project Diamond.') }

    # ---- roll up ----
    $wsum = ($dims | Measure-Object -Property weight -Sum).Sum
    $weighted = 0.0; foreach ($d in $dims) { $weighted += ($d.score * $d.weight) }
    $alignment = [int][math]::Round(($weighted / $wsum) * 100)

    $conflicts = @($dims | Where-Object { $_.conflict } | ForEach-Object { "$($_.name): $($_.note)" })

    # recommendations
    $recs = @()
    if ($alignment -ge 75) { $recs += 'This aligns well with who you are becoming - I would move forward.' }
    elseif ($alignment -ge 50) { $recs += 'Reasonable, with a caveat - mind the conflicts below before committing.' }
    else { $recs += 'I would pause on this and reconsider before acting.' }
    foreach ($c in $conflicts) { $recs += ("Protect against - {0}" -f $c) }

    # clarifying questions
    $clarify = @()
    if (-not $hasIdentity) { $clarify += 'I do not have your identity yet - shall we do your First Conversation so I can advise better?' }
    if (($dims | Where-Object { $_.name -eq 'Family Impact' -and $_.conflict })) { $clarify += 'Will this cost you family time this week?' }
    if ((Test-DecisionKeyword $q @('buy', 'purchase', 'spend', 'invest'))) { $clarify += 'Is this within your budget for the month?' }
    if (($q -split '\s+').Count -le 3 -and $q -ne '') { $clarify += 'Can you tell me a bit more about what you are trying to do?' }

    # priority
    $urgent = Test-DecisionKeyword $q @('today', 'now', 'urgent', 'asap', 'overdue', 'deadline', 'due')
    $priority = if ($urgent -or $alignment -ge 75) { 'High' } elseif ($alignment -ge 50) { 'Medium' } else { 'Low' }

    # confidence (heuristic layer, not AI - kept modest, higher with more context)
    $conf = 0.4
    if ($hasIdentity) { $conf += 0.08 }
    if ($goalTitles.Count -gt 0) { $conf += 0.06 }
    if ($valueNames.Count -gt 0) { $conf += 0.06 }
    if (@($RecentAudits).Count -gt 0) { $conf += 0.05 }
    $conf = [math]::Round([math]::Min(0.7, $conf), 2)

    return [pscustomobject]@{
        alignmentScore      = $alignment       # 0..100
        dimensions          = $dims
        conflicts           = $conflicts
        recommendations     = $recs
        clarifyingQuestions = $clarify
        priority            = $priority
        confidence          = $conf
        source              = 'judgment-layer'
    }
}
