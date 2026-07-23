# =====================================================================
# calendar-connector.tests.ps1 - Google Calendar WRITE connector (Epic 17)
# ---------------------------------------------------------------------
# Permanent, MOCKED tests: the real account/token is NEVER used. Every Google
# Calendar HTTP call is replaced by an in-memory provider store, so the full
# create/idempotency/verification/recovery contract runs offline and
# deterministically. The connector plugs into the ONE execution path
# (Invoke-ProposalExecution) - never a parallel one.
#
# Stage 2 scope: create-event path + provider-safe idempotency + engine-gated
# read-back verification + crash/timeout recovery for creates. Update/cancel and
# approval-instance binding arrive in Stage 3; the full hostile/mutation matrix
# in Stage 5.
# =====================================================================

. (Join-Path $PSScriptRoot '_harness.ps1')
. (Join-Path $script:CoreDir 'connectors\google-calendar.ps1')
Assert-Sandboxed
[void](Register-GCalConnector)

# ---- in-memory provider (replaces the four Google API seams) -----------------
$script:Prov = @{ events = @{}; insertCalls = 0; getCalls = 0; patchCalls = 0; deleteCalls = 0
    token = [pscustomobject]@{ ok = $true; token = 'mock-token'; account = 'jake@example.com'; state = 'connected'; detail = 'ok' }
    dropWrites = $false; misdirect = $false }
function New-MockHttpError { param([int]$Status)
    $ex = New-Object System.Exception ("mock http {0}" -f $Status)
    $resp = New-Object psobject; $resp | Add-Member NoteProperty StatusCode $Status
    $ex | Add-Member NoteProperty Response $resp -Force
    return $ex
}
function Reset-Prov { $script:Prov.events = @{}; $script:Prov.insertCalls = 0; $script:Prov.getCalls = 0; $script:Prov.patchCalls = 0; $script:Prov.deleteCalls = 0; $script:Prov.dropWrites = $false; $script:Prov.misdirect = $false; $script:Prov.token = [pscustomobject]@{ ok = $true; token = 'mock-token'; account = 'jake@example.com'; state = 'connected'; detail = 'ok' } }
# seam overrides (defined AFTER the connector dot-source, so they win)
function Get-GCalWriteAccessToken { param([string]$AccountId = '') return $script:Prov.token }
function Invoke-GCalInsert { param($Token, $CalendarId, $Body)
    $script:Prov.insertCalls++
    $storeId = if ($script:Prov.misdirect) { ([string]$Body.id + 'X') } else { [string]$Body.id }
    $key = ("{0}/{1}" -f $CalendarId, $storeId)
    if ($script:Prov.events.ContainsKey(("{0}/{1}" -f $CalendarId, [string]$Body.id))) { throw (New-MockHttpError -Status 409) }
    $ev = [pscustomobject]@{ id = $storeId; summary = [string]$Body.summary; start = $Body.start; end = $Body.end; status = 'confirmed'; etag = '"v1"' }
    if (-not $script:Prov.dropWrites) { $script:Prov.events[$key] = $ev }
    return $ev
}
function Invoke-GCalGet { param($Token, $CalendarId, $EventId)
    $script:Prov.getCalls++
    $key = ("{0}/{1}" -f $CalendarId, $EventId)
    if (-not $script:Prov.events.ContainsKey($key)) { throw (New-MockHttpError -Status 404) }
    return $script:Prov.events[$key]
}
function Invoke-GCalPatch { param($Token, $CalendarId, $EventId, $Body) $script:Prov.patchCalls++; $key = ("{0}/{1}" -f $CalendarId, $EventId); if (-not $script:Prov.events.ContainsKey($key)) { throw (New-MockHttpError -Status 404) }; $ev = $script:Prov.events[$key]; foreach ($n in $Body.PSObject.Properties.Name) { $ev | Add-Member -NotePropertyName $n -NotePropertyValue $Body.$n -Force }; return $ev }
function Invoke-GCalDelete { param($Token, $CalendarId, $EventId) $script:Prov.deleteCalls++; $key = ("{0}/{1}" -f $CalendarId, $EventId); if (-not $script:Prov.events.ContainsKey($key)) { throw (New-MockHttpError -Status 404) }; $script:Prov.events.Remove($key) | Out-Null; return $null }

