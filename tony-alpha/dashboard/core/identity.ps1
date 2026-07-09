# =====================================================================
# identity.ps1  —  The Identity workspace data layer
# ---------------------------------------------------------------------
# Identity is the foundation of GIOK - the user's personal operating
# system. Vision and Goals live INSIDE Identity (not as separate
# top-level workspaces).
#
# Identity OWNS all identity data (identity/*.json). Other workspaces may
# READ these via these functions but must never duplicate the data.
# Pure data logic, no UI. Local JSON only - no APIs, no cloud.
# =====================================================================

$ErrorActionPreference = 'Stop'

function Get-IdentityDir { return (Join-Path $PSScriptRoot '..\..\identity') }

function Get-IdentityFile {
    param([Parameter(Mandatory)][string]$Name)
    $p = Join-Path (Get-IdentityDir) $Name
    if (Test-Path $p) {
        try { return (Get-Content -Path $p -Raw -Encoding UTF8 | ConvertFrom-Json) } catch { }
    }
    return $null
}

# Section accessors (each reads exactly one source-of-truth file)
function Get-IdentityVision      { return (Get-IdentityFile 'vision.json') }
function Get-IdentityGoals       { return (Get-IdentityFile 'goals.json') }
function Get-IdentityValues      { return (Get-IdentityFile 'values.json') }
function Get-IdentityMission     { return (Get-IdentityFile 'mission.json') }
function Get-IdentityLegacy      { return (Get-IdentityFile 'legacy.json') }
function Get-IdentityAnnualTheme { return (Get-IdentityFile 'annual_theme.json') }
function Get-IdentityJournal     { return (Get-IdentityFile 'journal.json') }
function Get-IdentityTimeline    { return (Get-IdentityFile 'timeline.json') }

# The Identity sections, in order.
function Get-IdentitySections {
    return @('Overview', 'Vision', 'Goals', 'Core Values', 'Mission', 'Legacy', 'Annual Theme', 'Journal', 'Timeline')
}

# Aggregated model for the Overview (executive summary of who Jake is becoming).
function Get-IdentityOverview {
    $ov      = Get-IdentityFile 'overview.json'
    $vision  = Get-IdentityVision
    $goals   = Get-IdentityGoals
    $values  = Get-IdentityValues
    $theme   = Get-IdentityAnnualTheme
    $journal = Get-IdentityJournal

    $goalList = if ($goals) { @($goals.goals) } else { @() }
    $goalProgress = if ($goalList.Count -gt 0) { [int]((($goalList.progress) | Measure-Object -Average).Average) } else { 0 }
    $latestJournal = if ($journal) { @($journal.entries)[0] } else { $null }

    return [pscustomobject]@{
        identityScore  = if ($ov) { $ov.identityScore } else { [pscustomobject]@{ value = 0; trend = 'flat'; source = 'placeholder' } }
        visionProgress = if ($vision) { $vision.progress } else { 0 }
        goalProgress   = $goalProgress
        annualTheme    = $theme
        values         = if ($values) { @($values.values) } else { @() }
        latestJournal  = $latestJournal
        recentWins     = if ($ov) { @($ov.recentWins) } else { @() }
        tonyReflection = if ($ov) { $ov.tonyReflection } else { $null }
    }
}
