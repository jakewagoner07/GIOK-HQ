# =====================================================================
# home-layout.ps1  —  Home dashboard layout preferences (Epic 11)
# ---------------------------------------------------------------------
# Stores ONLY how the user wants Home arranged: per card { id, visible,
# order, size }. Nothing else. No goals, no family items, no appointments,
# no CRM data, no briefing text - every card reads its own owner live, so
# this file can be deleted at any time without losing a single fact.
#
# It is therefore NOT a second store of business data; it is a preference
# file, local and user-specific (gitignored), and a missing or corrupt one
# simply means "use the default layout".
#
# Pure data + file IO. No WPF, no UI, no provider calls.
# =====================================================================

$ErrorActionPreference = 'Stop'

$script:HomeLayoutVersion = '1.0.0'
$script:HomeCardSizes = @('small', 'medium', 'large')

# ---- the catalog: every card Home can show -------------------------------
# id     - stable key stored in the preferences file
# title  - display name in the Customize panel
# fixed  - $true means the size is not user-changeable (a letter/banner only
#          reads as full width); the card can still be hidden/reordered
# visible/order/size - the DEFAULT layout for a brand-new user
#
# Default = today's Home (briefing, capture, agency, appointments, agent
# health) plus Goals and Executive Inbox: both cheap to render and core to
# the product. Everything else ships available-but-off so Home stays calm.
$script:HomeCardCatalog = @(
    [pscustomobject]@{ id = 'briefing';       title = "Tony's Executive Briefing"; visible = $true;  order = 1;  size = 'large';  fixed = $true }
    [pscustomobject]@{ id = 'capture';        title = 'Capture Something';         visible = $true;  order = 2;  size = 'large';  fixed = $true }
    [pscustomobject]@{ id = 'inbox';          title = 'Executive Inbox';           visible = $true;  order = 3;  size = 'small';  fixed = $false }
    [pscustomobject]@{ id = 'goals';          title = 'Goals';                     visible = $true;  order = 4;  size = 'small';  fixed = $false }
    [pscustomobject]@{ id = 'agentHealth';    title = 'Agent Health';              visible = $true;  order = 5;  size = 'small';  fixed = $false }
    # SAMPLE cards - off by default. Their content is invented placeholder data
    # (core/tony-core.ps1, source='placeholder'), so Home must never show them to a
    # user who did not ask for them: "Sarah T. - Policy review - 2:00 PM" reads as
    # your actual afternoon. They stay selectable, but the picker says so plainly and
    # the cards themselves carry a prominent warning. Real calendar-backed
    # appointments are a later, focused sprint.
    [pscustomobject]@{ id = 'agency';         title = 'Agency Overview (Sample data)';       visible = $false; order = 6;  size = 'small';  fixed = $false }
    [pscustomobject]@{ id = 'appointments';   title = 'Upcoming Appointments (Sample data)'; visible = $false; order = 7;  size = 'small';  fixed = $false }
    [pscustomobject]@{ id = 'family';         title = 'Family';                    visible = $false; order = 8;  size = 'small';  fixed = $false }
    [pscustomobject]@{ id = 'nonNegotiables'; title = 'Non-Negotiables';           visible = $false; order = 9;  size = 'small';  fixed = $false }
    [pscustomobject]@{ id = 'health';         title = 'Health';                    visible = $false; order = 10; size = 'small';  fixed = $false }
    [pscustomobject]@{ id = 'financial';      title = 'Financial';                 visible = $false; order = 11; size = 'small';  fixed = $false }
    [pscustomobject]@{ id = 'learning';       title = 'Learning';                  visible = $false; order = 12; size = 'small';  fixed = $false }
    [pscustomobject]@{ id = 'projects';       title = 'Projects';                  visible = $false; order = 13; size = 'small';  fixed = $false }
    [pscustomobject]@{ id = 'communications'; title = 'Communications';            visible = $false; order = 14; size = 'small';  fixed = $false }
    [pscustomobject]@{ id = 'crm';            title = 'CRM';                       visible = $false; order = 15; size = 'small';  fixed = $false }
    [pscustomobject]@{ id = 'priorities';     title = 'Weekly Priorities';         visible = $false; order = 16; size = 'medium'; fixed = $false }
    [pscustomobject]@{ id = 'dailyPlan';       title = 'Daily Executive Plan';      visible = $false; order = 17; size = 'medium'; fixed = $false }
)

function Get-HomeCardCatalog { return @($script:HomeCardCatalog) }
function Get-HomeCardSizes { return @($script:HomeCardSizes) }
function Get-HomeCardMeta { param([string]$Id) return @($script:HomeCardCatalog | Where-Object { $_.id -eq $Id })[0] }
function Get-HomeLayoutPath { return (Join-Path $PSScriptRoot '..\..\home_layout.json') }

# The default layout, straight from the catalog.
function Get-DefaultHomeLayout {
    return @($script:HomeCardCatalog | ForEach-Object {
        [pscustomobject]@{ id = $_.id; visible = [bool]$_.visible; order = [int]$_.order; size = [string]$_.size }
    })
}