# ---- calendar proposal + approval fixtures -----------------------------------
$script:CalSeq = 0
function New-CalProposal {
    param([string]$Type = 'calendar.create-event', [hashtable]$Payload, [string]$Uid = '', [string]$Title = 'Team sync')
    $script:CalSeq++
    $uidVal = if ($Uid) { $Uid } else { ('cal-uid-{0}' -f $script:CalSeq) }
    return [pscustomobject]@{
        id = ('INBOX-{0:000}' -f $script:CalSeq); uid = $uidVal; type = $Type; title = $Title
        description = ''; source = 'test'; sourceId = ''; proposedDestination = ''; created = '2026-08-01 09:00:00'
        payload = ([pscustomobject]$Payload)
    }
}
function New-CreatePayload { param([string]$Cal = 'primary', [string]$Title = 'Team sync', [string]$Start = '2026-08-01T09:00:00-07:00', [string]$End = '2026-08-01T10:00:00-07:00', [string]$Tz = 'America/Los_Angeles')
    return @{ calendarId = $Cal; title = $Title; start = $Start; end = $End; timezone = $Tz }
}
function Invoke-CalExec { param($Proposal) return (Invoke-ProposalExecution -Proposal $Proposal -Approval (New-TestApproval -Proposal $Proposal)) }

# =====================================================================
Write-TestSection 'create: valid create -> succeeded, verified by exact provider id'
# =====================================================================
Reset-Prov
$p1 = New-CalProposal -Payload (New-CreatePayload -Title 'Prospecting block')
$expectId = Get-GCalClientEventId -Seed (Get-ExecutionIdempotencyKey -Proposal $p1)
$r1 = Invoke-CalExec -Proposal $p1
Assert-True ($r1.ok) 'valid calendar create succeeds'
Assert-True ($r1.newId -eq $expectId) 'result carries the DETERMINISTIC provider event id (client-specified)'
Assert-True ((Get-ExecutionById -Id $r1.executionId).state -eq 'succeeded') 'execution reaches succeeded'
Assert-True ($script:Prov.events.ContainsKey(('primary/{0}' -f $expectId))) 'the event exists in the provider under the deterministic id'
Assert-True ($script:Prov.getCalls -ge 1) 'verification performed an independent read-back (events.get)'
$hist = (Get-ExecutionById -Id $r1.executionId)
Assert-True ([string]$hist.result.destination -eq (Get-GCalSafeCalendarRef -CalendarId 'primary')) 'audit destination is a SAFE calendar ref (no raw title/calendar)'

# =====================================================================
Write-TestSection 'idempotency: duplicate approval + repeated direct invocation -> ONE event'
# =====================================================================
Reset-Prov
$p2 = New-CalProposal -Payload (New-CreatePayload -Title 'Renewal call')
$a2 = Invoke-CalExec -Proposal $p2
$b2 = Invoke-CalExec -Proposal $p2   # repeated approval/direct call
Assert-True ($a2.ok -and $b2.ok) 'both invocations report ok'
Assert-True ($b2.deduped -and $b2.executionId -eq $a2.executionId) 'the second invocation dedups to the one execution'
Assert-True ($script:Prov.insertCalls -eq 1) 'only ONE provider insert happened (no duplicate event)'
Assert-True (@($script:Prov.events.Keys).Count -eq 1) 'exactly one event exists'

# =====================================================================
Write-TestSection 'idempotency: distinct proposals, identical content, reused inbox id -> TWO events'
# =====================================================================
Reset-Prov
$sharedPayload = New-CreatePayload -Title 'Standup'
$d1 = New-CalProposal -Payload $sharedPayload -Uid 'uid-AAA' -Title 'Standup'
$d2 = New-CalProposal -Payload $sharedPayload -Uid 'uid-BBB' -Title 'Standup'
$d2.id = $d1.id   # REUSE the inbox id (ids are recycled) - only uid differs
$e1 = Invoke-CalExec -Proposal $d1
$e2 = Invoke-CalExec -Proposal $d2
Assert-True ($e1.newId -ne $e2.newId) 'different uid -> different deterministic event id (no collision)'
Assert-True ((-not $e2.deduped) -and $e1.executionId -ne $e2.executionId) 'two distinct executions (not deduped)'
Assert-True (@($script:Prov.events.Keys).Count -eq 2) 'two distinct events created'

