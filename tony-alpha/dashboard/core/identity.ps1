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

# ---- write side (Identity OWNS its data; other layers call these, never write files directly) ----
function Save-IdentityFile {
    param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)] $Object)
    $dir = Get-IdentityDir
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    ($Object | ConvertTo-Json -Depth 8) | Set-Content -Path (Join-Path $dir $Name) -Encoding UTF8
}

function Split-IdentityList {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return @() }
    return @($Text -split '[\r\n;,]+' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
}

function Set-IdentityVision {
    param([string]$Statement)
    if ([string]::IsNullOrWhiteSpace($Statement)) { return }
    $v = Get-IdentityVision; if (-not $v) { $v = [pscustomobject]@{ meta = [pscustomobject]@{ version = '1.0.0'; source = 'first-conversation' }; statement = ''; horizon = '5-year'; progress = 0 } }
    $v.statement = $Statement.Trim(); Save-IdentityFile -Name 'vision.json' -Object $v
}
function Set-IdentityMission {
    param([string]$Statement)
    if ([string]::IsNullOrWhiteSpace($Statement)) { return }
    $m = Get-IdentityMission; if (-not $m) { $m = [pscustomobject]@{ meta = [pscustomobject]@{ version = '1.0.0'; source = 'first-conversation' }; statement = '' } }
    $m.statement = $Statement.Trim(); Save-IdentityFile -Name 'mission.json' -Object $m
}
function Set-IdentityLegacy {
    param([string]$Statement)
    if ([string]::IsNullOrWhiteSpace($Statement)) { return }
    $l = Get-IdentityLegacy; if (-not $l) { $l = [pscustomobject]@{ meta = [pscustomobject]@{ version = '1.0.0'; source = 'first-conversation' }; statement = '' } }
    $l.statement = $Statement.Trim(); Save-IdentityFile -Name 'legacy.json' -Object $l
}
function Set-IdentityValuesFromText {
    param([string]$Text)
    $items = @(Split-IdentityList $Text | Select-Object -First 6)
    if ($items.Count -eq 0) { return }
    $values = $items | ForEach-Object { [pscustomobject]@{ name = ($_.Substring(0, [math]::Min(38, $_.Length))); desc = $_ } }
    Save-IdentityFile -Name 'values.json' -Object ([pscustomobject]@{ meta = [pscustomobject]@{ version = '1.0.0'; source = 'first-conversation' }; values = @($values) })
}
function Set-IdentityGoalsFromText {
    param([string]$Text)
    $items = @(Split-IdentityList $Text | Select-Object -First 6)
    if ($items.Count -eq 0) { return }
    $i = 1; $goals = $items | ForEach-Object { $g = [pscustomobject]@{ id = ('G-{0:000}' -f $i); title = $_; progress = 0; target = ([string](Get-Date).Year) }; $i++; $g }
    Save-IdentityFile -Name 'goals.json' -Object ([pscustomobject]@{ meta = [pscustomobject]@{ version = '1.0.0'; source = 'first-conversation' }; goals = @($goals) })
}
function Set-IdentityAnnualThemeFromText {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return }
    $t = Get-IdentityAnnualTheme; if (-not $t) { $t = [pscustomobject]@{ meta = [pscustomobject]@{ version = '1.0.0'; source = 'first-conversation' }; year = (Get-Date).Year; theme = ''; description = '' } }
    $t.theme = 'Your focus for the year'; $t.description = $Text.Trim(); Save-IdentityFile -Name 'annual_theme.json' -Object $t
}
function Set-IdentityOverviewReflection {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return }
    $o = Get-IdentityFile 'overview.json'
    if (-not $o) { $o = [pscustomobject]@{ meta = [pscustomobject]@{ version = '1.0.0' }; identityScore = [pscustomobject]@{ value = 0; trend = 'flat'; source = 'placeholder' }; tonyReflection = [pscustomobject]@{ text = ''; source = 'first-conversation' }; recentWins = @() } }
    $o.tonyReflection.text = $Text; $o.tonyReflection.source = 'first-conversation'
    Save-IdentityFile -Name 'overview.json' -Object $o
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
