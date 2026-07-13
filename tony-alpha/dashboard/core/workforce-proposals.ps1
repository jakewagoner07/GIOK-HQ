# =====================================================================
# workforce-proposals.ps1  -  The Workforce turns findings into PROPOSALS
# ---------------------------------------------------------------------
# Epic 6 (Workforce Activation). Each specialist already ANALYZES a live
# signal; here it may PROPOSE - turning an evidence-backed finding into a
# pending item in the Executive Inbox for Jake to approve, edit, or reject.
#
# A proposal is NOT an action. Producing one writes ONLY to the pending
# Executive Inbox (via Add-InboxProposal). Nothing reaches the operating
# system automatically: approval (always Jake's) is the only thing that
# writes real data, through the existing OWNING module. Read-only providers
# (calendar, CRM, documents) are never written - a proposal is a request.
#
# Every candidate passes a deterministic de-dup / quality gate before it
# becomes a proposal:
#   * stable key (type:sourceId, else type:normalizedTitle)
#   * suppress if an equivalent proposal is already pending
#   * suppress if the destination owner already holds an equivalent record
#   * suppress below a confidence floor; cap the number added per scan
# Suppressions are logged to diagnostics as key+type+reason only - never the
# private content of a proposal.
#
# Pure orchestration over EXISTING engines. No new external provider, no new
# store, no scheduler. The scan runs on demand (Executive Inbox open + a
# button) - never inside Executive Context or the Briefing, which write nothing.
# =====================================================================

$ErrorActionPreference = 'Stop'

$script:ProposalConfidenceFloor = 0.5   # below this, a candidate is too weak to bother Jake
$script:ProposalScanCap         = 12    # most new proposals a single scan may add
$script:ProposalPerProducerCap  = 6     # most a single specialist may contribute per scan

function _WPDiag {
    param([string]$Message, [string]$Level = 'info')
    if (Get-Command Write-TonyDiag -ErrorAction SilentlyContinue) { Write-TonyDiag -Level $Level -Source 'workforce' -Message $Message }
}

# A candidate proposal (pre-gate). Plain shape the gate understands. Pure.
function New-ProposalCandidate {
    param(
        [string]$DiscoveredBy, [string]$Type, [string]$Title, [string]$Description = '',
        [double]$Confidence = 0.6, [string]$Source = '', [string]$SourceId = '', $Evidence = @()
    )
    return [pscustomobject]@{
        discoveredBy = $DiscoveredBy; type = $Type; title = ([string]$Title).Trim(); description = ([string]$Description).Trim()
        confidence = $Confidence; source = $Source; sourceId = $SourceId; evidence = @($Evidence)
    }
}

# Do two titles mean the same thing? Normalized equality, or one clearly
# contains the other (length-guarded so short words don't over-match). Pure.
function _TitlesMatch {
    param([string]$A, [string]$B)
    $na = Get-InboxNormalizedTitle -Title $A; $nb = Get-InboxNormalizedTitle -Title $B
    if (-not $na -or -not $nb) { return $false }
    if ($na -eq $nb) { return $true }
    if ($na.Length -ge 8 -and $nb.Length -ge 8 -and ($na.Contains($nb) -or $nb.Contains($na))) { return $true }
    return $false
}

# Would this candidate duplicate a record the destination OWNER already holds?
# Reads the owning module's active records read-only; never writes. This is what
# stops "communication follow-up" proposals for a reply Jake already has an open
# Action Item for, or a goal proposal for a goal that already exists.
function Test-DestinationDuplicate {
    param([string]$Type, [string]$Title, [string]$SourceId = '')
    try {
        switch ($Type) {
            'goal' {
                if (Get-Command Get-ActiveGoals -ErrorAction SilentlyContinue) {
                    foreach ($g in @(Get-ActiveGoals)) { if (_TitlesMatch $Title $g.title) { return $true } }
                }
            }
            { $_ -in @('project', 'non-negotiable', 'family', 'health', 'financial', 'agency', 'learning') } {
                $domain = switch ($Type) { 'project' { 'projects' } 'non-negotiable' { 'nonNegotiables' } default { $Type } }
                if (Get-Command Get-LifeItems -ErrorAction SilentlyContinue) {
                    foreach ($li in @(Get-LifeItems -Domain $domain -ActiveOnly)) {
                        $t = if ($li.PSObject.Properties.Name -contains 'title') { $li.title } else { '' }
                        if (_TitlesMatch $Title $t) { return $true }
                    }
                }
            }
            'memory' {
                if (Get-Command Get-Memories -ErrorAction SilentlyContinue) {
                    foreach ($m in @(Get-Memories)) { if (_TitlesMatch $Title ([string]$m.value)) { return $true } }
                }
            }
            default {
                # task / communication / calendar / crm / document all land in Action Items.
                if (Get-Command Get-ActionItemsData -ErrorAction SilentlyContinue) {
                    foreach ($ai in @((Get-ActionItemsData).items | Where-Object { -not $_.done -and -not $_.archived })) {
                        if (_TitlesMatch $Title ([string]$ai.title)) { return $true }
                    }
                }
            }
        }
    } catch { }
    return $false
}

