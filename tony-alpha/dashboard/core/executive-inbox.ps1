# =====================================================================
# executive-inbox.ps1  -  The Executive Inbox (GIOK's approval center)
# ---------------------------------------------------------------------
# NOT a provider, NOT a database of Jake's data. It holds ONLY pending
# PROPOSALS - things the Workforce discovered that should become part of
# Jake's operating system, waiting for his approval. Nothing is ever added
# automatically. On APPROVE, the OWNING module writes the real record and the
# proposal leaves the inbox (no second copy). On REJECT, the proposal is
# removed. Single Source of Truth: approved data lives ONLY in its owner
# (goals -> identity/goals.json, tasks -> action_items.json, life domains ->
# life_os.json, memory -> tony_memory.json); the inbox keeps no copy.
#
# Any Workforce member (or Tony) may propose via Add-InboxProposal - proposing
# is NOT acting; it only requests Jake's approval. Tony owns the inbox, presents
# recommendations, and NEVER auto-approves.
#
# Pure data logic, no UI. Local JSON only. The store (executive_inbox.json) is
# gitignored - proposals can carry sensitive family/health/financial details.
# =====================================================================

$ErrorActionPreference = 'Stop'

# The last four are LOCAL ACTION verbs executed by the Executive Action Engine
# (Epic 15) against the Action Items store: reminder (create), set-priority / defer
# (modify an existing item by sourceId), archive (retire an existing item).
$script:InboxTypes = @('goal', 'project', 'task', 'non-negotiable', 'family', 'health', 'financial', 'agency', 'learning', 'calendar', 'crm', 'communication', 'document', 'memory', 'reminder', 'set-priority', 'defer', 'archive')
function Get-InboxTypes { return $script:InboxTypes }

function Get-InboxPath { return (Join-Path $PSScriptRoot '..\..\executive_inbox.json') }

function Get-InboxData {
    $p = Get-InboxPath; $data = $null
    if (Test-Path $p) { try { $data = Get-Content -Path $p -Raw -Encoding UTF8 | ConvertFrom-Json } catch { $data = $null } }
    if (-not $data) { $data = [pscustomobject]@{ meta = [pscustomobject]@{ version = '1.0.0'; updated = '' }; items = @() } }
    if (-not ($data.PSObject.Properties.Name -contains 'items') -or $null -eq $data.items) { $data | Add-Member -NotePropertyName items -NotePropertyValue @() -Force }
    return $data
}
function Save-InboxData {
    param([Parameter(Mandatory)] $Data)
    $Data.meta.updated = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    ($Data | ConvertTo-Json -Depth 8) | Set-Content -Path (Get-InboxPath) -Encoding UTF8
}

# Back-fill a raw proposal to the full schema. Pure.
function ConvertTo-NormalizedInboxItem {
    param($It)
    $now = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    $has = { param($n) ($It.PSObject.Properties.Name -contains $n) }
    $conf = 0.0; if ((& $has 'confidence') -and $null -ne $It.confidence) { try { $conf = [double]$It.confidence } catch { $conf = 0.0 } }
    return [pscustomobject]@{
        id                  = [string]$It.id
        discoveredBy        = $(if (& $has 'discoveredBy') { [string]$It.discoveredBy } else { 'Tony' })
        type                = $(if (& $has 'type') { [string]$It.type } else { 'task' })
        title               = [string]$It.title
        description         = $(if (& $has 'description') { [string]$It.description } else { '' })
        proposedDestination = $(if (& $has 'proposedDestination') { [string]$It.proposedDestination } else { '' })
        evidence            = @($(if (& $has 'evidence') { $It.evidence } else { @() }))
        confidence          = [math]::Round([math]::Max(0.0, [math]::Min(1.0, $conf)), 2)
        status              = $(if ((& $has 'status') -and $It.status) { [string]$It.status } else { 'pending' })
        created             = $(if ((& $has 'created') -and $It.created) { [string]$It.created } else { $now })
        source              = $(if (& $has 'source') { [string]$It.source } else { '' })
        sourceId            = $(if (& $has 'sourceId') { [string]$It.sourceId } else { '' })
    }
}

