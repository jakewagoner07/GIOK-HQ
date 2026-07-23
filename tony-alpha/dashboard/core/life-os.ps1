# =====================================================================
# life-os.ps1  -  The Life Operating System data layer
# ---------------------------------------------------------------------
# The single authoritative owner of the life-and-business domain records that
# are NOT goals, action items, or memories: non-negotiables, family, health,
# financial, agency, learning, and home projects. Each is one named collection
# in ONE file, tony-alpha/life_os.json (Single Source of Truth - one type, one
# owner, one home). Goals stay in identity/goals.json; memory in tony_memory.json;
# action items in action_items.json. This module never touches those.
#
# Pure data logic, no UI, no rendering. Local JSON only - no APIs, no cloud.
# Generic typed-collection CRUD driven by a domain registry, so a new domain is
# configuration (register its fields) rather than new code.
# =====================================================================

$ErrorActionPreference = 'Stop'

# Domain registry: collection name -> { prefix, fields }. `fields` lists the
# domain-specific keys every record of that type carries (besides the universal
# id/active/created/updated). 'progress' is an int; everything else defaults ''.
$script:LifeOsDomains = [ordered]@{
    nonNegotiables = @{ prefix = 'NN';  fields = @('title', 'cadence', 'purpose', 'protection') }
    family         = @{ prefix = 'FAM'; fields = @('kind', 'title', 'detail', 'date') }
    health         = @{ prefix = 'HL';  fields = @('kind', 'title', 'detail', 'cadence') }
    financial      = @{ prefix = 'FN';  fields = @('kind', 'title', 'amount', 'detail', 'dueDate') }
    agency         = @{ prefix = 'AG';  fields = @('kind', 'title', 'detail', 'metric') }
    learning       = @{ prefix = 'LR';  fields = @('title', 'resource', 'progress', 'nextStep') }
    projects       = @{ prefix = 'PRJ'; fields = @('title', 'outcome', 'status', 'nextAction', 'targetDate') }
}
function Get-LifeOsDomainNames { return @($script:LifeOsDomains.Keys) }
function Get-LifeOsDomainFields { param([string]$Domain) if ($script:LifeOsDomains.Contains($Domain)) { return @($script:LifeOsDomains[$Domain].fields) } return @() }

function Get-LifeOsPath { return (Join-Path $PSScriptRoot '..\..\life_os.json') }

# Load the whole store, guaranteeing every registered collection exists as an
# array (so callers never guard for null). Never writes.
function Get-LifeOsData {
    $p = Get-LifeOsPath
    $data = $null
    if (Test-Path $p) { try { $data = Get-Content -Path $p -Raw -Encoding UTF8 | ConvertFrom-Json } catch { $data = $null } }
    if (-not $data) { $data = [pscustomobject]@{ meta = [pscustomobject]@{ version = '1.0.0'; updated = '' } } }
    if (-not ($data.PSObject.Properties.Name -contains 'meta') -or -not $data.meta) { $data | Add-Member -NotePropertyName meta -NotePropertyValue ([pscustomobject]@{ version = '1.0.0'; updated = '' }) -Force }
    foreach ($d in $script:LifeOsDomains.Keys) {
        if (-not ($data.PSObject.Properties.Name -contains $d) -or $null -eq $data.$d) { $data | Add-Member -NotePropertyName $d -NotePropertyValue @() -Force }
    }
    return $data
}

function Save-LifeOsData {
    param([Parameter(Mandatory)] $Data)
    $Data.meta.updated = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    ($Data | ConvertTo-Json -Depth 8) | Set-Content -Path (Get-LifeOsPath) -Encoding UTF8
}

# Back-fill a raw record to the full shape for its domain. Pure.
function ConvertTo-NormalizedLifeItem {
    param([string]$Domain, $Item)
    $now = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    $has = { param($n) ($Item.PSObject.Properties.Name -contains $n) }
    $o = [ordered]@{
        id      = [string]$Item.id
        active  = $(if (& $has 'active') { [bool]$Item.active } else { $true })
        created = $(if ((& $has 'created') -and $Item.created) { [string]$Item.created } else { $now })
        updated = $(if ((& $has 'updated') -and $Item.updated) { [string]$Item.updated } else { $now })
    }
    foreach ($f in (Get-LifeOsDomainFields $Domain)) {
        if ($f -eq 'progress') {
            $v = 0; if ((& $has 'progress') -and $null -ne $Item.progress) { try { $v = [int]$Item.progress } catch { $v = 0 } }
            if ($v -lt 0) { $v = 0 } elseif ($v -gt 100) { $v = 100 }
            $o[$f] = $v
        }
        else { $o[$f] = $(if (& $has $f) { [string]$Item.$f } else { '' }) }
    }
    return [pscustomobject]$o
}

# Normalized read of one collection. -ActiveOnly excludes paused/archived items.
function Get-LifeItems {
    param([Parameter(Mandatory)][string]$Domain, [switch]$ActiveOnly)
    if (-not $script:LifeOsDomains.Contains($Domain)) { return @() }
    $data = Get-LifeOsData
    $items = @(@($data.$Domain) | ForEach-Object { ConvertTo-NormalizedLifeItem -Domain $Domain -Item $_ })
    if ($ActiveOnly) { $items = @($items | Where-Object { $_.active }) }
    return @($items)
}
function Get-LifeItemById { param([string]$Domain, [string]$Id) return @(Get-LifeItems -Domain $Domain | Where-Object { $_.id -eq $Id })[0] }