# ------------------------------------------------------------------ #
# PRODUCERS - one per specialist. Each reads an EXISTING signal and returns
# candidate proposals (pre-gate). Empty when its signal is unavailable - no
# fabrication (Randy stays quiet with zero opportunities; Mason needs a doc).
# ------------------------------------------------------------------ #

# Sam - Head of Communications. From the Email Intelligence attention items
# (which already exclude newsletters, promotions, and automated noise): reply
# follow-ups, invitation responses, and carrier/underwriting reviews.
function Get-SamProposals {
    param($Context)
    $email = if (Get-Command Get-WorkforceEmail -ErrorAction SilentlyContinue) { Get-WorkforceEmail -Context $Context } else { $null }
    if (-not $email -or -not $email.ok -or -not $email.summary) { return @() }
    $out = @()
    foreach ($a in @($email.summary.attentionItems)) {
        $from = [string]$a.from; $subj = [string]$a.subject; $mid = [string]$a.messageId
        # Provenance: preserve provider + source account (plus sender, subject, id).
        # Concise, human, and NEVER a token/password/private header. E.g.
        #   [Yahoo - jake.wagoner@yahoo.com] From Mike: Policy documents needed
        $src0 = @($a.sources)[0]
        $prov = if ($src0) { [string]$src0.provider } else { '' }
        $acct = if ($src0) { [string]$src0.account } else { '' }
        $provLabel = switch ($prov.ToLower()) { 'gmail' { 'Gmail' } 'yahoo' { 'Yahoo' } '' { '' } default { $prov.Substring(0, 1).ToUpper() + $prov.Substring(1) } }
        $tag = if ($provLabel -and $acct) { ('[{0} - {1}] ' -f $provLabel, $acct) } elseif ($provLabel) { ('[{0}] ' -f $provLabel) } elseif ($acct) { ('[{0}] ' -f $acct) } else { '' }
        $ev = @([pscustomobject]@{ source = 'email'; provider = $prov; account = $acct; sender = $from; subject = $subj; sourceId = $mid; detail = ('{0}From {1}: {2}' -f $tag, $from, $subj) })
        switch ([string]$a.category) {
            'urgent'            { $out += New-ProposalCandidate -DiscoveredBy 'Sam' -Type 'communication' -Title ('Reply to {0}: {1}' -f $from, $subj) -Description 'Flagged time-sensitive; a person is likely waiting.' -Confidence 0.85 -Source 'email' -SourceId $mid -Evidence $ev }
            'needs-reply'       { $out += New-ProposalCandidate -DiscoveredBy 'Sam' -Type 'communication' -Title ('Reply to {0}: {1}' -f $from, $subj) -Description 'A person wrote and is likely waiting for a response.' -Confidence 0.8 -Source 'email' -SourceId $mid -Evidence $ev }
            'important-contact' { $out += New-ProposalCandidate -DiscoveredBy 'Sam' -Type 'communication' -Title ('Follow up with {0}: {1}' -f $from, $subj) -Description 'From someone on your important-contacts list.' -Confidence 0.8 -Source 'email' -SourceId $mid -Evidence $ev }
            'calendar-invite'   { $out += New-ProposalCandidate -DiscoveredBy 'Sam' -Type 'calendar' -Title ('Respond to invitation: {0}' -f $subj) -Description ('Calendar invitation from {0}.' -f $from) -Confidence 0.7 -Source 'email' -SourceId $mid -Evidence $ev }
            'carrier-underwriting' { $out += New-ProposalCandidate -DiscoveredBy 'Sam' -Type 'task' -Title ('Review carrier/underwriting update: {0}' -f $subj) -Description ('From {0}.' -f $from) -Confidence 0.7 -Source 'email' -SourceId $mid -Evidence $ev }
        }
    }
    return @($out | Select-Object -First $script:ProposalPerProducerCap)
}