function Get-InboxItems {
    param([string]$Status = 'pending')
    $items = @(@((Get-InboxData).items) | ForEach-Object { ConvertTo-NormalizedInboxItem $_ })
    if ($Status -and $Status -ne 'all') { $items = @($items | Where-Object { $_.status -eq $Status }) }
    return @($items | Sort-Object -Property @{ Expression = { $_.confidence }; Descending = $true }, created)
}
function Get-InboxItemById { param([string]$Id) return @(Get-InboxItems -Status 'all' | Where-Object { $_.id -eq $Id })[0] }
function Get-InboxCount { param([string]$Status = 'pending') return @(Get-InboxItems -Status $Status).Count }

# ANY Workforce member (or Tony) may propose. Proposing != acting - it only
# requests Jake's approval. Returns the new normalized proposal, or $null.
function Add-InboxProposal {
    param(
        [Parameter(Mandatory)][string]$DiscoveredBy,
        [Parameter(Mandatory)][string]$Type,
        [Parameter(Mandatory)][string]$Title,
        [string]$Description = '',
        [string]$ProposedDestination = '',
        $Evidence = @(),
        [double]$Confidence = 0.6,
        [string]$Source = '',
        [string]$SourceId = ''
    )
    if ([string]::IsNullOrWhiteSpace($Title)) { return $null }
    if ($script:InboxTypes -notcontains $Type) { $Type = 'task' }
    if (-not $ProposedDestination) { $ProposedDestination = (Get-InboxDestinationLabel -Type $Type) }
    $data = Get-InboxData
    $max = 0; foreach ($x in @($data.items)) { if ($x.id -match '^INBOX-(\d+)$') { $n = [int]$Matches[1]; if ($n -gt $max) { $max = $n } } }
    $now = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    $new = [pscustomobject]@{
        id = ('INBOX-{0:000}' -f ($max + 1)); discoveredBy = $DiscoveredBy.Trim(); type = $Type; title = $Title.Trim()
        description = $Description.Trim(); proposedDestination = $ProposedDestination.Trim(); evidence = @($Evidence)
        confidence = [math]::Round([math]::Max(0.0, [math]::Min(1.0, $Confidence)), 2); status = 'pending'; created = $now
        source = $Source.Trim(); sourceId = $SourceId.Trim()
    }
    $data.items = @($data.items) + $new
    Save-InboxData $data
    return (ConvertTo-NormalizedInboxItem $new)
}

# Edit a pending proposal (for Edit-then-Approve). Only editable fields.
function Update-InboxItem {
    param([Parameter(Mandatory)][string]$Id, [Parameter(Mandatory)][hashtable]$Fields)
    $data = Get-InboxData; $changed = $false
    $editable = @('type', 'title', 'description', 'proposedDestination', 'confidence')
    $normalized = @(@($data.items) | ForEach-Object { ConvertTo-NormalizedInboxItem $_ })
    foreach ($it in $normalized) {
        if ($it.id -eq $Id -and $it.status -eq 'pending') {
            foreach ($k in $Fields.Keys) {
                if ($editable -notcontains $k) { continue }
                if ($k -eq 'type' -and ($script:InboxTypes -notcontains $Fields[$k])) { continue }
                if ($k -eq 'confidence') { $it.$k = [math]::Round([math]::Max(0.0, [math]::Min(1.0, [double]$Fields[$k])), 2) }
                else { $it.$k = ([string]$Fields[$k]).Trim() }
                $changed = $true
            }
        }
    }
    if ($changed) { $data.items = @($normalized); Save-InboxData $data }
    return $changed
}

function Remove-InboxItem {
    param([Parameter(Mandatory)][string]$Id)
    $data = Get-InboxData; $before = @($data.items).Count
    $data.items = @(@($data.items) | Where-Object { $_.id -ne $Id })
    if (@($data.items).Count -ne $before) { Save-InboxData $data; return $true }
    return $false
}

