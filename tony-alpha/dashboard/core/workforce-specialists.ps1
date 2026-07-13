# =====================================================================
# workforce-specialists.ps1  —  Tony's initial specialist analysts
# ---------------------------------------------------------------------
# The first internal specialists on the Workforce Engine. Each one uses
# EXISTING provider outputs only - it never re-implements provider logic,
# never stores anything, and never acts. It reads the single Executive
# Context (or the existing provider function when the context doesn't carry
# its data), analyzes, and returns the STANDARD report. Tony merges them.
#
#   Sam    - Head of Communications; reads ONE combined signal (Gmail + Yahoo)
#   Ava    - Calendar Manager; reads Get-Calendar / the calendar signal
#   Mason  - Document Analyst; reads Document Intelligence (when a doc is queued)
#   Emma   - Priority Analyst; wraps the Executive Priority Engine (D18)
#   Riley  - Timeline Analyst; wraps the Executive Timeline (D19)
#   Randy  - CRM Manager; reads the normalized crm signal
#
# Emma/Riley activate automatically when their engines are in
# the build (Get-ExecutivePriorities / Get-ExecutiveTimeline). Until then they
# report honestly that the capability is not present - no duplicated logic,
# no fabrication, full future compatibility.
# =====================================================================

$ErrorActionPreference = 'Stop'

# Resolve a live signal: prefer what the Executive Context already carries;
# otherwise call the existing provider function ONCE (only when connected).
function Get-WorkforceEmail {
    param($Context)
    if ($Context -and $Context.email -and $Context.email.ok) { return $Context.email }
    # Prefer the provider-neutral COMBINED signal (Gmail + Yahoo) so Sam's one
    # report spans every inbox. Read through the shared cache (Epic 9) so the
    # Inbox scan reuses whatever Home already fetched - no independent re-fetch.
    if (Get-Command Get-CommunicationsSignal -ErrorAction SilentlyContinue) {
        try { $c = Get-CommunicationsSignal; if ($c -and $c.ok) { return $c } } catch { }
    }
    elseif (Get-Command Get-Communications -ErrorAction SilentlyContinue) {
        try { $c = Get-Communications; if ($c -and $c.ok) { return $c } } catch { }
    }
    if ((Get-Command Get-GmailStatus -ErrorAction SilentlyContinue) -and (Get-Command Get-Email -ErrorAction SilentlyContinue)) {
        try { if ((Get-GmailStatus).state -eq 'connected') { return (Get-Email -When 'today') } } catch { }
    }
    return $null
}
function Get-WorkforceCalendar {
    param($Context)
    if ($Context -and $Context.calendar -and $Context.calendar.ok) { return $Context.calendar }
    if (Get-Command Get-CalendarSignal -ErrorAction SilentlyContinue) {
        try { $c = Get-CalendarSignal; if ($c) { return $c } } catch { }
    }
    elseif ((Get-Command Get-GCalStatus -ErrorAction SilentlyContinue) -and (Get-Command Get-Calendar -ErrorAction SilentlyContinue)) {
        try { if ((Get-GCalStatus).state -eq 'connected') { return (Get-Calendar -When 'today') } } catch { }
    }
    return $null
}
# Randy reads the normalized 'crm' signal - prefer what the Executive Context
# already carries; otherwise the shared cache (Epic 9) fetches ONCE per window.
# She never touches a CRM API or a vendor - only the normalized model.
function Get-WorkforceCRM {
    param($Context)
    if ($Context -and ($Context.PSObject.Properties.Name -contains 'crm') -and $Context.crm -and $Context.crm.ok) { return $Context.crm }
    if (Get-Command Get-CrmSignal -ErrorAction SilentlyContinue) {
        try { $c = Get-CrmSignal; if ($c) { return $c } } catch { }
    }
    elseif ((Get-Command Get-CRMStatus -ErrorAction SilentlyContinue) -and (Get-Command Get-CRM -ErrorAction SilentlyContinue)) {
        try { if ((Get-CRMStatus).state -in @('configured', 'connected', 'degraded')) { return (Get-CRM) } } catch { }
    }
    return $null
}