# Ava - Calendar Manager. Meeting prep, conflict follow-ups, and protecting a
# non-negotiable / family commitment on a packed day. NEVER writes the calendar.
function Get-AvaProposals {
    param($Context)
    $cal = if (Get-Command Get-WorkforceCalendar -ErrorAction SilentlyContinue) { Get-WorkforceCalendar -Context $Context } else { $null }
    if (-not $cal -or -not $cal.ok -or -not $cal.insights) { return @() }
    $t = $cal.insights.today
    $out = @()
    $meetingHeavy = [bool]$t.meetingHeavy

    # meeting prep - just the first meeting of the day (keyed by event id so it
    # is proposed once, not every day)
    if ($t.firstMeeting -and $t.totalMeetings -gt 0) {
        $fm = $t.firstMeeting
        $out += New-ProposalCandidate -DiscoveredBy 'Ava' -Type 'task' -Title ('Prepare for {0}' -f $fm.title) `
            -Description ('First meeting today at {0}.' -f $fm.start.ToString('h:mm tt')) -Confidence 0.65 -Source 'calendar' -SourceId ([string]$fm.id) `
            -Evidence @([pscustomobject]@{ source = 'calendar'; sourceId = [string]$fm.id; detail = ('{0} at {1}' -f $fm.title, $fm.start.ToString('h:mm tt')) })
    }
    # conflicts
    foreach ($cf in @($cal.conflicts | Select-Object -First 3)) {
        $out += New-ProposalCandidate -DiscoveredBy 'Ava' -Type 'calendar' -Title ('Resolve calendar conflict: {0} overlaps {1}' -f $cf.a, $cf.b) `
            -Description 'Two events overlap; decide which takes the slot.' -Confidence 0.75 -Source 'calendar' `
            -Evidence @([pscustomobject]@{ source = 'calendar'; sourceId = $null; detail = ('{0} overlaps {1}' -f $cf.a, $cf.b) })
    }
    # threatened non-negotiable / family commitment when the day is packed
    if ($meetingHeavy -and $Context -and $Context.life) {
        foreach ($nn in @($Context.life.nonNegotiables | Select-Object -First 2)) {
            $out += New-ProposalCandidate -DiscoveredBy 'Ava' -Type 'task' -Title ('Protect time for your non-negotiable: {0}' -f $nn.title) `
                -Description 'A meeting-heavy day leaves little protected time.' -Confidence 0.7 -Source 'calendar' -SourceId ([string]$nn.id) `
                -Evidence @([pscustomobject]@{ source = 'life'; sourceId = [string]$nn.id; detail = ('non-negotiable: {0}' -f $nn.title) })
        }
        foreach ($f in @($Context.life.familyToday | Select-Object -First 2)) {
            $out += New-ProposalCandidate -DiscoveredBy 'Ava' -Type 'task' -Title ('Guard your family commitment today: {0}' -f $f.title) `
                -Description 'A full schedule risks crowding out family time.' -Confidence 0.72 -Source 'calendar' -SourceId ([string]$f.id) `
                -Evidence @([pscustomobject]@{ source = 'life'; sourceId = [string]$f.id; detail = ('family: {0}' -f $f.title) })
        }
    }
    return @($out | Select-Object -First $script:ProposalPerProducerCap)
}