# REJECT: the proposal is removed (never becomes data).
function Reject-InboxItem {
    param([Parameter(Mandatory)][string]$Id)
    if (Remove-InboxItem -Id $Id) { return [pscustomobject]@{ ok = $true; message = 'Proposal rejected and removed.' } }
    return [pscustomobject]@{ ok = $false; message = 'Proposal not found.' }
}

# A human label for where a type would go (for display + default destination).
function Get-InboxDestinationLabel {
    param([string]$Type)
    switch ($Type) {
        'goal'           { 'Goals (goal store)' }
        'project'        { 'Home Projects' }
        'task'           { 'Action Items' }
        'communication'  { 'Action Items (follow-up)' }
        'non-negotiable' { 'Non-Negotiables' }
        'family'         { 'Family' }
        'health'         { 'Health' }
        'financial'      { 'Financial' }
        'agency'         { 'Agency' }
        'learning'       { 'Learning' }
        'memory'         { 'Tony Memory (permission-gated)' }
        'calendar'       { 'Action Items (calendar is read-only)' }
        'crm'            { 'Action Items (CRM is read-only)' }
        'document'       { 'Action Items (document follow-up)' }
        default          { 'Action Items' }
    }
}

# Route an approved proposal to the OWNING module's writer. The inbox NEVER
# writes the data itself. Returns { ok; destination; newId; message }.
function Invoke-InboxRoute {
    param($Item)
    $title = [string]$Item.title; $desc = [string]$Item.description
    $addTask = {
        param($t)
        if (-not (Get-Command Add-ActionItem -ErrorAction SilentlyContinue)) { return $null }
        # Add-ActionItem returns the whole store (not the item), so mint the id
        # first, pass it in, and return it.
        $d = Get-ActionItemsData
        $newId = if (Get-Command Get-NextActionId -ErrorAction SilentlyContinue) { Get-NextActionId -Data $d } else { ('AI-{0:000}' -f (@($d.items).Count + 1)) }
        [void](Add-ActionItem -Data $d -Title $t -Id $newId)
        Save-ActionItemsData $d
        return $newId
    }
    try {
        switch ($Item.type) {
            'goal'           { if (Get-Command Add-Goal -EA SilentlyContinue) { $r = Add-Goal -Title $title -Reason $desc; return [pscustomobject]@{ ok = $true; destination = 'Goals'; newId = $r.id; message = ("Added goal {0}." -f $r.id) } } }
            'project'        { if (Get-Command Add-LifeItem -EA SilentlyContinue) { $r = Add-LifeItem -Domain 'projects' -Fields @{ title = $title; outcome = $desc }; return [pscustomobject]@{ ok = $true; destination = 'Home Projects'; newId = $r.id; message = ("Added project {0}." -f $r.id) } } }
            'non-negotiable' { if (Get-Command Add-LifeItem -EA SilentlyContinue) { $r = Add-LifeItem -Domain 'nonNegotiables' -Fields @{ title = $title; purpose = $desc }; return [pscustomobject]@{ ok = $true; destination = 'Non-Negotiables'; newId = $r.id; message = ("Added non-negotiable {0}." -f $r.id) } } }
            'family'         { if (Get-Command Add-LifeItem -EA SilentlyContinue) { $r = Add-LifeItem -Domain 'family' -Fields @{ kind = 'commitment'; title = $title; detail = $desc }; return [pscustomobject]@{ ok = $true; destination = 'Family'; newId = $r.id; message = ("Added family item {0}." -f $r.id) } } }
            'health'         { if (Get-Command Add-LifeItem -EA SilentlyContinue) { $r = Add-LifeItem -Domain 'health' -Fields @{ kind = 'next-action'; title = $title; detail = $desc }; return [pscustomobject]@{ ok = $true; destination = 'Health'; newId = $r.id; message = ("Added health item {0}." -f $r.id) } } }
            'financial'      { if (Get-Command Add-LifeItem -EA SilentlyContinue) { $r = Add-LifeItem -Domain 'financial' -Fields @{ kind = 'target'; title = $title; detail = $desc }; return [pscustomobject]@{ ok = $true; destination = 'Financial'; newId = $r.id; message = ("Added financial item {0}." -f $r.id) } } }
            'agency'         { if (Get-Command Add-LifeItem -EA SilentlyContinue) { $r = Add-LifeItem -Domain 'agency' -Fields @{ kind = 'next-step'; title = $title; detail = $desc }; return [pscustomobject]@{ ok = $true; destination = 'Agency'; newId = $r.id; message = ("Added agency item {0}." -f $r.id) } } }
            'learning'       { if (Get-Command Add-LifeItem -EA SilentlyContinue) { $r = Add-LifeItem -Domain 'learning' -Fields @{ title = $title; resource = $desc }; return [pscustomobject]@{ ok = $true; destination = 'Learning'; newId = $r.id; message = ("Added learning item {0}." -f $r.id) } } }
            'memory'         { if (Get-Command Approve-Memory -EA SilentlyContinue) { $cat = if ($Item.proposedDestination -in (Get-MemoryCategories)) { $Item.proposedDestination } else { 'Preferences' }; $r = Approve-Memory -Category $cat -Value $title -Why $desc -Source $(if ($Item.source) { $Item.source } else { 'conversation' }); if ($r) { return [pscustomobject]@{ ok = $true; destination = 'Tony Memory'; newId = $r.id; message = ("Approved memory {0}." -f $r.id) } } } }
            default {
                # task / communication / calendar / crm / document: read-only providers
                # cannot be written, so approval creates an honest follow-up Action Item.
                $t = if ($Item.type -in @('calendar', 'crm', 'document', 'communication')) { 'Follow up: ' + $title } else { $title }
                $id = & $addTask $t
                if ($id) { return [pscustomobject]@{ ok = $true; destination = 'Action Items'; newId = $id; message = ("Added action item {0}." -f $id) } }
            }
        }
    } catch {
        return [pscustomobject]@{ ok = $false; destination = ''; newId = $null; message = ("Could not add it: {0}" -f $_.Exception.Message) }
    }
    return [pscustomobject]@{ ok = $false; destination = ''; newId = $null; message = 'The owning module is not available; left pending.' }
}