# =====================================================================
Write-TestSection 'crash-after-insert (response lost): recovery verifies by deterministic id, no duplicate'
# =====================================================================
Reset-Prov
$p3 = New-CalProposal -Payload (New-CreatePayload -Title 'Board prep')
# provider already created the event under the deterministic id (the insert landed)
$cid = Get-GCalClientEventId -Seed (Get-ExecutionIdempotencyKey -Proposal $p3)
$script:Prov.events[('primary/{0}' -f $cid)] = [pscustomobject]@{ id = $cid; summary = 'Board prep'; start = ([pscustomobject]@{ dateTime = '2026-08-01T09:00:00-07:00'; timeZone = 'America/Los_Angeles' }); end = ([pscustomobject]@{ dateTime = '2026-08-01T10:00:00-07:00'; timeZone = 'America/Los_Angeles' }); status = 'confirmed' }
# but the execution crashed mid-flight: a non-terminal record with the intent, no result
$iv = New-ExecutionIntent -Proposal $p3
$log = Get-ExecutionLog
$log.executions = @($log.executions) + [pscustomobject]@{ id = 'EXE-CAL-B'; proposalId = $p3.id; type = $p3.type; title = $p3.title; description = ''; source = 't'; sourceId = ''; proposedDestination = ''; state = 'executing'; createdAt = 't'; updatedAt = 't'; attempts = 1; idempotencyKey = (Get-ExecutionIdempotencyKey -Proposal $p3); approval = $null; intent = $iv.intent; result = $null; history = @([pscustomobject]@{ state = 'executing'; at = 't'; detail = 'crash' }) }
Save-ExecutionLog $log
$script:Prov.insertCalls = 0
$null = Restore-ActionEngine
Assert-True ((Get-ExecutionById -Id 'EXE-CAL-B').state -eq 'succeeded') 'window B: recovery finds the exact event and succeeds'
Assert-True ($script:Prov.insertCalls -eq 0) 'window B: recovery never re-sent the create (no duplicate)'

# =====================================================================
Write-TestSection 'crash-before-send (intent only, no event): recovery -> failed/retriable, no blind re-send'
# =====================================================================
Reset-Prov
$p4 = New-CalProposal -Payload (New-CreatePayload -Title 'Never sent')
$iv4 = New-ExecutionIntent -Proposal $p4
$log = Get-ExecutionLog
$log.executions = @($log.executions) + [pscustomobject]@{ id = 'EXE-CAL-A'; proposalId = $p4.id; type = $p4.type; title = $p4.title; description = ''; source = 't'; sourceId = ''; proposedDestination = ''; state = 'executing'; createdAt = 't'; updatedAt = 't'; attempts = 1; idempotencyKey = (Get-ExecutionIdempotencyKey -Proposal $p4); approval = $null; intent = $iv4.intent; result = $null; history = @([pscustomobject]@{ state = 'executing'; at = 't'; detail = 'crash' }) }
Save-ExecutionLog $log
$script:Prov.insertCalls = 0
$null = Restore-ActionEngine
Assert-True ((Get-ExecutionById -Id 'EXE-CAL-A').state -eq 'failed') 'window A: absent event -> recovered failed (retriable)'
Assert-True ($script:Prov.insertCalls -eq 0) 'window A: recovery never sent a create'

# =====================================================================
Write-TestSection 'verification is real: HTTP success but no provider state -> FAILED'
# =====================================================================
Reset-Prov
$script:Prov.dropWrites = $true   # insert "succeeds" (returns an event) but nothing is stored
$p5 = New-CalProposal -Payload (New-CreatePayload -Title 'Phantom')
$r5 = Invoke-CalExec -Proposal $p5
Assert-True (-not $r5.ok) 'a create that cannot be read back is NOT marked succeeded'
Assert-True ((Get-ExecutionById -Id $r5.executionId).state -eq 'failed') 'execution is failed (verification gate held)'

