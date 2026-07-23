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

Complete-TestFile 'calendar-connector'