# =====================================================================
# PROPOSAL KEYS + AWARENESS (Epic 6 - Workforce Activation)
# ---------------------------------------------------------------------
# Deterministic identity for a proposal so the Workforce never adds a
# duplicate: a stable key is type:sourceId when a real source id exists,
# else type:normalizedTitle. These are pure helpers shared by the inbox
# and the producer gate (core/workforce-proposals.ps1).
# =====================================================================

# Normalize a title to a comparable form: lower-case, punctuation to spaces,
# collapse whitespace, drop a leading "follow up:" so a follow-up and its plain
# form collide. Pure.
function Get-InboxNormalizedTitle {
    param([string]$Title)
    $t = ([string]$Title).ToLower().Trim()
    $t = $t -replace '^\s*follow[ -]?up:\s*', ''
    $t = $t -replace '[^a-z0-9 ]', ' '
    $t = ($t -replace '\s+', ' ').Trim()
    return $t
}

# The stable key for a candidate/proposal. type:sourceId when we have a real
# source id, else type:normalizedTitle. Pure.
function Get-ProposalKey {
    param([string]$Type, [string]$Title, [string]$SourceId = '')
    $ty = ([string]$Type).ToLower().Trim(); if (-not $ty) { $ty = 'task' }
    if ($SourceId -and -not [string]::IsNullOrWhiteSpace($SourceId)) { return ('{0}:{1}' -f $ty, ([string]$SourceId).Trim().ToLower()) }
    return ('{0}:{1}' -f $ty, (Get-InboxNormalizedTitle -Title $Title))
}