# Riley - Timeline Analyst. Overdue / aging follow-ups from the Executive
# Timeline. Ages go in the DESCRIPTION so the title (and its key) stay stable -
# an unchanged overdue condition is proposed once, not daily.
function Get-RileyProposals {
    param($Context, [datetime]$Now = (Get-Date))
    if (-not (Get-Command Get-ExecutiveTimeline -ErrorAction SilentlyContinue)) { return @() }
    $waiting = $null
    if ((Get-Command Get-EmailWaiting -ErrorAction SilentlyContinue) -and (Get-Command Get-GmailStatus -ErrorAction SilentlyContinue)) {
        try { if ((Get-GmailStatus).state -eq 'connected') { $waiting = Get-EmailWaiting -Now $Now } } catch { }
    }
    $tl = Get-ExecutiveTimeline -Context $Context -Now $Now -WaitingEmails $waiting
    if (-not $tl -or -not $tl.hasAny) { return @() }
    $out = @()
    foreach ($o in @($tl.overdue | Select-Object -First 4)) {
        $out += New-ProposalCandidate -DiscoveredBy 'Riley' -Type 'task' -Title ('Follow up on overdue: {0}' -f $o.title) `
            -Description ('{0} days without movement.' -f $o.ageDays) -Confidence 0.75 -Source ([string]$o.source) -SourceId ([string]$o.sourceId) `
            -Evidence @([pscustomobject]@{ source = [string]$o.source; sourceId = [string]$o.sourceId; detail = ('overdue {0}d: {1}' -f $o.ageDays, $o.title) })
    }
    foreach ($a in @($tl.aging | Select-Object -First 2)) {
        $out += New-ProposalCandidate -DiscoveredBy 'Riley' -Type 'task' -Title ('Move a stalling item forward: {0}' -f $a.title) `
            -Description ('Aging - {0} days old.' -f $a.ageDays) -Confidence 0.6 -Source ([string]$a.source) -SourceId ([string]$a.sourceId) `
            -Evidence @([pscustomobject]@{ source = [string]$a.source; sourceId = [string]$a.sourceId; detail = ('aging {0}d: {1}' -f $a.ageDays, $a.title) })
    }
    return @($out | Select-Object -First $script:ProposalPerProducerCap)
}

# Emma - Priority Analyst. A next-step action for a goal that has one, and a
# gentle nudge for a genuinely neglected goal. Keyed by goal id, so an unchanged
# goal is not re-proposed.
function Get-EmmaProposals {
    param($Context, [datetime]$Now = (Get-Date))
    $goals = if ($Context -and $Context.activeGoals) { @($Context.activeGoals) } elseif (Get-Command Get-ActiveGoals -ErrorAction SilentlyContinue) { @(Get-ActiveGoals) } else { @() }
    if (@($goals).Count -eq 0) { return @() }
    $out = @()
    foreach ($g in $goals) {
        $gid = [string]$g.id
        if ($g.nextStep -and -not [string]::IsNullOrWhiteSpace($g.nextStep)) {
            $out += New-ProposalCandidate -DiscoveredBy 'Emma' -Type 'task' -Title ("Next step for '{0}': {1}" -f $g.title, $g.nextStep) `
                -Description ('The defined next step for goal {0}.' -f $gid) -Confidence 0.7 -Source 'goal' -SourceId $gid `
                -Evidence @([pscustomobject]@{ source = 'goal'; sourceId = $gid; detail = ('goal: {0}' -f $g.title) })
        } else {
            $stale = $false
            try { $stale = ([int]$g.progress -eq 0 -and ($Now - [datetime]$g.updated).TotalDays -ge 21) } catch { $stale = $false }
            if ($stale) {
                $out += New-ProposalCandidate -DiscoveredBy 'Emma' -Type 'task' -Title ("Revisit a neglected goal: '{0}'" -f $g.title) `
                    -Description 'No progress and no next step in three weeks - decide a next step or set it aside.' -Confidence 0.6 -Source 'goal' -SourceId ('neglect:' + $gid) `
                    -Evidence @([pscustomobject]@{ source = 'goal'; sourceId = $gid; detail = ('neglected goal: {0}' -f $g.title) })
            }
        }
    }
    return @($out | Select-Object -First $script:ProposalPerProducerCap)
}