if (Get-Command Register-Specialist -ErrorAction SilentlyContinue) {

    # ---- Sam - Head of Communications (provider-neutral) ---------------
    # Sam (she) makes sure no important communication is missed, regardless of
    # WHERE it originated. She reads ONE combined signal across every backend
    # (Gmail + Yahoo today; Outlook/SMS/voicemail/Slack later) and never learns
    # the vendor. Each surfaced item keeps its source account + provider.
    Register-Specialist -Specialist ([pscustomobject]@{
            name         = 'Sam'
            purpose      = 'Head of Communications - ensures no important communication is missed, regardless of where it originated.'
            capabilities = @('combined inbox summary (Gmail + Yahoo)', 'who is waiting on you', 'carrier/underwriting updates')
            relevant     = { param($t) [bool]($t -match '(?i)\b(e-?mail|inbox|mail|mailbox|yahoo|message|reply|wrote|waiting|communication|overnight|what happened|catch me up|attention|status|new)\b') }
            status       = { if (Get-Command Get-CommunicationsStatus -ErrorAction SilentlyContinue) { $st = Get-CommunicationsStatus; [pscustomobject]@{ available = ($st.state -eq 'connected'); detail = $st.detail } } elseif (Get-Command Get-GmailStatus -ErrorAction SilentlyContinue) { $st = Get-GmailStatus; [pscustomobject]@{ available = ($st.state -eq 'connected'); detail = $st.detail } } else { [pscustomobject]@{ available = $false; detail = 'Communication providers not loaded.' } } }
            analyze      = {
                param($req)
                $email = Get-WorkforceEmail -Context $req.context
                if (-not $email -or -not $email.ok) { return (New-SpecialistReport -Specialist 'Sam' -Purpose 'Reviews communications.' -Input 'the inboxes' -Output 'No communication account is connected, so I could not review the inboxes.' -Confidence 0.2 -Status 'no-data' -Scope 'inbox') }
                $s = $email.summary
                $inboxN = [int]$email.accountCount
                $out = ('Reviewed {0} inbox(es): {1} received today; {2} need attention, {3} awaiting a reply, {4} invitation(s).' -f $inboxN, $s.total, $s.needsAttention, $s.waitingForReply, $s.invitations)
                $ev = @($s.attentionItems | Select-Object -First 5 | ForEach-Object { [pscustomobject]@{ source = 'email'; sourceId = [string]$_.messageId; detail = ('{0}: {1}{2}' -f $_.from, $_.subject, $(if (@($_.accounts).Count -gt 0) { ' [' + ((@($_.accounts)) -join ', ') + ']' } else { '' })) } })
                $acts = @($s.attentionItems | Where-Object { $_.category -in @('needs-reply', 'important-contact', 'urgent') } | Select-Object -First 3 | ForEach-Object { ('Reply to {0} ({1})' -f $_.from, $_.subject) })
                New-SpecialistReport -Specialist 'Sam' -Purpose 'Head of Communications - reviews every inbox and flags what needs a response.' -Input ('{0} inbox(es) across {1}' -f $inboxN, $(if ($email.providers) { (@($email.providers) -join ' + ') } else { 'email' })) -Output $out `
                    -Confidence $(if ($s.total -gt 0) { 0.85 } else { 0.7 }) -Evidence $ev -Status 'ok' -RecommendedActions $acts `
                    -Assessment $(if ($s.needsAttention -gt 0) { 'needs-attention' } else { 'clear' }) -Scope 'inbox'
            }
        })

    # ---- Ava - Calendar Manager ----------------------------------------
    # Ava reviews the schedule and protects the day. She never writes the
    # calendar - she only reads it and proposes.
    Register-Specialist -Specialist ([pscustomobject]@{
            name         = 'Ava'
            purpose      = 'Reviews today''s schedule and flags conflicts and the clearest focus block.'
            capabilities = @('schedule summary', 'conflict detection', 'free-block protection')
            relevant     = { param($t) [bool]($t -match '(?i)\b(calendar|schedule|meeting|appointment|agenda|today|conflict|free time|overnight|what happened|catch me up|status)\b') }
            status       = { $c = (Get-Command Get-GCalStatus -ErrorAction SilentlyContinue); if ($c) { $st = Get-GCalStatus; [pscustomobject]@{ available = ($st.state -eq 'connected'); detail = $st.detail } } else { [pscustomobject]@{ available = $false; detail = 'Calendar provider not loaded.' } } }
            analyze      = {
                param($req)
                $cal = Get-WorkforceCalendar -Context $req.context
                if (-not $cal -or -not $cal.ok) { return (New-SpecialistReport -Specialist 'Ava' -Purpose 'Reviews the schedule.' -Input 'today''s calendar' -Output 'Google Calendar is not connected, so I could not review the schedule.' -Confidence 0.2 -Status 'no-data' -Scope 'schedule') }
                $t = $cal.insights.today
                $out = ('{0} meeting(s) today; {1} busy minutes; {2} scheduling conflict(s).' -f $t.totalMeetings, $t.busyMinutes, @($cal.conflicts).Count)
                $ev = @()
                if ($t.firstMeeting) { $ev += [pscustomobject]@{ source = 'calendar'; sourceId = [string]$t.firstMeeting.id; detail = ('first: {0} at {1}' -f $t.firstMeeting.title, $t.firstMeeting.start.ToString('h:mm tt')) } }
                foreach ($cf in @($cal.conflicts | Select-Object -First 3)) { $ev += [pscustomobject]@{ source = 'calendar'; sourceId = $null; detail = ('conflict: {0} overlaps {1}' -f $cf.a, $cf.b) } }
                $acts = @(); if ($t.longestFreeBlock) { $acts += ('Protect {0}-{1} for focused work' -f $t.longestFreeBlock.start.ToString('h:mm tt'), $t.longestFreeBlock.end.ToString('h:mm tt')) }
                if ($t.meetingHeavy) { $acts += 'Protect the gaps for recovery - it is a meeting-heavy day' }
                New-SpecialistReport -Specialist 'Ava' -Purpose 'Reviews today''s schedule and flags conflicts and the clearest focus block.' -Input ('calendar across {0} account(s)' -f $cal.accountCount) -Output $out `
                    -Confidence 0.85 -Evidence $ev -Status 'ok' -RecommendedActions $acts `
                    -Assessment $(if ($t.meetingHeavy -or @($cal.conflicts).Count -gt 0) { 'needs-attention' } else { 'clear' }) -Scope 'schedule'
            }
        })

    # ---- Mason - Document Analyst (reads a document Jake queues) --------
    # Mason reads only a document Jake explicitly points him at - never folders.
    Register-Specialist -Specialist ([pscustomobject]@{
            name         = 'Mason'
            purpose      = 'Reads a document for meaning when one is queued.'
            capabilities = @('extract meaning', 'find action items', 'summarize')
            relevant     = { param($t) [bool]($t -match '(?i)\b(document|pdf|docx|contract|attachment|read (this|the)|this file)\b') }
            status       = { [pscustomobject]@{ available = [bool](Get-Command Invoke-DocumentIntelligence -ErrorAction SilentlyContinue); detail = 'Reads a document when a path is provided.' } }
            analyze      = {
                param($req)
                $path = if ($req.context -and ($req.context.PSObject.Properties.Name -contains 'documentPath')) { $req.context.documentPath } else { $null }
                if (-not $path -and $req.PSObject.Properties.Name -contains 'documentPath') { $path = $req.documentPath }
                if (-not $path -or -not (Get-Command Invoke-DocumentIntelligence -ErrorAction SilentlyContinue)) {
                    return (New-SpecialistReport -Specialist 'Mason' -Purpose 'Reads a document for meaning.' -Input 'no document queued' -Output 'No document is queued for review - point me at a file and I will read it (with your approval).' -Confidence 0.2 -Status 'no-data' -Scope 'document')
                }
                $di = Invoke-DocumentIntelligence -Path $path
                if (-not $di.ok) { return (New-SpecialistReport -Specialist 'Mason' -Output ("Couldn't read that document. {0}" -f $di.note) -Confidence 0.2 -Status 'no-data' -Scope 'document') }
                New-SpecialistReport -Specialist 'Mason' -Purpose 'Reads a document for meaning.' -Input ([string]$di.source) -Output ([string]$di.executiveSummary) `
                    -Confidence 0.75 -Evidence @([pscustomobject]@{ source = 'document'; sourceId = [string]$di.source; detail = ('type {0}' -f $di.type) }) -Status 'ok' -Scope 'document'
            }
        })

    # ---- Emma - Priority Analyst (wraps the Executive Priority Engine, D18) ----
    Register-Specialist -Specialist ([pscustomobject]@{
            name         = 'Emma'
            purpose      = 'Ranks what to act on now versus later, without losing anything.'
            capabilities = @('rank items', 'act-now vs keep-visible', 'no-loss check')
            relevant     = { param($t) [bool]($t -match '(?i)\b(priorit|focus|most important|what should i|attention|act now|to-?do|overnight|what happened|status)\b') }
            status       = { [pscustomobject]@{ available = [bool](Get-Command Get-ExecutivePriorities -ErrorAction SilentlyContinue); detail = 'Active when the Executive Priority Engine is in the build.' } }
            analyze      = {
                param($req)
                if (-not (Get-Command Get-ExecutivePriorities -ErrorAction SilentlyContinue)) {
                    return (New-SpecialistReport -Specialist 'Emma' -Purpose 'Ranks priorities.' -Input 'n/a' -Output 'The priority engine is not part of this build yet - I cannot rank right now.' -Confidence 0.2 -Status 'unavailable' -Scope 'attention')
                }
                $p = Get-ExecutivePriorities -Context $req.context -Now $req.now
                $out = ('{0} to act on now, {1} for today, {2} kept visible.' -f $p.counts.actNow, $p.counts.doToday, $p.counts.keepVisible)
                $ev = @(@($p.actNow) + @($p.doToday) | Select-Object -First 5 | ForEach-Object { $sr = @($_.sources | Select-Object -First 1); [pscustomobject]@{ source = $(if ($sr) { $sr[0].source } else { 'priority' }); sourceId = $(if ($sr) { $sr[0].sourceId } else { $null }); detail = $_.title } })
                $acts = @($p.actNow | Select-Object -First 3 | ForEach-Object { $_.title })
                New-SpecialistReport -Specialist 'Emma' -Purpose 'Ranks what to act on now versus later.' -Input 'the full item set' -Output $out `
                    -Confidence 0.8 -Evidence $ev -Status 'ok' -RecommendedActions $acts -Assessment $(if ($p.counts.actNow -gt 0) { 'needs-attention' } else { 'clear' }) -Scope 'attention'
            }
        })

    # ---- Riley - Timeline Analyst (wraps the Executive Timeline, D19) ---
    Register-Specialist -Specialist ([pscustomobject]@{
            name         = 'Riley'
            purpose      = 'Identifies what is new, aging, overdue, waiting, or expiring over time.'
            capabilities = @('what changed', 'aging/overdue', 'waiting mail', 'deadlines')
            relevant     = { param($t) [bool]($t -match '(?i)\b(what changed|new|aging|overdue|waiting|since|overnight|what happened|catch me up|timeline|expir|deadline|status)\b') }
            status       = { [pscustomobject]@{ available = [bool](Get-Command Get-ExecutiveTimeline -ErrorAction SilentlyContinue); detail = 'Active when the Executive Timeline is in the build.' } }
            analyze      = {
                param($req)
                if (-not (Get-Command Get-ExecutiveTimeline -ErrorAction SilentlyContinue)) {
                    return (New-SpecialistReport -Specialist 'Riley' -Purpose 'Notices change over time.' -Input 'n/a' -Output 'The timeline engine is not part of this build yet - I cannot track changes over time right now.' -Confidence 0.2 -Status 'unavailable' -Scope 'time')
                }
                $we = $null
                if ((Get-Command Get-EmailWaiting -ErrorAction SilentlyContinue) -and (Get-Command Get-GmailStatus -ErrorAction SilentlyContinue)) { try { if ((Get-GmailStatus).state -eq 'connected') { $we = Get-EmailWaiting -Now $req.now } } catch { } }
                $tl = Get-ExecutiveTimeline -Context $req.context -Now $req.now -WaitingEmails $we
                if (-not $tl.hasAny) { return (New-SpecialistReport -Specialist 'Riley' -Purpose 'Notices change over time.' -Input 'timestamps' -Output 'Nothing notable has changed over time.' -Confidence 0.7 -Status 'ok' -Assessment 'clear' -Scope 'time') }
                $out = (@($tl.notes | ForEach-Object { $_.text }) -join ' ')
                $ev = @($tl.overdue + $tl.aging | Select-Object -First 4 | ForEach-Object { [pscustomobject]@{ source = $_.source; sourceId = $_.sourceId; detail = ('{0} ({1}d)' -f $_.title, $_.ageDays) } })
                New-SpecialistReport -Specialist 'Riley' -Purpose 'Identifies what is new, aging, overdue, waiting, or expiring.' -Input 'existing timestamps' -Output $out `
                    -Confidence 0.8 -Evidence $ev -Status 'ok' -RecommendedActions @() -Assessment $(if (@($tl.overdue).Count -gt 0 -or $tl.counts.waiting -gt 0) { 'needs-attention' } else { 'clear' }) -Scope 'time'
            }
        })

    # ---- Randy - CRM Manager (reads the normalized 'crm' signal) --------
    # Randy understands CRM as a discipline, not GoHighLevel. She reads ONLY
    # the normalized crm signal (leads, pipeline, follow-ups, underwriting),
    # never a vendor API, never acts, and reports to Tony only. Activates when
    # the CRM provider is present + connected; reports honestly otherwise.
    Register-Specialist -Specialist ([pscustomobject]@{
            name         = 'Randy'
            purpose      = 'Reviews the book of business - leads, pipeline, follow-ups, and what needs attention.'
            capabilities = @('pipeline health', 'aging leads', 'stalled/underwriting deals', 'overdue follow-ups', 'business health')
            relevant     = { param($t) [bool]($t -match '(?i)\b(crm|pipeline|lead|leads|prospect|opportunit|renewal|underwriting|follow.?up|policy|policies|book of business|revenue|deal|deals|client(s)?|what happened|catch me up|status|attention|where do (things|we) stand)\b') }
            status       = { $c = (Get-Command Get-CRMStatus -ErrorAction SilentlyContinue); if ($c) { $st = Get-CRMStatus; [pscustomobject]@{ available = ($st.state -in @('configured', 'connected', 'degraded')); detail = $st.detail } } else { [pscustomobject]@{ available = $false; detail = 'CRM provider not loaded.' } } }
            analyze      = {
                param($req)
                if (-not (Get-Command Get-CRM -ErrorAction SilentlyContinue)) {
                    return (New-SpecialistReport -Specialist 'Randy' -Purpose 'Reviews the book of business.' -Input 'n/a' -Output 'The CRM is not part of this build yet - I cannot review the book of business right now.' -Confidence 0.2 -Status 'unavailable' -Scope 'crm')
                }
                $crm = Get-WorkforceCRM -Context $req.context
                if (-not $crm -or -not $crm.ok) {
                    $why = if ($crm -and $crm.status) { [string]$crm.status.detail } else { 'GoHighLevel is not connected.' }
                    return (New-SpecialistReport -Specialist 'Randy' -Purpose 'Reviews the book of business.' -Input 'the CRM' -Output ('I could not review the CRM. {0}' -f $why) -Confidence 0.2 -Status 'no-data' -Scope 'crm')
                }
                $sum = $crm.summary
                if (-not $sum) { return (New-SpecialistReport -Specialist 'Randy' -Purpose 'Reviews the book of business.' -Input 'the CRM' -Output 'The CRM connected but returned nothing to review.' -Confidence 0.4 -Status 'no-data' -Scope 'crm') }
                $bh = $sum.businessHealth
                $out = [string]$sum.headline
                if ($sum.note) { $out = ('{0} {1}' -f $out, $sum.note) }
                $ev = @($sum.attentionItems | Select-Object -First 5 | ForEach-Object { [pscustomobject]@{ source = 'crm'; sourceId = [string]$_.sourceId; detail = ('{0}: {1}' -f $_.title, $_.detail) } })
                $acts = @()
                foreach ($a in @($sum.attentionItems | Select-Object -First 3)) {
                    if ($a.kind -eq 'overdue-follow-up') { $acts += ('Handle the overdue follow-up: {0}' -f $a.title) }
                    elseif ($a.kind -eq 'stalled-underwriting') { $acts += ('Unblock the underwriting deal: {0}' -f $a.title) }
                    elseif ($a.kind -eq 'stalled-opportunity') { $acts += ('Revive the stalled opportunity: {0}' -f $a.title) }
                    elseif ($a.kind -eq 'aging-lead') { $acts += ('Reach out to the aging lead: {0}' -f $a.title) }
                }
                # Confidence: high with real pipeline data; LOW when the pipeline is
                # empty (Randy has little to assess and says so); mid when sampled.
                $conf = if ($sum.pipelineEmpty) { 0.5 } elseif ($crm.opportunities.capped -or $crm.contacts.capped) { 0.7 } else { 0.8 }
                $assessment = if ($sum.hasAttention) { 'needs-attention' } elseif ($sum.pipelineEmpty) { 'informational' } else { 'clear' }
                $contactStr = if ($bh.contactsCapped) { ('{0}+ contact(s), recent sample' -f $bh.contactCount) } else { ('{0} contact(s)' -f $bh.contactCount) }
                New-SpecialistReport -Specialist 'Randy' -Purpose 'Reviews the book of business - leads, pipeline, follow-ups, and what needs attention.' `
                    -Input ('CRM across {0} location(s): {1} open opp(s), {2}' -f $crm.locationCount, $bh.openOpportunities, $contactStr) -Output $out `
                    -Confidence $conf -Evidence $ev -Status 'ok' -RecommendedActions $acts -Assessment $assessment -Scope 'crm'
            }
        })
}
