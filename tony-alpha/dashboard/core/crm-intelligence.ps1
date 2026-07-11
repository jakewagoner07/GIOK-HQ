# =====================================================================
# crm-intelligence.ps1  -  provider-neutral book-of-business intelligence
# ---------------------------------------------------------------------
# The VENDOR-NEUTRAL analysis layer for the CRM. It knows nothing about
# GoHighLevel (or any CRM product). It reads ONLY the NORMALIZED CRM MODEL
# (leads/contacts, opportunities, pipeline stages, follow-ups) that a CRM
# provider hands it, and derives the calm "book of business" read Randy the
# CRM Manager reports to Tony: aging leads, stalled opportunities, overdue
# follow-ups, in-underwriting deals, revenue at risk, and business-health
# counts.
#
# It stores NOTHING and it never fetches - it is a pure function of the
# normalized data + Now + thresholds. All vendor specifics (endpoints,
# field mapping, date formats) live in the provider; all judgment thresholds
# (aging/stalled windows) live here, provider-neutral. This is the layer at
# which multiple CRMs would merge, exactly like email-intelligence merges
# mail from any backend.
#
# HONESTY: it derives only from fields the provider says are AVAILABLE. It
# never invents policies, renewals, underwriting, revenue, or follow-ups the
# CRM did not expose - those arrive flagged unavailable and are reported so.
# =====================================================================

$ErrorActionPreference = 'Stop'

# Age in whole hours/days between a timestamp and Now (0 if missing).
function Get-CrmAgeHours { param($When, [datetime]$Now) if (-not $When) { return $null } try { return [int][math]::Floor(($Now - [datetime]$When).TotalHours) } catch { return $null } }
function Get-CrmAgeDays  { param($When, [datetime]$Now) $h = Get-CrmAgeHours -When $When -Now $Now; if ($null -eq $h) { return $null } return [int][math]::Floor($h / 24) }

# Human phrase for an age, honest and calm.
function Format-CrmAge {
    param([int]$Days, [int]$Hours)
    if ($Days -ge 1) { return ('{0} day{1}' -f $Days, $(if ($Days -eq 1) { '' } else { 's' })) }
    return ('{0} hour{1}' -f $Hours, $(if ($Hours -eq 1) { '' } else { 's' }))
}

