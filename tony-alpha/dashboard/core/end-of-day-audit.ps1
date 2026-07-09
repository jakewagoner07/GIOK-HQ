# =====================================================================
# end-of-day-audit.ps1  —  The End of Day Audit workspace (business logic)
# ---------------------------------------------------------------------
# GIOK's signature evening ritual. Not journaling - honest review,
# improvement, and preparation for tomorrow. Answers:
#   "Did today move Jake closer to the life he is building?"
#
# Source of truth: end_of_day_audit.json, stored by DATE. Nothing is
# overwritten across days - every day's audit is a permanent record.
# Pure data logic, no UI. Local JSON only - no AI, no cloud, no APIs.
# =====================================================================

$ErrorActionPreference = 'Stop'

function Get-AuditPath { return (Join-Path $PSScriptRoot '..\..\end_of_day_audit.json') }

# Score categories the user sets (Overall is derived from these).
function Get-AuditScoreCategories { return @('Business', 'Health', 'Family', 'Financial', 'Learning', 'Consistency', 'Relationship') }
function ConvertTo-ScoreKey { param([string]$Name) return ($Name.Substring(0, 1).ToLower() + $Name.Substring(1)) }

# Non-negotiables (display name -> storage key).
function Get-NonNegotiableDefs {
    return @(
        [pscustomobject]@{ name = 'Workout'; key = 'workout' }
        [pscustomobject]@{ name = 'Learning'; key = 'learning' }
        [pscustomobject]@{ name = 'Reading'; key = 'reading' }
        [pscustomobject]@{ name = 'Family Time'; key = 'familyTime' }
        [pscustomobject]@{ name = 'Prospecting'; key = 'prospecting' }
        [pscustomobject]@{ name = 'Social Posting'; key = 'socialPosting' }
        [pscustomobject]@{ name = 'Water'; key = 'water' }
        [pscustomobject]@{ name = 'Protein'; key = 'protein' }
        [pscustomobject]@{ name = 'Sleep'; key = 'sleep' }
    )
}

# Reflection fields (key -> label).
function Get-ReflectionDefs {
    return @(
        [pscustomobject]@{ key = 'largestWin'; label = 'Largest Win' }
        [pscustomobject]@{ key = 'largestLesson'; label = 'Largest Lesson' }
        [pscustomobject]@{ key = 'better'; label = 'What Could Have Been Better' }
        [pscustomobject]@{ key = 'grateful'; label = 'What Are You Grateful For' }
        [pscustomobject]@{ key = 'promise'; label = 'One Promise To Tomorrow' }
        [pscustomobject]@{ key = 'tomorrowPriority'; label = "Tomorrow's #1 Priority" }
    )
}

function Get-TonyAuditSummary {
    param([string]$Date)
    # Placeholder - future versions generate this with AI.
    return "Today showed steady progress, Jake. Celebrate the wins, keep the streaks alive, and start tomorrow with your highest-value follow-up before the noise arrives. Consistency over intensity - that's how the life you're building gets built."
}

function Get-AuditData {
    $p = Get-AuditPath
    if (Test-Path $p) {
        try { return (Get-Content -Path $p -Raw -Encoding UTF8 | ConvertFrom-Json) } catch { }
    }
    return [pscustomobject]@{ meta = [pscustomobject]@{ version = '1.0.0'; note = 'End of Day Audits, stored by date. Nothing is overwritten across days.'; updated = $null }; audits = [pscustomobject]@{} }
}

function Save-AuditData {
    param([Parameter(Mandatory)] $Data)
    if (-not $Data.meta) { $Data | Add-Member -NotePropertyName meta -NotePropertyValue ([pscustomobject]@{ version = '1.0.0'; updated = $null }) -Force }
    $Data.meta.updated = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    ($Data | ConvertTo-Json -Depth 10) | Set-Content -Path (Get-AuditPath) -Encoding UTF8
}

function Get-DefaultDayAudit {
    param([string]$Date)
    return [pscustomobject]@{
        date           = $Date
        scores         = [pscustomobject]@{ overall = 0; business = 0; health = 0; family = 0; financial = 0; learning = 0; consistency = 0; relationship = 0 }
        wins           = @()
        nonNegotiables = [pscustomobject]@{ workout = $false; learning = $false; reading = $false; familyTime = $false; prospecting = $false; socialPosting = $false; water = $false; protein = $false; sleep = $false }
        reflection     = [pscustomobject]@{ largestWin = ''; largestLesson = ''; better = ''; grateful = ''; promise = ''; tomorrowPriority = '' }
        movedToTomorrow = @()
        tonyAudit      = (Get-TonyAuditSummary -Date $Date)
        savedAt        = $null
    }
}