function Get-NextLifeId {
    param([string]$Domain, $Data)
    $prefix = $script:LifeOsDomains[$Domain].prefix
    $max = 0
    foreach ($x in @($Data.$Domain)) { if ($x.id -match ('^' + [regex]::Escape($prefix) + '-(\d+)$')) { $n = [int]$Matches[1]; if ($n -gt $max) { $max = $n } } }
    return ('{0}-{1:000}' -f $prefix, ($max + 1))
}

# Create a record. $Fields is a hashtable of domain field keys -> values.
# Unknown keys are ignored; missing fields default. Title (when the domain has
# one) must be non-empty. Returns the new normalized item, or $null.
# -Id (Epic 16A): optional caller-supplied STABLE id. Omitted -> unchanged sequential
# <prefix>-NNN. Supplied -> the EXACT id after two gates: it must be a well-formed id
# for THIS domain's prefix and must not already exist in the domain. Owner stays the
# only writer; unrelated fields are untouched.
function Add-LifeItem {
    param([Parameter(Mandatory)][string]$Domain, [Parameter(Mandatory)][hashtable]$Fields, [string]$Id = '')
    if (-not $script:LifeOsDomains.Contains($Domain)) { return $null }
    $fieldKeys = Get-LifeOsDomainFields $Domain
    if ($fieldKeys -contains 'title' -and [string]::IsNullOrWhiteSpace([string]$Fields['title'])) { return $null }
    $data = Get-LifeOsData
    $useId = ''
    if ($Id) {
        $prefix = $script:LifeOsDomains[$Domain].prefix
        if ($Id -notmatch ('^' + [regex]::Escape($prefix) + '-[A-Za-z0-9]+$')) { return $null }        # invalid id -> reject
        if (@($data.$Domain | Where-Object { [string]$_.id -eq $Id }).Count -gt 0) { return $null }     # duplicate id -> reject
        $useId = $Id
    }
    else { $useId = Get-NextLifeId -Domain $Domain -Data $data }
    $now = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    $rec = [ordered]@{ id = $useId; active = $true; created = $now; updated = $now }
    foreach ($f in $fieldKeys) {
        if ($f -eq 'progress') { $v = 0; if ($Fields.ContainsKey('progress')) { try { $v = [int]$Fields['progress'] } catch { $v = 0 } }; if ($v -lt 0) { $v = 0 } elseif ($v -gt 100) { $v = 100 }; $rec[$f] = $v }
        else { $rec[$f] = $(if ($Fields.ContainsKey($f) -and $null -ne $Fields[$f]) { ([string]$Fields[$f]).Trim() } else { '' }) }
    }
    $new = [pscustomobject]$rec
    $data.$Domain = @($data.$Domain) + $new
    Save-LifeOsData $data
    return (ConvertTo-NormalizedLifeItem -Domain $Domain -Item $new)
}

# Update any subset of fields on one record.
function Update-LifeItem {
    param([Parameter(Mandatory)][string]$Domain, [Parameter(Mandatory)][string]$Id, [Parameter(Mandatory)][hashtable]$Fields)
    if (-not $script:LifeOsDomains.Contains($Domain)) { return $false }
    $data = Get-LifeOsData
    $fieldKeys = Get-LifeOsDomainFields $Domain
    $normalized = @(@($data.$Domain) | ForEach-Object { ConvertTo-NormalizedLifeItem -Domain $Domain -Item $_ })
    $changed = $false
    foreach ($it in $normalized) {
        if ($it.id -eq $Id) {
            foreach ($k in $Fields.Keys) {
                if ($k -eq 'active') { $it.active = [bool]$Fields[$k]; $changed = $true; continue }
                if ($fieldKeys -contains $k) {
                    if ($k -eq 'progress') { $v = 0; try { $v = [int]$Fields[$k] } catch { $v = 0 }; if ($v -lt 0) { $v = 0 } elseif ($v -gt 100) { $v = 100 }; $it.$k = $v }
                    else { $it.$k = ([string]$Fields[$k]).Trim() }
                    $changed = $true
                }
            }
            $it.updated = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
        }
    }
    if ($changed) { $data.$Domain = @($normalized); Save-LifeOsData $data }
    return $changed
}
function Set-LifeItemActive { param([string]$Domain, [string]$Id, [bool]$Active) return (Update-LifeItem -Domain $Domain -Id $Id -Fields @{ active = $Active }) }
function Remove-LifeItem {
    param([Parameter(Mandatory)][string]$Domain, [Parameter(Mandatory)][string]$Id)
    if (-not $script:LifeOsDomains.Contains($Domain)) { return $false }
    $data = Get-LifeOsData; $before = @($data.$Domain).Count
    $data.$Domain = @(@($data.$Domain) | Where-Object { $_.id -ne $Id })
    if (@($data.$Domain).Count -ne $before) { Save-LifeOsData $data; return $true }
    return $false
}