# Randy - CRM Manager. Follow-ups for real CRM attention items. On a pipeline
# with zero opportunities Randy stays quiet (returns nothing) rather than invent.
function Get-RandyProposals {
    param($Context)
    $crm = if (Get-Command Get-WorkforceCRM -ErrorAction SilentlyContinue) { Get-WorkforceCRM -Context $Context } else { $null }
    if (-not $crm -or -not $crm.ok -or -not $crm.summary) { return @() }
    $sum = $crm.summary
    if ($sum.pipelineEmpty) { return @() }   # nothing real to act on - no fabrication
    $out = @()
    foreach ($a in @($sum.attentionItems | Select-Object -First 5)) {
        $verb = switch ([string]$a.kind) {
            'overdue-follow-up'    { 'Handle the overdue CRM follow-up' }
            'stalled-underwriting' { 'Unblock the underwriting deal' }
            'stalled-opportunity'  { 'Revive the stalled opportunity' }
            'aging-lead'           { 'Reach out to the aging lead' }
            default                { 'CRM follow-up' }
        }
        $out += New-ProposalCandidate -DiscoveredBy 'Randy' -Type 'crm' -Title ('{0}: {1}' -f $verb, $a.title) `
            -Description ([string]$a.detail) -Confidence 0.7 -Source 'crm' -SourceId ([string]$a.sourceId) `
            -Evidence @([pscustomobject]@{ source = 'crm'; sourceId = [string]$a.sourceId; detail = ('{0}: {1}' -f $a.title, $a.detail) })
    }
    return @($out | Select-Object -First $script:ProposalPerProducerCap)
}

# Mason - Document Analyst. ONLY from a document Jake explicitly asks him to
# analyze. Maps Document Intelligence's NEW suggestions (goals/tasks/projects it
# found are not already in the OS) into proposals, preserving the extracted line
# as evidence. Never monitors folders; never treats a maybe as a commitment.
function Get-MasonProposals {
    param([string]$Document)
    if (-not $Document -or -not (Get-Command Invoke-DocumentIntelligence -ErrorAction SilentlyContinue)) { return @() }
    $di = Invoke-DocumentIntelligence -Path $Document
    if (-not $di -or -not $di.ok) { return @() }
    $src = [string]$di.source
    $out = @()
    $groups = @(
        [pscustomobject]@{ type = 'goal';    items = @($di.suggestedGoals) },
        [pscustomobject]@{ type = 'task';    items = @($di.suggestedTasks) },
        [pscustomobject]@{ type = 'project'; items = @($di.suggestedProjects) }
    )
    foreach ($grp in $groups) {
        foreach ($sug in @($grp.items)) {
            $finding = [string]$sug.finding
            if ([string]::IsNullOrWhiteSpace($finding)) { continue }
            $out += New-ProposalCandidate -DiscoveredBy 'Mason' -Type $grp.type -Title $finding -Description ([string]$sug.comparison) `
                -Confidence 0.6 -Source 'document' -SourceId ($src + ':' + [string]$sug.id) `
                -Evidence @([pscustomobject]@{ source = 'document'; sourceId = $src; detail = ('extracted from {0}' -f $src) })
        }
    }
    return @($out | Select-Object -First $script:ProposalPerProducerCap)
}

# ------------------------------------------------------------------ #
# THE SCAN - run producers, gate the candidates, add survivors. On demand only.
# ------------------------------------------------------------------ #

# PHASE 1 (READ-ONLY) - build the context and run the specialist producers, returning
# the raw candidate list. Writes NOTHING, so it is safe to run off the UI thread on the
# Epic-9 background worker. Same producers, same order as before.
#   -Only <string[]>   run just these producers by name (Sam/Ava/Riley/Emma/Randy/Mason)
#   -Document <path>   give Mason a document to analyze (he is silent otherwise)
function Get-WorkforceProposalCandidates {
    param(
        $Context = $null,
        [datetime]$Now = (Get-Date),
        [string[]]$Only = @(),
        [string]$Document = ''
    )
    if (-not $Context -and (Get-Command Get-TonyExecutiveContext -ErrorAction SilentlyContinue)) {
        try { $Context = Get-TonyExecutiveContext -CurrentWorkspace 'Executive Inbox' -CurrentQuestion 'Scan for new Workforce proposals.' -Now $Now } catch { $Context = $null }
    }

    $runAll = (@($Only).Count -eq 0)
    $wants = { param($name) $runAll -or ($Only -contains $name) }

    $candidates = @()
    if (& $wants 'Sam')   { $candidates += @(Get-SamProposals   -Context $Context) }
    if (& $wants 'Ava')   { $candidates += @(Get-AvaProposals   -Context $Context) }
    if (& $wants 'Riley') { $candidates += @(Get-RileyProposals -Context $Context -Now $Now) }
    if (& $wants 'Emma')  { $candidates += @(Get-EmmaProposals  -Context $Context -Now $Now) }
    if (& $wants 'Randy') { $candidates += @(Get-RandyProposals -Context $Context) }
    if ((& $wants 'Mason') -and $Document) { $candidates += @(Get-MasonProposals -Document $Document) }
    return @($candidates)
}