# Returns the stored audit for a date, or a fresh (unsaved) default.
function Get-DayAudit {
    param([string]$Date)
    $data = Get-AuditData
    if ($data.audits.PSObject.Properties.Name -contains $Date) { return $data.audits.$Date }
    return (Get-DefaultDayAudit -Date $Date)
}

# Loads data and guarantees an entry for the date exists; returns the data object.
function Confirm-DayAuditEntry {
    param([Parameter(Mandatory)] $Data, [string]$Date)
    if ($Data.audits.PSObject.Properties.Name -notcontains $Date) {
        $Data.audits | Add-Member -NotePropertyName $Date -NotePropertyValue (Get-DefaultDayAudit -Date $Date) -Force
    }
    return $Data.audits.$Date
}

function Update-Overall { param($Audit)
    $cats = @('business', 'health', 'family', 'financial', 'learning', 'consistency', 'relationship')
    $vals = $cats | ForEach-Object { [int]$Audit.scores.$_ }
    $Audit.scores.overall = [int]([math]::Round(($vals | Measure-Object -Average).Average))
}

function Set-AuditScore {
    param([string]$Date, [string]$Category, [int]$Value)
    $data = Get-AuditData; $a = Confirm-DayAuditEntry -Data $data -Date $Date
    $key = ConvertTo-ScoreKey $Category
    $a.scores.$key = [math]::Max(0, [math]::Min(10, $Value))
    Update-Overall -Audit $a; $a.savedAt = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    Save-AuditData $data
}
function Set-AuditScoreDelta {
    param([string]$Date, [string]$Category, [int]$Delta)
    $cur = [int](Get-DayAudit -Date $Date).scores.(ConvertTo-ScoreKey $Category)
    Set-AuditScore -Date $Date -Category $Category -Value ($cur + $Delta)
}

function Add-AuditWin {
    param([string]$Date, [string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return }
    $data = Get-AuditData; $a = Confirm-DayAuditEntry -Data $data -Date $Date
    $a.wins = @($a.wins) + $Text.Trim(); $a.savedAt = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    Save-AuditData $data
}
function Remove-AuditWin {
    param([string]$Date, [int]$Index)
    $data = Get-AuditData; $a = Confirm-DayAuditEntry -Data $data -Date $Date
    $w = @($a.wins); if ($Index -ge 0 -and $Index -lt $w.Count) { $a.wins = @($w | Where-Object { $_ -ne $w[$Index] -or $false } | Select-Object -First 0) }
    # simple index removal
    $new = @(); for ($i = 0; $i -lt $w.Count; $i++) { if ($i -ne $Index) { $new += $w[$i] } }
    $a.wins = @($new)
    Save-AuditData $data
}

function Set-NonNegotiable {
    param([string]$Date, [string]$Key, [bool]$Done)
    $data = Get-AuditData; $a = Confirm-DayAuditEntry -Data $data -Date $Date
    $a.nonNegotiables.$Key = $Done; $a.savedAt = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    Save-AuditData $data
}

function Set-AuditReflection {
    param([string]$Date, [string]$Field, [string]$Value)
    $data = Get-AuditData; $a = Confirm-DayAuditEntry -Data $data -Date $Date
    $a.reflection.$Field = $Value; $a.savedAt = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    Save-AuditData $data
}

function Add-AuditMovedToTomorrow {
    param([string]$Date, [string]$ActionId)
    $data = Get-AuditData; $a = Confirm-DayAuditEntry -Data $data -Date $Date
    if (@($a.movedToTomorrow) -notcontains $ActionId) { $a.movedToTomorrow = @($a.movedToTomorrow) + $ActionId }
    Save-AuditData $data
}

# Incomplete action items (live from action_items.json - referenced, not duplicated).
function Get-AuditIncompleteActions {
    if (Get-Command Get-ActionItemsData -ErrorAction SilentlyContinue) {
        return @((Get-ActionItemsData).items | Where-Object { -not $_.archived -and -not $_.done })
    }
    return @()
}

# Past audits (all stored dates), newest first.
function Get-AuditHistory {
    $data = Get-AuditData
    $dates = @($data.audits.PSObject.Properties.Name) | Sort-Object -Descending
    return @($dates | ForEach-Object { $data.audits.$_ })
}