# =====================================================================
Write-TestSection 'verification anchored to the exact id: provider stores a DIFFERENT id -> FAILED'
# =====================================================================
Reset-Prov
$script:Prov.misdirect = $true   # provider stores under id+X, not the requested deterministic id
$p6 = New-CalProposal -Payload (New-CreatePayload -Title 'Wrong id')
$r6 = Invoke-CalExec -Proposal $p6
Assert-True (-not $r6.ok) 'an event under the wrong id does not satisfy verification'
Assert-True ((Get-ExecutionById -Id $r6.executionId).state -eq 'failed') 'verification requires the EXACT deterministic id'

# =====================================================================
Write-TestSection 'fail closed: write not connected -> no insert, failed'
# =====================================================================
Reset-Prov
$script:Prov.token = [pscustomobject]@{ ok = $false; token = $null; account = $null; state = 'not-connected'; detail = 'not connected' }
$p7 = New-CalProposal -Payload (New-CreatePayload -Title 'No conn')
$r7 = Invoke-CalExec -Proposal $p7
Assert-True (-not $r7.ok) 'a disconnected write connection fails the execution'
Assert-True ($script:Prov.insertCalls -eq 0) 'no insert attempted when not connected'

# =====================================================================
Write-TestSection 'validation before side effect: malformed payloads write nothing'
# =====================================================================
Reset-Prov
$bad1 = New-CalProposal -Payload (New-CreatePayload -Start '2026-08-01T09:00:00' )   # bare local (DST-ambiguous)
$rb1 = Invoke-CalExec -Proposal $bad1
Assert-True (-not $rb1.ok) 'bare local start (DST-ambiguous) is rejected'
$bad2 = New-CalProposal -Payload (New-CreatePayload -Tz 'Nowhere/Void')
$rb2 = Invoke-CalExec -Proposal $bad2
Assert-True (-not $rb2.ok) 'unrecognized timezone is rejected (never guessed)'
$bad3 = New-CalProposal -Payload (New-CreatePayload -Start '2026-08-01T10:00:00-07:00' -End '2026-08-01T09:00:00-07:00')
$rb3 = Invoke-CalExec -Proposal $bad3
Assert-True (-not $rb3.ok) 'end<=start is rejected'
Assert-True ($script:Prov.insertCalls -eq 0) 'NOT ONE malformed payload reached the provider'

# =====================================================================
Write-TestSection 'update: valid update -> succeeded, verified by exact intended fields'
# =====================================================================
Reset-Prov
$uc = New-CalProposal -Payload (New-CreatePayload -Title 'Orig title')
$urc = Invoke-CalExec -Proposal $uc
$eid = $urc.newId
$pu = New-CalProposal -Type 'calendar.update-event' -Payload @{ calendarId = 'primary'; eventId = $eid; changes = ([pscustomobject]@{ title = 'Renamed title' }) }
$ru = Invoke-CalExec -Proposal $pu
Assert-True ($ru.ok) 'valid update succeeds'
Assert-True ([string]$script:Prov.events[('primary/{0}' -f $eid)].summary -eq 'Renamed title') 'the event now carries the intended new title'
Assert-True ($script:Prov.patchCalls -eq 1) 'exactly one patch was sent'

# =====================================================================
Write-TestSection 'update: stale expectedProviderVersion -> rejected, not overwritten'
# =====================================================================
Reset-Prov
$sc = New-CalProposal -Payload (New-CreatePayload -Title 'Keep me')
$src = Invoke-CalExec -Proposal $sc
$eid2 = $src.newId
$before = [string]$script:Prov.events[('primary/{0}' -f $eid2)].summary
$ps = New-CalProposal -Type 'calendar.update-event' -Payload @{ calendarId = 'primary'; eventId = $eid2; expectedProviderVersion = '"STALE-OLD"'; changes = ([pscustomobject]@{ title = 'Should not apply' }) }
$rs = Invoke-CalExec -Proposal $ps
Assert-True (-not $rs.ok) 'a stale-version update is refused'
Assert-True ($script:Prov.patchCalls -eq 0) 'no patch was sent for a stale update'
Assert-True ([string]$script:Prov.events[('primary/{0}' -f $eid2)].summary -eq $before) 'the newer external state was NOT overwritten'