# PHASE 2 (WRITES) - the EXACT existing de-dup/quality gate followed by Add-InboxProposal
# for survivors. Runs ONLY on the UI/owner thread, sequentially. The gate reads the CURRENT
# pending inbox + owner records at commit time, so idempotency holds even if state changed
# while candidates were being generated. Returns { added; suppressed; byType; addedItems; ran }.
function Add-WorkforceProposalCandidates {
    param(
        $Candidates = @(),
        [datetime]$Now = (Get-Date)
    )
    $pendingKeys = if (Get-Command Get-InboxProposalKeys -ErrorAction SilentlyContinue) { Get-InboxProposalKeys } else { @{} }
    $seen = @{}
    $added = 0; $suppressed = 0; $byType = @{}; $addedItems = @()

    foreach ($c in @($Candidates)) {
        if (-not $c -or [string]::IsNullOrWhiteSpace($c.title)) { continue }
        $key = Get-ProposalKey -Type $c.type -Title $c.title -SourceId $c.sourceId

        # Diagnostics record type + who + reason only - NEVER the title/key, which
        # can embed a subject line or other private content.
        if ([double]$c.confidence -lt $script:ProposalConfidenceFloor) { $suppressed++; _WPDiag ("suppressed [{0}] type={1} reason=low-confidence" -f $c.discoveredBy, $c.type); continue }
        if ($seen.ContainsKey($key)) { $suppressed++; _WPDiag ("suppressed [{0}] type={1} reason=duplicate-in-scan" -f $c.discoveredBy, $c.type); continue }
        if ($pendingKeys.ContainsKey($key)) { $suppressed++; _WPDiag ("suppressed [{0}] type={1} reason=already-pending" -f $c.discoveredBy, $c.type); continue }
        if (Test-DestinationDuplicate -Type $c.type -Title $c.title -SourceId $c.sourceId) { $suppressed++; _WPDiag ("suppressed [{0}] type={1} reason=already-in-owner" -f $c.discoveredBy, $c.type); continue }
        if ($added -ge $script:ProposalScanCap) { $suppressed++; _WPDiag ("suppressed [{0}] type={1} reason=scan-cap" -f $c.discoveredBy, $c.type); continue }

        $item = Add-InboxProposal -DiscoveredBy $c.discoveredBy -Type $c.type -Title $c.title -Description $c.description `
            -Evidence $c.evidence -Confidence $c.confidence -Source $c.source -SourceId $c.sourceId
        if ($item) {
            $seen[$key] = $true
            $added++
            $t = [string]$item.type; if ($byType.ContainsKey($t)) { $byType[$t]++ } else { $byType[$t] = 1 }
            $addedItems += [pscustomobject]@{ id = $item.id; type = $item.type; title = $item.title; discoveredBy = $item.discoveredBy }
        }
    }

    if ($added -gt 0 -or $suppressed -gt 0) { _WPDiag ("scan complete: {0} added, {1} suppressed" -f $added, $suppressed) }
    return [pscustomobject]@{ added = $added; suppressed = $suppressed; byType = $byType; addedItems = @($addedItems); ran = $true }
}

# The scan, unchanged for every caller: analyze (read-only) then commit (writes). The async
# UI path calls the two phases separately (analysis off-thread, commit on the owner thread);
# every other caller and the synchronous/headless path get identical behavior here.
function Invoke-WorkforceProposals {
    param(
        $Context = $null,
        [datetime]$Now = (Get-Date),
        [string[]]$Only = @(),
        [string]$Document = ''
    )
    $cands = Get-WorkforceProposalCandidates -Context $Context -Now $Now -Only $Only -Document $Document
    return (Add-WorkforceProposalCandidates -Candidates $cands -Now $Now)
}
