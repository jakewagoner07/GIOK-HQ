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
function Add-IdentityGoal {
    # Back-compat wrapper (used by Document Intelligence / Capture): create a
    # basic goal in the ONE goal store via the enriched Add-Goal.
    param([string]$Title)
    return (Add-Goal -Title $Title)
}

# =====================================================================
# ENRICHED GOAL LAYER (Life OS Stage 1)
# The ONE goal store stays at identity/goals.json, owned here. The schema is
# enriched (domain/reason/targetDate/status/nextStep/notes) and legacy records
# (id/title/progress/target only) are back-filled on read - no second store.
# =====================================================================
$script:GoalDomains = @('personal', 'family', 'health', 'financial', 'agency', 'learning')
function Get-GoalDomains { return $script:GoalDomains }
function Get-GoalStatuses { return @('active', 'paused', 'done', 'archived') }

# Back-fill any goal (old or new) to the full schema. Pure; never writes.
function ConvertTo-NormalizedGoal {
    param($G)
    $now = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    $has = { param($n) ($G.PSObject.Properties.Name -contains $n) }
    $prog = 0; if ((& $has 'progress') -and $null -ne $G.progress) { try { $prog = [int]$G.progress } catch { $prog = 0 } }
    if ($prog -lt 0) { $prog = 0 } elseif ($prog -gt 100) { $prog = 100 }
    $status = if ((& $has 'status') -and $G.status) { [string]$G.status } elseif ($prog -ge 100) { 'done' } else { 'active' }
    return [pscustomobject]@{
        id         = [string]$G.id
        title      = [string]$G.title
        domain     = $(if ((& $has 'domain') -and $G.domain) { [string]$G.domain } else { 'personal' })
        reason     = $(if (& $has 'reason') { [string]$G.reason } else { '' })
        target     = $(if (& $has 'target') { [string]$G.target } else { '' })
        targetDate = $(if (& $has 'targetDate') { [string]$G.targetDate } else { '' })
        progress   = $prog
        status     = $status
        nextStep   = $(if (& $has 'nextStep') { [string]$G.nextStep } else { '' })
        notes      = $(if (& $has 'notes') { [string]$G.notes } else { '' })
        created    = $(if ((& $has 'created') -and $G.created) { [string]$G.created } else { $now })
        updated    = $(if ((& $has 'updated') -and $G.updated) { [string]$G.updated } else { $now })
    }
}

function Get-GoalStore {
    $g = Get-IdentityFile 'goals.json'
    if (-not $g) { $g = [pscustomobject]@{ meta = [pscustomobject]@{ version = '1.0.0'; source = 'life-os'; updated = '' }; goals = @() } }
    if (-not ($g.PSObject.Properties.Name -contains 'goals') -or $null -eq $g.goals) { $g | Add-Member -NotePropertyName goals -NotePropertyValue @() -Force }
    return $g
}
function Save-GoalStore {
    param($Store)
    if (-not ($Store.meta.PSObject.Properties.Name -contains 'updated')) { $Store.meta | Add-Member -NotePropertyName updated -NotePropertyValue '' -Force }
    $Store.meta.updated = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    Save-IdentityFile -Name 'goals.json' -Object $Store
}

# Normalized reads (what the workspace, context, and priority engine consume).
function Get-GoalsList   { return @(@((Get-GoalStore).goals) | ForEach-Object { ConvertTo-NormalizedGoal $_ }) }
function Get-ActiveGoals { return @(Get-GoalsList | Where-Object { $_.status -in @('active', 'paused') }) }
function Get-GoalById    { param([string]$Id) return @(Get-GoalsList | Where-Object { $_.id -eq $Id })[0] }