# Merge whatever is on disk with the catalog. This is what makes an old
# preferences file safe against a new build:
#   * unknown ids (a card we removed) are dropped
#   * cards added since the file was written appear with catalog defaults
#   * a bad size/order falls back to the default
#   * fixed-size cards are pinned to their catalog size
# And the last guard: if the user hid EVERYTHING, the briefing is forced back
# on. That lives here, in the model, so no UI path can produce a blank Home.
function ConvertTo-NormalizedHomeLayout {
    param($Stored)
    $out = @()
    foreach ($c in @($script:HomeCardCatalog)) {
        $s = $null
        if ($Stored) { $s = @($Stored | Where-Object { $_ -and $_.id -eq $c.id })[0] }
        $visible = if ($s -and ($s.PSObject.Properties.Name -contains 'visible')) { [bool]$s.visible } else { [bool]$c.visible }
        $order = [int]$c.order
        if ($s -and ($s.PSObject.Properties.Name -contains 'order')) { try { $order = [int]$s.order } catch { $order = [int]$c.order } }
        $size = [string]$c.size
        if (-not $c.fixed -and $s -and ($s.PSObject.Properties.Name -contains 'size') -and ($script:HomeCardSizes -contains [string]$s.size)) { $size = [string]$s.size }
        $out += [pscustomobject]@{ id = $c.id; visible = $visible; order = $order; size = $size }
    }
    # stable, gap-free ordering
    $i = 0
    $out = @($out | Sort-Object @{ Expression = 'order' }, @{ Expression = 'id' } | ForEach-Object { $i++; $_.order = $i; $_ })
    # never a blank Home
    if (@($out | Where-Object { $_.visible }).Count -eq 0) {
        foreach ($x in $out) { if ($x.id -eq 'briefing') { $x.visible = $true } }
    }
    return ([array]$out)
}

function Get-HomeLayout {
    $p = Get-HomeLayoutPath
    $stored = $null
    if (Test-Path $p) {
        try { $stored = @((Get-Content -Path $p -Raw -Encoding UTF8 | ConvertFrom-Json).cards) } catch { $stored = $null }
    }
    return (ConvertTo-NormalizedHomeLayout -Stored $stored)
}

# Persist. Writes ONLY id/visible/order/size. Never throws into the UI - a
# failed preference save must never take the dashboard down.
function Save-HomeLayout {
    param([Parameter(Mandatory)] $Layout)
    try {
        $obj = [pscustomobject]@{
            meta  = [pscustomobject]@{ version = $script:HomeLayoutVersion }
            cards = ([array]@(@($Layout) | ForEach-Object {
                [pscustomobject]@{ id = [string]$_.id; visible = [bool]$_.visible; order = [int]$_.order; size = [string]$_.size }
            }))
        }
        ($obj | ConvertTo-Json -Depth 6) | Set-Content -Path (Get-HomeLayoutPath) -Encoding UTF8 -ErrorAction Stop
        return $true
    }
    catch { return $false }
}

function Reset-HomeLayout {
    $p = Get-HomeLayoutPath
    if (Test-Path $p) { try { Remove-Item $p -Force -ErrorAction Stop } catch { return $false } }
    return $true
}

function Set-HomeCardVisible {
    param([Parameter(Mandatory)][string]$Id, [bool]$Visible)
    $l = Get-HomeLayout
    foreach ($c in $l) { if ($c.id -eq $Id) { $c.visible = $Visible } }
    # re-normalize so the all-hidden guard applies before we persist
    $l = ConvertTo-NormalizedHomeLayout -Stored $l
    return (Save-HomeLayout -Layout $l)
}

function Set-HomeCardSize {
    param([Parameter(Mandatory)][string]$Id, [Parameter(Mandatory)][string]$Size)
    if ($script:HomeCardSizes -notcontains $Size) { return $false }
    $meta = Get-HomeCardMeta -Id $Id
    if (-not $meta -or $meta.fixed) { return $false }   # fixed cards are not resizable
    $l = Get-HomeLayout
    foreach ($c in $l) { if ($c.id -eq $Id) { $c.size = $Size } }
    return (Save-HomeLayout -Layout $l)
}

# Move one card up/down among ALL cards (visible or not) by swapping order
# with its neighbour, so the Customize list and Home agree.
function Move-HomeCard {
    param([Parameter(Mandatory)][string]$Id, [Parameter(Mandatory)][ValidateSet('up', 'down')][string]$Direction)
    $l = @(Get-HomeLayout | Sort-Object order)
    $idx = -1
    for ($i = 0; $i -lt $l.Count; $i++) { if ($l[$i].id -eq $Id) { $idx = $i; break } }
    if ($idx -lt 0) { return $false }
    $swap = if ($Direction -eq 'up') { $idx - 1 } else { $idx + 1 }
    if ($swap -lt 0 -or $swap -ge $l.Count) { return $false }   # already at the end
    $a = $l[$idx].order; $l[$idx].order = $l[$swap].order; $l[$swap].order = $a
    return (Save-HomeLayout -Layout $l)
}

# What Home actually renders: visible cards in order.
function Get-VisibleHomeCards { return @(Get-HomeLayout | Where-Object { $_.visible } | Sort-Object order) }
