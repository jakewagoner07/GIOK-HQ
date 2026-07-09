# =====================================================================
# action-items.ps1  —  Action Item state (source of truth: action_items.json)
# ---------------------------------------------------------------------
# The interactive task manager reads/writes action_items.json. The
# markdown file (action_items.md) stays human-readable, but JSON drives
# the UI and holds task state (done / archived / timestamps).
#
# Pure data logic; no UI. All mutators return the updated data object;
# the caller decides when to Save.
# =====================================================================

$ErrorActionPreference = 'Stop'

function Get-ActionItemsPath { return (Join-Path $PSScriptRoot '..\..\action_items.json') }

function Get-ActionItemsData {
    $p = Get-ActionItemsPath
    if (Test-Path $p) {
        try { return (Get-Content -Path $p -Raw -Encoding UTF8 | ConvertFrom-Json) } catch { }
    }
    return [pscustomobject]@{
        meta  = [pscustomobject]@{ version = '1.0.0'; updated = $null }
        items = @()
    }
}

function Save-ActionItemsData {
    param([Parameter(Mandatory)] $Data)
    if (-not $Data.meta) { $Data | Add-Member -NotePropertyName meta -NotePropertyValue ([pscustomobject]@{ version = '1.0.0'; updated = $null }) -Force }
    $Data.meta.updated = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    $json = $Data | ConvertTo-Json -Depth 8
    Set-Content -Path (Get-ActionItemsPath) -Value $json -Encoding UTF8
}

function Get-NextActionId {
    param([Parameter(Mandatory)] $Data)
    $max = 0
    foreach ($it in @($Data.items)) {
        if ($it.id -match '^AI-(\d+)$') { $n = [int]$Matches[1]; if ($n -gt $max) { $max = $n } }
    }
    return ('AI-{0:000}' -f ($max + 1))
}

function Add-ActionItem {
    param([Parameter(Mandatory)] $Data, [Parameter(Mandatory)][string]$Title, [string]$Id)
    if (-not $Id) { $Id = Get-NextActionId -Data $Data }
    $item = [pscustomobject]@{
        id          = $Id
        title       = $Title.Trim()
        done        = $false
        archived    = $false
        created     = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
        completedAt = $null
    }
    $Data.items = @($Data.items) + $item
    return $Data
}

function Set-ActionItemDone {
    param([Parameter(Mandatory)] $Data, [Parameter(Mandatory)][string]$Id, [bool]$Done)
    foreach ($it in @($Data.items)) {
        if ($it.id -eq $Id) {
            $it.done = $Done
            $it.completedAt = if ($Done) { (Get-Date).ToString('yyyy-MM-dd HH:mm:ss') } else { $null }
        }
    }
    return $Data
}

function Set-ActionItemArchived {
    param([Parameter(Mandatory)] $Data, [Parameter(Mandatory)][string]$Id, [bool]$Archived)
    foreach ($it in @($Data.items)) { if ($it.id -eq $Id) { $it.archived = $Archived } }
    return $Data
}

function Remove-ActionItem {
    param([Parameter(Mandatory)] $Data, [Parameter(Mandatory)][string]$Id)
    $Data.items = @(@($Data.items) | Where-Object { $_.id -ne $Id })
    return $Data
}

function Invoke-ArchiveCompleted {
    # Archive every completed (done) item that isn't archived yet. Returns count archived.
    param([Parameter(Mandatory)] $Data)
    $count = 0
    foreach ($it in @($Data.items)) {
        if ($it.done -and -not $it.archived) { $it.archived = $true; $count++ }
    }
    return $count
}
