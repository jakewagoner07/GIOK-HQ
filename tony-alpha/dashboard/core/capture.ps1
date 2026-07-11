# =====================================================================
# capture.ps1  —  GIOK Capture system (source of truth: capture.json)
# ---------------------------------------------------------------------
# "Your brain is for thinking, not remembering." Capture removes info
# from the user's mind and safely stores it. Organize later.
#
# Capture is SEPARATE from Action Items (different file, different life-
# cycle). Everything lands in the Inbox first; nothing is auto-deleted.
# Pure data logic, no UI. Mutators return the data; caller Saves.
# =====================================================================

$ErrorActionPreference = 'Stop'

# The categories a capture can be tagged with (optional - default 'Note').
function Get-CaptureCategories {
    return @('Note', 'Task', 'Idea', 'Reminder', 'Journal', 'Shopping', 'Home', 'Family', 'Business', 'Health', 'Financial', 'Learning')
}

function Get-CapturePath { return (Join-Path $PSScriptRoot '..\..\capture.json') }

function Get-CaptureData {
    $p = Get-CapturePath
    if (Test-Path $p) {
        try { return (Get-Content -Path $p -Raw -Encoding UTF8 | ConvertFrom-Json) } catch { }
    }
    return [pscustomobject]@{ meta = [pscustomobject]@{ version = '1.0.0'; updated = $null }; items = @() }
}

function Save-CaptureData {
    param([Parameter(Mandatory)] $Data)
    if (-not $Data.meta) { $Data | Add-Member -NotePropertyName meta -NotePropertyValue ([pscustomobject]@{ version = '1.0.0'; updated = $null }) -Force }
    $Data.meta.updated = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    ($Data | ConvertTo-Json -Depth 8) | Set-Content -Path (Get-CapturePath) -Encoding UTF8
}

function Get-NextCaptureId {
    param([Parameter(Mandatory)] $Data)
    $max = 0
    foreach ($it in @($Data.items)) { if ($it.id -match '^CAP-(\d+)$') { $n = [int]$Matches[1]; if ($n -gt $max) { $max = $n } } }
    return ('CAP-{0:000}' -f ($max + 1))
}

function Add-Capture {
    param([Parameter(Mandatory)] $Data, [Parameter(Mandatory)][string]$Text, [string]$Category = 'Note', [string]$CreatedFrom = 'app')
    $item = [pscustomobject]@{
        id          = Get-NextCaptureId -Data $Data
        timestamp   = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
        text        = $Text.Trim()
        category    = if ([string]::IsNullOrWhiteSpace($Category)) { 'Note' } else { $Category }
        status      = 'new'        # new | processed | archived
        createdFrom = $CreatedFrom  # capture-window | command-bar | home-button | ...
        processed   = $false
        convertedTo = $null         # action-item | goal | reminder | null
        notes       = ''
        tags        = @()           # future
    }
    $Data.items = @($Data.items) + $item
    return $item
}

function Set-CaptureProcessed {
    param([Parameter(Mandatory)] $Data, [Parameter(Mandatory)][string]$Id, [bool]$Processed = $true)
    foreach ($it in @($Data.items)) { if ($it.id -eq $Id) { $it.processed = $Processed; $it.status = if ($Processed) { 'processed' } else { 'new' } } }
    return $Data
}

function Set-CaptureArchived {
    param([Parameter(Mandatory)] $Data, [Parameter(Mandatory)][string]$Id)
    foreach ($it in @($Data.items)) { if ($it.id -eq $Id) { $it.status = 'archived' } }
    return $Data
}

function Restore-Capture {
    param([Parameter(Mandatory)] $Data, [Parameter(Mandatory)][string]$Id)
    foreach ($it in @($Data.items)) { if ($it.id -eq $Id) { $it.status = if ($it.processed) { 'processed' } else { 'new' } } }
    return $Data
}

function Remove-Capture {
    param([Parameter(Mandatory)] $Data, [Parameter(Mandatory)][string]$Id)
    $Data.items = @(@($Data.items) | Where-Object { $_.id -ne $Id })
    return $Data
}

# ---- conversions (architecture exists; some destinations are placeholders) ----
function Convert-Capture {
    param([Parameter(Mandatory)] $Data, [Parameter(Mandatory)][string]$Id, [Parameter(Mandatory)][ValidateSet('action-item', 'goal', 'reminder')][string]$To)
    $cap = @($Data.items) | Where-Object { $_.id -eq $Id } | Select-Object -First 1
    if (-not $cap) { return $Data }

    switch ($To) {
        'action-item' {
            # real: create an Action Item from the capture text
            if (Get-Command Add-ActionItem -ErrorAction SilentlyContinue) {
                $ai = Get-ActionItemsData
                Add-ActionItem -Data $ai -Title $cap.text | Out-Null
                Save-ActionItemsData $ai
            }
            $cap.notes = ("Converted to Action Item on {0}." -f (Get-Date).ToString('yyyy-MM-dd'))
        }
        'goal'     {
            # real (Life OS): create a goal in the ONE goal store from the capture text
            if (Get-Command Add-Goal -ErrorAction SilentlyContinue) {
                [void](Add-Goal -Title $cap.text)
                $cap.notes = ("Converted to a Goal on {0}." -f (Get-Date).ToString('yyyy-MM-dd'))
            }
            else { $cap.notes = ("Marked for Goals on {0}." -f (Get-Date).ToString('yyyy-MM-dd')) }
        }
        'reminder' { $cap.notes = ("Marked for Reminders (destination store is a future placeholder) on {0}." -f (Get-Date).ToString('yyyy-MM-dd')) }
    }
    $cap.convertedTo = $To
    $cap.processed = $true
    $cap.status = 'processed'
    return $Data
}

function Get-CaptureStats {
    $items = @((Get-CaptureData).items)
    $today = (Get-Date).ToString('yyyy-MM-dd')
    return [pscustomobject]@{
        total       = $items.Count
        unprocessed = @($items | Where-Object { $_.status -eq 'new' }).Count
        today       = @($items | Where-Object { $_.timestamp -like "$today*" }).Count
        recent      = @($items | Select-Object -Last 5 | Sort-Object { $_.id } -Descending)
    }
}
