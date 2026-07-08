# =====================================================================
# tony-core.ps1  —  Tony Alpha business logic layer
# ---------------------------------------------------------------------
# NO UI CODE LIVES HERE. This module reads the single source of truth
# (agents_registry.json) and returns a plain data "model" object.
# The UI layer (ui/tony-ui.ps1) only renders whatever this returns.
#
# Anything that is not yet wired to live data is provided as clearly
# labelled PLACEHOLDER data (Sprint Alpha requirement #9).
# =====================================================================

$ErrorActionPreference = 'Stop'

function Get-RegistryPath {
    # Registry lives two levels up from dashboard/core/
    return (Resolve-Path (Join-Path $PSScriptRoot '..\..\agents_registry.json')).Path
}

function Get-Registry {
    $path = Get-RegistryPath
    if (-not (Test-Path $path)) { throw "agents_registry.json not found at: $path" }
    return (Get-Content -Path $path -Raw | ConvertFrom-Json)
}

function Get-Greeting {
    param([datetime]$Now = (Get-Date))
    $h = $Now.Hour
    if ($h -lt 12)      { return 'Good Morning, Jake' }
    elseif ($h -lt 17)  { return 'Good Afternoon, Jake' }
    else                { return 'Good Evening, Jake' }
}

function Get-TonyModel {
    param([datetime]$Now = (Get-Date))

    $reg    = Get-Registry
    $agents = @($reg.agents)

    # ---- Agent Summary (LIVE from registry) ----
    $byStatus = [ordered]@{}
    foreach ($s in $reg.meta.status_values) { $byStatus[$s] = 0 }
    foreach ($a in $agents) {
        if ($byStatus.Contains($a.status)) { $byStatus[$a.status]++ } else { $byStatus[$a.status] = 1 }
    }

    $byPriority = [ordered]@{ Critical = 0; High = 0; Normal = 0; Low = 0 }
    foreach ($a in $agents) { if ($byPriority.Contains($a.priority)) { $byPriority[$a.priority]++ } }

    $byOwner = [ordered]@{}
    foreach ($a in $agents) {
        if (-not $byOwner.Contains($a.owner)) { $byOwner[$a.owner] = 0 }
        $byOwner[$a.owner]++
    }

    $withHealth      = @($agents | Where-Object { $null -ne $_.health_score })
    $agentsWithIssues = @($agents | Where-Object { @($_.issues).Count -gt 0 })

    # ---- Registry Health (LIVE from registry) ----
    $healthCoverage = "$($withHealth.Count)/$($agents.Count) measured"
    $overallHealth  = if ($withHealth.Count -eq 0) { 'N/A' }
                      else { '{0}%' -f [math]::Round(($withHealth.health_score | Measure-Object -Average).Average) }
    $registryStatus = if (-not $reg.meta.verified_against_scheduler) { 'Catalogued (unverified)' } else { 'Verified' }

    # ---- Open Issues (PLACEHOLDER — mirrors issues_log.md, not yet wired live) ----
    $openIssues = @(
        [pscustomobject]@{ id = 'META-001';    type = 'metadata'; title = 'Owner/priority/dependencies are provisional' }
        [pscustomobject]@{ id = 'OVERLAP-001'; type = 'overlap';  title = 'GHL SMS Monitor <-> GHL Lead Text Batch' }
        [pscustomobject]@{ id = 'OVERLAP-002'; type = 'overlap';  title = 'Lead Research <-> Engagement Leads' }
        [pscustomobject]@{ id = 'OVERLAP-003'; type = 'overlap';  title = 'Email Triage Digest <-> Morning Digest' }
        [pscustomobject]@{ id = 'OVERLAP-004'; type = 'overlap';  title = 'Morning Digest <-> Tony Morning Briefing' }
        [pscustomobject]@{ id = 'OVERLAP-005'; type = 'overlap';  title = 'Agent Health Check <-> Performance Review' }
        [pscustomobject]@{ id = 'OVERLAP-006'; type = 'overlap';  title = 'Weekly cluster (4 agents)' }
    )

    # ---- Action Items (PLACEHOLDER — mirrors action_items.md, not yet wired live) ----
    $actionItems = @(
        [pscustomobject]@{ id = 'AI-001'; done = $false; title = 'Confirm real schedules for all agents' }
        [pscustomobject]@{ id = 'AI-002'; done = $false; title = 'Confirm last-run + status (leave unknown until observed)' }
        [pscustomobject]@{ id = 'AI-A1'; done = $false; title = 'Confirm agent owners (Admin vs Finance for Log Hours)' }
        [pscustomobject]@{ id = 'AI-A3'; done = $false; title = 'Confirm dependencies (seed integrations registry)' }
        [pscustomobject]@{ id = 'AR-001'; done = $true;  title = 'Architecture Review 001 registry improvements' }
    )

    # ---- Current Sprint (PLACEHOLDER) ----
    $currentSprint = [pscustomobject]@{
        name      = 'Sprint Alpha - Dashboard Build'
        objective = 'Prove Tony can launch as a real desktop application.'
        status    = 'In Progress'
        items     = @(
            'Launch locally in a desktop window',
            'Read agents_registry.json as source of truth',
            'Show summary, issues, actions, health, sprint',
            'Keep business logic separate from UI'
        )
    }

    # ---- Assemble model ----
    return [pscustomobject]@{
        generatedAt  = $Now
        greeting     = Get-Greeting -Now $Now
        dateText     = $Now.ToString('dddd, MMMM d, yyyy')
        timeText     = $Now.ToString('h:mm:ss tt')

        agentSummary = [pscustomobject]@{
            total      = $agents.Count
            byStatus   = $byStatus
            byPriority = $byPriority
            byOwner    = $byOwner
            critical   = $byPriority['Critical']
        }

        registryHealth = [pscustomobject]@{
            version         = $reg.meta.version
            verified        = [bool]$reg.meta.verified_against_scheduler
            registryStatus  = $registryStatus
            healthCoverage  = $healthCoverage
            overallHealth   = $overallHealth
            agentsWithIssues = $agentsWithIssues.Count
            sourceFile      = 'agents_registry.json'
            lastUpdated     = $reg.meta.last_updated
        }

        openIssues    = $openIssues
        actionItems   = $actionItems
        currentSprint = $currentSprint

        dataSources = [pscustomobject]@{
            live        = 'Agent Summary, Registry Health'
            placeholder = 'Open Issues, Action Items, Current Sprint'
        }
    }
}