# =====================================================================
Write-TestSection 'update: missing event and no-op update are refused'
# =====================================================================
Reset-Prov
$pm = New-CalProposal -Type 'calendar.update-event' -Payload @{ calendarId = 'primary'; eventId = 'giokdoesnotexist99'; changes = ([pscustomobject]@{ title = 'X' }) }
$rm = Invoke-CalExec -Proposal $pm
Assert-True (-not $rm.ok) 'update of a missing event fails'
$nc = New-CalProposal -Payload (New-CreatePayload -Title 'Same')
$nrc = Invoke-CalExec -Proposal $nc
$pn = New-CalProposal -Type 'calendar.update-event' -Payload @{ calendarId = 'primary'; eventId = $nrc.newId; changes = ([pscustomobject]@{ title = 'Same' }) }
$rn = Invoke-CalExec -Proposal $pn
Assert-True (-not $rn.ok) 'a no-op update (nothing changes) is refused'

# =====================================================================
Write-TestSection 'update window C: response lost after patch -> recovery verifies, succeeds'
# =====================================================================
Reset-Prov
$wc = New-CalProposal -Payload (New-CreatePayload -Title 'Before')
$wrc = Invoke-CalExec -Proposal $wc
$eidC = $wrc.newId
$puC = New-CalProposal -Type 'calendar.update-event' -Payload @{ calendarId = 'primary'; eventId = $eidC; changes = ([pscustomobject]@{ title = 'After' }) }
$ivC = New-ExecutionIntent -Proposal $puC
# the patch LANDED (event already renamed) but the response was lost mid-flight
$script:Prov.events[('primary/{0}' -f $eidC)].summary = 'After'
$log = Get-ExecutionLog
$log.executions = @($log.executions) + [pscustomobject]@{ id = 'EXE-CAL-C'; proposalId = $puC.id; type = $puC.type; title = $puC.title; description = ''; source = 't'; sourceId = ''; proposedDestination = ''; state = 'executing'; createdAt = 't'; updatedAt = 't'; attempts = 1; idempotencyKey = (Get-ExecutionIdempotencyKey -Proposal $puC); approval = $null; intent = $ivC.intent; result = $null; history = @([pscustomobject]@{ state = 'executing'; at = 't'; detail = 'crash' }) }
Save-ExecutionLog $log
$script:Prov.patchCalls = 0
$null = Restore-ActionEngine
Assert-True ((Get-ExecutionById -Id 'EXE-CAL-C').state -eq 'succeeded') 'window C: recovery sees the intended change and succeeds'
Assert-True ($script:Prov.patchCalls -eq 0) 'window C: recovery never re-sent the patch'

# =====================================================================
Write-TestSection 'cancel: valid cancel -> succeeded, event gone; already-gone is idempotent'
# =====================================================================
Reset-Prov
$cc = New-CalProposal -Payload (New-CreatePayload -Title 'Cancel me')
$crc = Invoke-CalExec -Proposal $cc
$eidX = $crc.newId
$pcancel = New-CalProposal -Type 'calendar.cancel-event' -Payload @{ calendarId = 'primary'; eventId = $eidX }
$rcancel = Invoke-CalExec -Proposal $pcancel
Assert-True ($rcancel.ok) 'valid cancel succeeds'
Assert-True (-not $script:Prov.events.ContainsKey(('primary/{0}' -f $eidX))) 'the event is gone from the provider'
# a fresh proposal cancelling an already-absent event is idempotent success
$pcancel2 = New-CalProposal -Type 'calendar.cancel-event' -Payload @{ calendarId = 'primary'; eventId = $eidX }
$rcancel2 = Invoke-CalExec -Proposal $pcancel2
Assert-True ($rcancel2.ok) 'cancelling an already-gone event is idempotent success'