# -Id (Epic 16A): an optional caller-supplied STABLE id. When omitted, behaviour is
# unchanged (sequential G-NNN). When supplied, the EXACT id is persisted after two
# safety gates - it must be a well-formed goal id (G-...) and must not already exist -
# so the Action Engine can pre-allocate a deterministic id and verify by exact identity.
# The owner remains the only writer of its store.
function Add-Goal {
    param([string]$Title, [string]$Domain = 'personal', [string]$Reason = '', [string]$TargetDate = '', [string]$NextStep = '', [string]$Notes = '', [int]$Progress = 0, [string]$Id = '')
    if ([string]::IsNullOrWhiteSpace($Title)) { return $null }
    if ($script:GoalDomains -notcontains $Domain) { $Domain = 'personal' }
    $store = Get-GoalStore
    $newId = ''
    if ($Id) {
        if ($Id -notmatch '^G-[A-Za-z0-9]+$') { return $null }                                  # invalid id -> reject
        if (@($store.goals | Where-Object { [string]$_.id -eq $Id }).Count -gt 0) { return $null }  # duplicate id -> reject
        $newId = $Id
    }
    else {
        $max = 0; foreach ($x in @($store.goals)) { if ($x.id -match '^G-(\d+)$') { $n = [int]$Matches[1]; if ($n -gt $max) { $max = $n } } }
        $newId = ('G-{0:000}' -f ($max + 1))
    }
    $now = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    if ($Progress -lt 0) { $Progress = 0 } elseif ($Progress -gt 100) { $Progress = 100 }
    $new = [pscustomobject]@{
        id = $newId; title = $Title.Trim(); domain = $Domain; reason = $Reason.Trim()
        target = ''; targetDate = $TargetDate.Trim(); progress = $Progress; status = $(if ($Progress -ge 100) { 'done' } else { 'active' })
        nextStep = $NextStep.Trim(); notes = $Notes.Trim(); created = $now; updated = $now
    }
    $store.goals = @($store.goals) + $new
    Save-GoalStore $store
    return $new
}

# Edit any subset of fields. $Fields is a hashtable of goal fields to set.
function Update-Goal {
    param([Parameter(Mandatory)][string]$Id, [Parameter(Mandatory)][hashtable]$Fields)
    $store = Get-GoalStore; $changed = $false
    $normalized = @(@($store.goals) | ForEach-Object { ConvertTo-NormalizedGoal $_ })
    foreach ($g in $normalized) {
        if ($g.id -eq $Id) {
            foreach ($k in $Fields.Keys) {
                if ($g.PSObject.Properties.Name -contains $k) {
                    $v = $Fields[$k]
                    if ($k -eq 'domain' -and ($script:GoalDomains -notcontains $v)) { continue }
                    if ($k -eq 'status' -and ((Get-GoalStatuses) -notcontains $v)) { continue }
                    if ($k -eq 'progress') { $v = [int]$v; if ($v -lt 0) { $v = 0 } elseif ($v -gt 100) { $v = 100 } }
                    $g.$k = $v; $changed = $true
                }
            }
            if ($Fields.ContainsKey('progress') -and -not $Fields.ContainsKey('status')) {
                if ([int]$g.progress -ge 100 -and $g.status -eq 'active') { $g.status = 'done' }
            }
            $g.updated = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
        }
    }
    if ($changed) { $store.goals = @($normalized); Save-GoalStore $store }
    return $changed
}
function Set-GoalStatus   { param([string]$Id, [string]$Status) return (Update-Goal -Id $Id -Fields @{ status = $Status }) }
function Set-GoalProgress { param([string]$Id, [int]$Progress) return (Update-Goal -Id $Id -Fields @{ progress = $Progress }) }
function Complete-Goal    { param([string]$Id) return (Update-Goal -Id $Id -Fields @{ status = 'done'; progress = 100 }) }
function Archive-Goal     { param([string]$Id) return (Update-Goal -Id $Id -Fields @{ status = 'archived' }) }
function Restore-Goal     { param([string]$Id) return (Update-Goal -Id $Id -Fields @{ status = 'active' }) }
function Remove-Goal {
    param([Parameter(Mandatory)][string]$Id)
    $store = Get-GoalStore; $before = @($store.goals).Count
    $store.goals = @(@($store.goals) | Where-Object { $_.id -ne $Id })
    if (@($store.goals).Count -ne $before) { Save-GoalStore $store; return $true }
    return $false
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