# THE neutral read. Input: the normalized CRM object from a provider (Get-CRM).
# Output: a calm summary Randy reports. Pure - no side effects, no storage.
function Get-CRMSummary {
    param($Crm, [datetime]$Now = (Get-Date), $Config = $null)

    $agingHours  = 48; $stalledDays = 14; $recentLeadDays = 30
    if ($Config) {
        if ($Config.PSObject.Properties.Name -contains 'agingLeadHours' -and $Config.agingLeadHours) { $agingHours = [int]$Config.agingLeadHours }
        if ($Config.PSObject.Properties.Name -contains 'stalledOpportunityDays' -and $Config.stalledOpportunityDays) { $stalledDays = [int]$Config.stalledOpportunityDays }
        if ($Config.PSObject.Properties.Name -contains 'recentLeadDays' -and $Config.recentLeadDays) { $recentLeadDays = [int]$Config.recentLeadDays }
    }

    $contacts = @(); $opps = @(); $followUps = @()
    $contactsCapped = $false
    if ($Crm) {
        if ($Crm.contacts -and $Crm.contacts.available) { $contacts = @($Crm.contacts.items); $contactsCapped = [bool]$Crm.contacts.capped }
        if ($Crm.opportunities -and $Crm.opportunities.available) { $opps = @($Crm.opportunities.items) }
        if ($Crm.followUps -and $Crm.followUps.available) { $followUps = @($Crm.followUps.items) }
    }

    # --- aging leads: NEW opportunities going cold -----------------------
    # A "lead" in CRM terms is an OPPORTUNITY in a pipeline - NOT a raw contact.
    # Raw contacts are the whole address book (clients, dead leads, people in
    # automated drip sequences) and must NOT be treated as leads-needing-follow-
    # up; doing so floods Jake with false urgency. So aging leads are derived
    # from OPPORTUNITIES: an OPEN opp created recently (within the recent-lead
    # window) that has had no activity within the aging window but is not yet
    # "stalled" - a fresh lead going cold. If no opportunities exist, there are
    # no aging leads to report (and Randy says pipeline visibility is limited).
    $agingLeads = @()
    foreach ($o in $opps) {
        if (([string]$o.status) -and ([string]$o.status).ToLower() -ne 'open') { continue }
        $h = Get-CrmAgeHours -When $o.lastActivityAt -Now $Now
        $createdDays = Get-CrmAgeDays -When $o.createdAt -Now $Now
        if ($null -ne $h -and $h -ge $agingHours -and $h -lt ($stalledDays * 24) -and $null -ne $createdDays -and $createdDays -le $recentLeadDays) {
            $nm = if ($o.contactName) { $o.contactName } else { $o.title }
            $agingLeads += [pscustomobject]@{ id = $o.id; name = $nm; title = $o.title; ageHours = $h; ageDays = [int][math]::Floor($h / 24); createdDays = $createdDays; stageName = $o.stageName; value = [double]$o.value; sourceId = $o.sourceId; sourceAccount = $o.sourceAccount }
        }
    }
    $agingLeads = @($agingLeads | Sort-Object -Property ageHours -Descending)

    # contacts are the address book - a COUNT, never "leads to work"
    $recentContacts = 0
    foreach ($c in $contacts) { $cd = Get-CrmAgeDays -When $c.createdAt -Now $Now; if ($null -ne $cd -and $cd -le $recentLeadDays) { $recentContacts++ } }

    # --- stalled opportunities: open, no activity within the stalled window
    $stalled = @()
    foreach ($o in $opps) {
        if (([string]$o.status) -and ([string]$o.status).ToLower() -ne 'open') { continue }
        $d = Get-CrmAgeDays -When $o.lastActivityAt -Now $Now
        if ($null -ne $d -and $d -ge $stalledDays) {
            $stalled += [pscustomobject]@{ id = $o.id; title = $o.title; stageName = $o.stageName; pipelineName = $o.pipelineName; ageDays = $d; value = [double]$o.value; inUnderwriting = [bool]$o.inUnderwriting; contactName = $o.contactName; sourceId = $o.sourceId; sourceAccount = $o.sourceAccount }
        }
    }
    $stalled = @($stalled | Sort-Object -Property ageDays -Descending)

    # --- overdue follow-ups: not completed, due in the past ---------------
    $overdue = @()
    foreach ($t in $followUps) {
        if ([bool]$t.completed) { continue }
        if (-not $t.dueDate) { continue }
        $d = Get-CrmAgeDays -When $t.dueDate -Now $Now
        if ($null -ne $d -and $d -ge 1) {
            $overdue += [pscustomobject]@{ id = $t.id; title = $t.title; ageDays = $d; dueDate = $t.dueDate; contactId = $t.contactId; sourceId = $t.sourceId; sourceAccount = $t.sourceAccount }
        }
    }
    $overdue = @($overdue | Sort-Object -Property ageDays -Descending)

    # --- in underwriting (derived from real pipeline STAGE identity) ------
    $inUnderwriting = @($opps | Where-Object { [bool]$_.inUnderwriting -and (([string]$_.status).ToLower() -eq 'open' -or -not $_.status) } | ForEach-Object {
            [pscustomobject]@{ id = $_.id; title = $_.title; stageName = $_.stageName; ageDays = (Get-CrmAgeDays -When $_.lastActivityAt -Now $Now); value = [double]$_.value; sourceId = $_.sourceId; sourceAccount = $_.sourceAccount }
        })

    # --- business health (only from available sections) -------------------
    $openOpps = @($opps | Where-Object { -not $_.status -or ([string]$_.status).ToLower() -eq 'open' })
    $openValue = 0.0; foreach ($o in $openOpps) { $openValue += [double]$o.value }
    $revenueAtRisk = 0.0; foreach ($o in $stalled) { $revenueAtRisk += [double]$o.value }

    # is pipeline data even present? (opportunities available but none exist)
    $oppsAvailable = [bool]($Crm -and $Crm.opportunities -and $Crm.opportunities.available)
    $pipelineEmpty = [bool]($oppsAvailable -and @($opps).Count -eq 0)

    $businessHealth = [pscustomobject]@{
        contactCount         = @($contacts).Count
        contactsCapped       = $contactsCapped
        recentContacts       = $recentContacts
        recentLeadWindowDays = $recentLeadDays
        openOpportunities    = @($openOpps).Count
        openValue            = [math]::Round($openValue, 2)
        agingLeadCount       = @($agingLeads).Count
        stalledCount         = @($stalled).Count
        overdueFollowUpCount = @($overdue).Count
        inUnderwritingCount  = @($inUnderwriting).Count
        revenueAtRisk        = [math]::Round($revenueAtRisk, 2)
        pipelineEmpty        = $pipelineEmpty
    }

    # --- attention items: the few things that deserve Jake, ranked --------
    # overdue follow-ups first (a promise past due), then stalled-in-underwriting,
    # then other stalled deals, then aging leads. Each carries its evidence.
    $attention = @()
    foreach ($t in @($overdue | Select-Object -First 3)) {
        $attention += [pscustomobject]@{ kind = 'overdue-follow-up'; title = $t.title; detail = ('follow-up overdue by {0}' -f (Format-CrmAge -Days $t.ageDays -Hours ($t.ageDays * 24))); source = 'crm'; sourceId = $t.sourceId; rank = 1 }
    }
    foreach ($o in @($stalled | Where-Object { $_.inUnderwriting } | Select-Object -First 2)) {
        $attention += [pscustomobject]@{ kind = 'stalled-underwriting'; title = $o.title; detail = ('stalled {0} in underwriting ({1})' -f (Format-CrmAge -Days $o.ageDays -Hours ($o.ageDays * 24)), $o.stageName); source = 'crm'; sourceId = $o.sourceId; rank = 2 }
    }
    foreach ($o in @($stalled | Where-Object { -not $_.inUnderwriting } | Select-Object -First 2)) {
        $attention += [pscustomobject]@{ kind = 'stalled-opportunity'; title = $o.title; detail = ('no activity in {0} ({1})' -f (Format-CrmAge -Days $o.ageDays -Hours ($o.ageDays * 24)), $o.stageName); source = 'crm'; sourceId = $o.sourceId; rank = 3 }
    }
    foreach ($l in @($agingLeads | Select-Object -First 3)) {
        $attention += [pscustomobject]@{ kind = 'aging-lead'; title = $l.name; detail = ('new lead, no follow-up in {0}' -f (Format-CrmAge -Days $l.ageDays -Hours $l.ageHours)); source = 'crm'; sourceId = $l.sourceId; rank = 4 }
    }
    $attention = @($attention | Sort-Object -Property rank | Select-Object -First 6)

    # --- headline: only non-zero clauses; calm when the book is current ---
    $clauses = @()
    if ($agingLeads.Count -gt 0)    { $clauses += ('{0} new lead{1} with no follow-up in {2}h' -f $agingLeads.Count, $(if ($agingLeads.Count -eq 1) { '' } else { 's' }), $agingHours) }
    if ($inUnderwriting.Count -gt 0){ $clauses += ('{0} opportunit{1} in underwriting' -f $inUnderwriting.Count, $(if ($inUnderwriting.Count -eq 1) { 'y' } else { 'ies' })) }
    if ($stalled.Count -gt 0)       { $clauses += ('{0} opportunit{1} stalled' -f $stalled.Count, $(if ($stalled.Count -eq 1) { 'y' } else { 'ies' })) }
    if ($overdue.Count -gt 0)       { $clauses += ('{0} follow-up{1} overdue' -f $overdue.Count, $(if ($overdue.Count -eq 1) { '' } else { 's' })) }
    $contactStr = if ($contactsCapped) { ('{0}+' -f @($contacts).Count) } else { ('{0}' -f @($contacts).Count) }
    # A note when the pipeline is empty: be honest that lead signals can't be
    # assessed, rather than implying an all-clear that was never checked.
    $note = $null
    if ($pipelineEmpty) { $note = ('GoHighLevel returns no open opportunity records, so pipeline position, stalled deals, and renewals cannot be assessed. Your book holds {0} contact(s).' -f $contactStr) }
    $headline = if ($clauses.Count -gt 0) { (($clauses -join '; ') + '.') }
    elseif ($pipelineEmpty) { ('No open opportunities are in the pipeline right now ({0} contact(s) in the book).' -f $contactStr) }
    else { 'The book of business looks current - no new leads going cold, nothing overdue or stalled.' }

    # --- what the CRM honestly did NOT expose (for transparency) ----------
    $unavailable = @()
    foreach ($sec in @('policies', 'renewals', 'requirements', 'appointments')) {
        if ($Crm -and ($Crm.PSObject.Properties.Name -contains $sec)) {
            $s = $Crm.$sec
            if ($s -and -not $s.available) { $unavailable += [pscustomobject]@{ area = $sec; reason = [string]$s.reason } }
        }
    }

    return [pscustomobject]@{
        headline       = $headline
        note           = $note
        agingLeads     = @($agingLeads)
        stalled        = @($stalled)
        overdue        = @($overdue)
        inUnderwriting = @($inUnderwriting)
        businessHealth = $businessHealth
        attentionItems = @($attention)
        unavailable    = @($unavailable)
        hasAttention   = [bool](@($attention).Count -gt 0)
        pipelineEmpty  = $pipelineEmpty
        thresholds     = [pscustomobject]@{ agingLeadHours = $agingHours; stalledOpportunityDays = $stalledDays }
    }
}
