# =====================================================================
# tony-core.ps1  —  Tony Alpha business logic layer
# ---------------------------------------------------------------------
# NO UI CODE LIVES HERE. This module reads the source-of-truth files
# and returns plain data. The UI layer (ui/tony-ui.ps1) only renders
# whatever these functions return.
#
# Source files (all live in tony-alpha/, two levels up from here):
#   agents_registry.json  <- single source of truth for agents
#   issues_log.md, action_items.md, weekly_status.md, ROADMAP.md
#
# Nothing is duplicated: agent data is only ever read from the registry;
# doc views are only ever read from their .md files.
# =====================================================================

$ErrorActionPreference = 'Stop'

function Get-DocPath {
    param([Parameter(Mandatory)][string]$Name)
    return (Join-Path $PSScriptRoot ('..\..\' + $Name))
}

function Get-RegistryPath { return (Resolve-Path (Get-DocPath 'agents_registry.json')).Path }

function Get-Registry {
    $path = Get-RegistryPath
    if (-not (Test-Path $path)) { throw "agents_registry.json not found at: $path" }
    return (Get-Content -Path $path -Raw -Encoding UTF8 | ConvertFrom-Json)
}

function Get-AgentsList { return @((Get-Registry).agents) }

function Get-DocText {
    param([Parameter(Mandatory)][string]$Name)
    $p = Get-DocPath $Name
    if (Test-Path $p) { return (Get-Content -Path $p -Raw -Encoding UTF8) }
    return "($Name not found next to the registry.)"
}

function Get-Greeting {
    param([datetime]$Now = (Get-Date))
    $h = $Now.Hour
    if     ($h -lt 12) { return 'Good Morning, Jake' }
    elseif ($h -lt 17) { return 'Good Afternoon, Jake' }
    else               { return 'Good Evening, Jake' }
}

# ---- light markdown parsers (read real files; used for dashboard summaries) ----

function Get-IssuesSummary {
    # Extract the "Open flags" entries from issues_log.md. Source stays the .md file.
    $items = @()
    try {
        $lines = Get-Content -Path (Get-DocPath 'issues_log.md') -Encoding UTF8
        $inOpen = $false
        foreach ($l in $lines) {
            if ($l -match '^##\s+Open flags') { $inOpen = $true; continue }
            elseif ($l -match '^##\s+')        { $inOpen = $false }
            if ($inOpen -and $l -match '^###\s+(.+)$') {
                $h = ($Matches[1] -replace '^[^\w]*', '').Trim()   # strip leading emoji/symbols
                $id = ''; $title = $h
                if ($h -match '^(\S+)\s+\p{Pd}\s+(.+)$') { $id = $Matches[1]; $title = $Matches[2] }
                $items += [pscustomobject]@{ id = $id; title = $title }
            }
        }
    } catch { }
    return $items
}

function Get-ActionItemsSummary {
    # Extract checkbox items from action_items.md. Source stays the .md file.
    $items = @()
    try {
        $lines = Get-Content -Path (Get-DocPath 'action_items.md') -Encoding UTF8
        foreach ($l in $lines) {
            if ($l -match '^\s*-\s+([^\s*]{1,3})\s+\*\*(.+?)\*\*') {
                $mark = $Matches[1]; $body = $Matches[2]
                $done = ($mark -eq [char]0x2611) -or ($mark -match '\[[xX]\]')
                $id = ''; $title = $body
                if ($body -match '^(\S+)\s+\p{Pd}\s+(.+)$') { $id = $Matches[1]; $title = $Matches[2] }
                $items += [pscustomobject]@{ id = $id; title = ($title -replace '\*\*', ''); done = [bool]$done }
            }
        }
    } catch { }
    return $items
}

function Get-TonyModel {
    param([datetime]$Now = (Get-Date))

    $reg    = Get-Registry
    $agents = @($reg.agents)

    # ---- Agent Summary (LIVE from registry) ----
    $byStatus = [ordered]@{}
    foreach ($s in $reg.meta.status_values) { $byStatus[$s] = 0 }
    foreach ($a in $agents) { if ($byStatus.Contains($a.status)) { $byStatus[$a.status]++ } else { $byStatus[$a.status] = 1 } }

    $byPriority = [ordered]@{ Critical = 0; High = 0; Normal = 0; Low = 0 }
    foreach ($a in $agents) { if ($byPriority.Contains($a.priority)) { $byPriority[$a.priority]++ } }

    $byOwner = [ordered]@{}
    foreach ($a in $agents) { if (-not $byOwner.Contains($a.owner)) { $byOwner[$a.owner] = 0 }; $byOwner[$a.owner]++ }

    $withHealth       = @($agents | Where-Object { $null -ne $_.health_score })
    $agentsWithIssues = @($agents | Where-Object { @($_.issues).Count -gt 0 })

    $overallHealth = if ($withHealth.Count -eq 0) { 'N/A' }
                     else { '{0}%' -f [math]::Round(($withHealth.health_score | Measure-Object -Average).Average) }
    $registryStatus = if (-not $reg.meta.verified_against_scheduler) { 'Catalogued (unverified)' } else { 'Verified' }

    return [pscustomobject]@{
        generatedAt = $Now
        greeting    = Get-Greeting -Now $Now
        dateText    = $Now.ToString('dddd, MMMM d, yyyy')
        timeText    = $Now.ToString('h:mm:ss tt')

        agentSummary = [pscustomobject]@{
            total = $agents.Count; byStatus = $byStatus; byPriority = $byPriority
            byOwner = $byOwner; critical = $byPriority['Critical']
        }
        registryHealth = [pscustomobject]@{
            version = $reg.meta.version; verified = [bool]$reg.meta.verified_against_scheduler
            registryStatus = $registryStatus
            healthCoverage = "$($withHealth.Count)/$($agents.Count) measured"
            overallHealth = $overallHealth; agentsWithIssues = $agentsWithIssues.Count
            sourceFile = 'agents_registry.json'; lastUpdated = $reg.meta.last_updated
        }

        # LIVE from the .md files (parsed, not duplicated)
        openIssues  = @(Get-IssuesSummary)
        actionItems = @(Get-ActionItemsSummary)

        # Current sprint has no backing file yet -> placeholder
        currentSprint = [pscustomobject]@{
            name = 'Sprint Charlie - Hub Navigation'
            objective = 'Turn Tony Alpha into a simple command hub.'
            status = 'In Progress'
        }
    }
}