# =====================================================================
Write-TestSection 'cancel window D: response lost after delete -> recovery verifies cancelled/gone'
# =====================================================================
Reset-Prov
$wd = New-CalProposal -Payload (New-CreatePayload -Title 'Doomed')
$wdrc = Invoke-CalExec -Proposal $wd
$eidD = $wdrc.newId
$pcD = New-CalProposal -Type 'calendar.cancel-event' -Payload @{ calendarId = 'primary'; eventId = $eidD }
$ivD = New-ExecutionIntent -Proposal $pcD
# the delete LANDED (event gone) but the response was lost
$script:Prov.events.Remove(('primary/{0}' -f $eidD)) | Out-Null
$log = Get-ExecutionLog
$log.executions = @($log.executions) + [pscustomobject]@{ id = 'EXE-CAL-D'; proposalId = $pcD.id; type = $pcD.type; title = $pcD.title; description = ''; source = 't'; sourceId = ''; proposedDestination = ''; state = 'executing'; createdAt = 't'; updatedAt = 't'; attempts = 1; idempotencyKey = (Get-ExecutionIdempotencyKey -Proposal $pcD); approval = $null; intent = $ivD.intent; result = $null; history = @([pscustomobject]@{ state = 'executing'; at = 't'; detail = 'crash' }) }
Save-ExecutionLog $log
$script:Prov.deleteCalls = 0
$null = Restore-ActionEngine
Assert-True ((Get-ExecutionById -Id 'EXE-CAL-D').state -eq 'succeeded') 'window D: recovery confirms the cancelled/gone state and succeeds'
Assert-True ($script:Prov.deleteCalls -eq 0) 'window D: recovery never re-sent the delete'

# =====================================================================
Write-TestSection 'approval-instance binding (NB-1): a reused approval cannot execute another instance'
# =====================================================================
Reset-Prov
$binPayload = New-CreatePayload -Title 'Identical'
$b1 = New-CalProposal -Payload $binPayload -Uid 'uid-ONE' -Title 'Identical'
$b2 = New-CalProposal -Payload $binPayload -Uid 'uid-TWO' -Title 'Identical'
$b2.id = $b1.id   # reused inbox id; identical content -> identical fingerprint
Assert-True ((Get-ProposalFingerprint -Proposal $b1) -eq (Get-ProposalFingerprint -Proposal $b2)) 'the two instances have identical content fingerprints'
$ap1 = New-TestApproval -Proposal $b1
$reuse = Invoke-ProposalExecution -Proposal $b2 -Approval $ap1   # b1's approval, b2's proposal
Assert-True (-not $reuse.ok) 'a reused approval with a different uid is REFUSED (instance mismatch)'
Assert-True ($script:Prov.insertCalls -eq 0) 'the reused-approval attempt wrote nothing'
# a connector action REQUIRES an instance-bound approval (bare-content approval refused)
$bareAp = [pscustomobject]@{ approvedBy = 'x'; approvedAt = '2026-08-01 09:00:00'; source = 'test'; fingerprint = (Get-ProposalFingerprint -Proposal $b1) }
$bare = Invoke-ProposalExecution -Proposal $b1 -Approval $bareAp
Assert-True (-not $bare.ok) 'a calendar action with a non-instance-bound approval is refused'
# the correctly-bound approval works
$good = Invoke-ProposalExecution -Proposal $b1 -Approval (New-TestApproval -Proposal $b1)
Assert-True ($good.ok) 'the correctly instance-bound approval executes'

# =====================================================================
Write-TestSection 'approval binding: editing the payload after approval invalidates it'
# =====================================================================
Reset-Prov
$ed = New-CalProposal -Payload (New-CreatePayload -Title 'Original') -Uid 'uid-EDIT'
$apEd = New-TestApproval -Proposal $ed
$ed.payload.title = 'Edited after approval'   # content change -> fingerprint change
$redit = Invoke-ProposalExecution -Proposal $ed -Approval $apEd
Assert-True (-not $redit.ok) 'a payload edit after approval invalidates the approval (fingerprint)'
Assert-True ($script:Prov.insertCalls -eq 0) 'the edited-after-approval attempt wrote nothing'