# The set of stable keys for the current pending proposals - the producer gate
# checks candidates against this so nothing already waiting is re-proposed.
function Get-InboxProposalKeys {
    $keys = @{}
    foreach ($it in @(Get-InboxItems -Status 'pending')) {
        $k = Get-ProposalKey -Type $it.type -Title $it.title -SourceId $it.sourceId
        $keys[$k] = $true
        if ($it.sourceId) { $keys[('{0}:{1}' -f ([string]$it.type).ToLower(), ([string]$it.sourceId).Trim().ToLower())] = $true }
    }
    return $keys
}

# Read-only awareness summary for Tony (Stage 1). Counts only - never the
# private content of a proposal. A read, not a write.
function Get-InboxSummary {
    param([datetime]$Now = (Get-Date))
    $pending = @(Get-InboxItems -Status 'pending')
    $byType = @{}
    foreach ($it in $pending) { $t = [string]$it.type; if ($byType.ContainsKey($t)) { $byType[$t]++ } else { $byType[$t] = 1 } }
    $oldest = 0
    foreach ($it in $pending) { try { $age = [int]([math]::Floor(($Now - [datetime]$it.created).TotalDays)); if ($age -gt $oldest) { $oldest = $age } } catch { } }
    $highConf = @($pending | Where-Object { [double]$_.confidence -ge 0.8 }).Count
    $timeRx = '(?i)\b(today|tomorrow|overdue|past due|deadline|expir|urgent|asap|final notice|by (eod|end of day))\b'
    $timeSensitive = @($pending | Where-Object {
            ($_.type -in @('calendar', 'communication')) -or ($_.title -match $timeRx) -or ($_.description -match $timeRx)
        }).Count
    return [pscustomobject]@{
        pending            = $pending.Count
        byType             = $byType
        oldestAgeDays      = $oldest
        highConfidenceCount = $highConf
        timeSensitiveCount = $timeSensitive
    }
}

# APPROVE: the OWNING module writes the real record, then the proposal leaves the
# inbox (no second copy). Never auto-called - only from Jake's explicit action.
function Approve-InboxItem {
    param([Parameter(Mandatory)][string]$Id, [string]$ApprovedBy = 'owner')
    $item = Get-InboxItemById -Id $Id
    if (-not $item) { return [pscustomobject]@{ ok = $false; message = 'Proposal not found.' } }
    if ($item.status -ne 'pending') { return [pscustomobject]@{ ok = $false; message = 'Proposal is not pending.' } }
    # Approval is the ONLY gate that starts an execution, and the Executive Action
    # Engine is the ONLY executor (PERMANENT DECISION, Epic 15.1): it validates,
    # persists the execution intent, executes through the owner's writer, VERIFIES
    # the owner store actually changed, and records the full audit trail. If the
    # engine is unavailable, approval FAILS CLOSED - the proposal stays pending
    # with a calm message, and there is NO direct owner-route fallback: an
    # unvalidated, unaudited, unverified execution path must not exist.
    if (-not (Get-Command Invoke-ProposalExecution -ErrorAction SilentlyContinue)) {
        return [pscustomobject]@{ ok = $false; destination = ''; newId = $null; message = 'The Action Engine is not available. Nothing was changed; the proposal is still pending.' }
    }
    # approval metadata is grounded in THIS user approval event - who, when, from
    # where, and a fingerprint of the proposal exactly as approved. The engine
    # rejects execution if the proposal no longer matches the fingerprint.
    $approval = [pscustomobject]@{
        approvedBy  = $ApprovedBy
        approvedAt  = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
        source      = 'executive-inbox'
        fingerprint = (Get-ProposalFingerprint -Proposal $item)
    }
    $exec = Invoke-ProposalExecution -Proposal $item -Approval $approval
    if ($exec.ok) {
        [void](Remove-InboxItem -Id $Id)   # data now lives in its owner; no copy kept
        return [pscustomobject]@{ ok = $true; destination = $exec.destination; newId = $exec.newId; message = $exec.message; executionId = $exec.executionId }
    }
    return [pscustomobject]@{ ok = $false; destination = ''; newId = $null; message = $exec.message; executionId = $exec.executionId }
}