# =====================================================================
Write-TestSection 'inbox integration: payload preserved; Approve-InboxItem drives the connector'
# =====================================================================
Reset-Prov
$prop = Add-InboxProposal -DiscoveredBy 'Tony' -Type 'calendar.create-event' -Title 'Prospecting block' -Payload ([pscustomobject]@{ calendarId = 'primary'; title = 'Prospecting block'; start = '2026-08-03T07:30:00-07:00'; end = '2026-08-03T09:00:00-07:00'; timezone = 'America/Los_Angeles' })
Assert-True ($null -ne $prop) 'a calendar proposal with a payload is accepted'
$reloaded = Get-InboxItemById -Id $prop.id
Assert-True ($null -ne $reloaded.payload -and [string]$reloaded.payload.calendarId -eq 'primary') 'the structured payload survives inbox normalization/round-trip'
$ar = Approve-InboxItem -Id $prop.id
Assert-True ($ar.ok) 'Approve-InboxItem executes the calendar action through the engine+connector'
$expIdInbox = Get-GCalClientEventId -Seed (Get-ExecutionIdempotencyKey -Proposal $reloaded)
Assert-True ($script:Prov.events.ContainsKey(('primary/{0}' -f $expIdInbox))) 'the event was created by the approved inbox proposal'
Assert-True ($null -eq (Get-InboxItemById -Id $prop.id)) 'the proposal left the inbox on verified success (no copy)'

# a connector proposal with NO payload is refused at the inbox
$noPay = Add-InboxProposal -DiscoveredBy 'Tony' -Type 'calendar.create-event' -Title 'No payload'
Assert-True ($null -eq $noPay) 'a calendar proposal without a payload is refused'

# =====================================================================
Write-TestSection 'approval summary: safe, complete rows for the Executive Inbox card'
# =====================================================================
$sp = New-CalProposal -Payload (New-CreatePayload -Title 'Renewal call' -Start '2026-08-03T10:00:00-07:00' -End '2026-08-03T11:00:00-07:00')
$sum = Get-GCalApprovalSummary -Proposal $sp
$labels = @($sum | ForEach-Object { [string]$_.label })
Assert-True ($labels -contains 'Action' -and $labels -contains 'Calendar' -and $labels -contains 'Title' -and $labels -contains 'When' -and $labels -contains 'Time zone' -and $labels -contains 'Notifies') 'create summary has action/calendar/title/when/timezone/notifies'
$notify = @($sum | Where-Object { $_.label -eq 'Notifies' })[0].value
Assert-True ($notify -match 'No one') 'the summary states no one is notified in V1'
$titleRow = @($sum | Where-Object { $_.label -eq 'Title' })[0].value
Assert-True ($titleRow -eq 'Renewal call') 'the summary shows the real event title for the approver'
# update summary lists the change
$up = New-CalProposal -Type 'calendar.update-event' -Payload @{ calendarId = 'primary'; eventId = 'giokabc12345'; changes = ([pscustomobject]@{ title = 'Moved call' }) }
$usum = Get-GCalApprovalSummary -Proposal $up
$changes = @($usum | Where-Object { $_.label -eq 'Changes' })[0].value
Assert-True ($changes -match 'Moved call') 'the update summary describes the change'

# =====================================================================
Write-TestSection 'settings model: truthful state, no secrets'
# =====================================================================
$m = Get-GCalWriteSettingsModel
Assert-True ([string]$m.scope -eq 'https://www.googleapis.com/auth/calendar.events') 'settings model reports the least-privilege write scope'
Assert-True (@('connected', 'not-connected', 'not-configured', 'needs-attention') -contains [string]$m.state) 'settings state is one of the known truthful states'
Assert-True (($m | ConvertTo-Json -Depth 6) -notmatch 'token|secret|Bearer') 'settings model contains no token/secret material'

Complete-TestFile 'calendar-connector'
