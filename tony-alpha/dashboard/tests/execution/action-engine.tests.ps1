# =====================================================================
# action-engine.tests.ps1 - the permanent Executive Action Engine suite (Epic 15)
# ---------------------------------------------------------------------
# The engine is the SOLE execution authority: every execution originates from an
# APPROVED Inbox proposal, walks pending->validating->executing->verifying->
# succeeded/failed, and never claims success without VERIFYING the owner store
# changed. Every store is sandboxed; no real data is touched.
# =====================================================================

. (Join-Path $PSScriptRoot '_harness.ps1')
Assert-Sandboxed

# =====================================================================
Write-TestSection 'the state machine: approved proposal -> verified success'
# =====================================================================
$p = New-TestProposal -Type 'task' -Title 'Call five leads' -SourceId 'G-001'
$before = @((Get-ActionItemsData).items).Count
$r = Approve-InboxItem -Id $p.id
Assert-True ($r.ok -and $r.newId -and $r.executionId) 'approve returns ok + owner newId + executionId'
Assert-True (@((Get-ActionItemsData).items | Where-Object { $_.id -eq $r.newId }).Count -eq 1) 'the owner store actually gained the item (verified write)'
Assert-True (-not (Get-InboxItemById -Id $p.id)) 'SSOT: proposal leaves the inbox after a verified success (no second copy)'
$exec = Get-ExecutionById -Id $r.executionId
Assert-True ($exec.state -eq 'succeeded') 'execution ends in succeeded'
Assert-True (((Get-ExecHistoryStates -Id $r.executionId) -join ',') -eq 'pending,validating,executing,verifying,succeeded') 'audit trail walks every state in order'

# =====================================================================
Write-TestSection 'verification is REQUIRED before success'
# =====================================================================
# a handler that claims success with an id the verifier will never find
Register-ActionHandler -Type 'ghost' -Execute { param($rec) [pscustomobject]@{ ok = $true; destination = 'Action Items'; newId = 'AI-NEVER'; message = 'claims done' } } -Verify { param($rec) Test-ExecutionApplied -Destination 'Action Items' -NewId ([string]$rec.result.newId) }
$g = Invoke-TestExecution -Proposal ([pscustomobject]@{ id = 'P-ghost'; type = 'ghost'; title = 'Ghost'; description = ''; source = ''; sourceId = ''; proposedDestination = '' })
Assert-True (-not $g.ok) 'an unverifiable execution returns ok=false'
Assert-True ((Get-ExecutionById -Id $g.executionId).state -eq 'failed') 'an unverifiable execution ends in failed'
$gs = Get-ExecHistoryStates -Id $g.executionId
Assert-True (($gs -contains 'verifying') -and (-not ($gs -contains 'succeeded'))) 'it reached verifying but was NEVER marked succeeded'

# a handler whose execute THROWS -> failed, engine never throws
Register-ActionHandler -Type 'boom' -Execute { param($rec) throw 'kaboom' } -Verify { param($rec) $true }
$b = Invoke-TestExecution -Proposal ([pscustomobject]@{ id = 'P-boom'; type = 'boom'; title = 'Boom'; description = ''; source = ''; sourceId = ''; proposedDestination = '' })
Assert-True ((-not $b.ok) -and (Get-ExecutionById -Id $b.executionId).state -eq 'failed') 'a throwing handler fails calmly (engine never throws)'

# =====================================================================
Write-TestSection 'approval-first + pending-on-failure (the only trigger is approval)'
# =====================================================================
# a proposal that has not been approved has produced NO execution and NO owner write
$execCountBefore = @(Get-Executions -State 'all').Count
$pending = New-TestProposal -Type 'task' -Title 'Not yet approved'
Assert-True ([bool](Get-InboxItemById -Id $pending.id)) 'an un-approved proposal just sits in the inbox'
Assert-True (@(Get-Executions -State 'all').Count -eq $execCountBefore) 'creating a proposal creates NO execution (approval is the only trigger)'
# a failing execution leaves the proposal PENDING and retriable
$pf = New-TestProposal -Type 'set-priority' -Title 'bump' -SourceId 'AI-NOPE'   # target missing -> execute fails
$rf = Approve-InboxItem -Id $pf.id
Assert-True ((-not $rf.ok) -and [bool](Get-InboxItemById -Id $pf.id)) 'a failed execution leaves the proposal pending (retriable), not consumed'
# rejecting a proposal never executes it
$pr = New-TestProposal -Type 'task' -Title 'To be rejected'
[void](Reject-InboxItem -Id $pr.id)
Assert-True (@(Get-Executions -State 'all' | Where-Object { $_.proposalId -eq $pr.id }).Count -eq 0) 'a rejected proposal is never executed'

# =====================================================================
Write-TestSection 'local action verbs (Action Items) - each execute + verify'
# =====================================================================
$aid = (New-TestActionItems -Count 1 -Titles @('Existing task'))[0]
# reminder (create)
$rem = Approve-InboxItem -Id (New-TestProposal -Type 'reminder' -Title 'Renew license' -Description '2026-08-01').id
Assert-True ($rem.ok -and (Get-ActionItemField -Id $rem.newId -Field 'remindAt') -like '2026-08-01T00:00:00*') 'reminder: creates an item with a verified remindAt (ISO, explicit offset)'
# set-priority (modify existing)
$pri = Approve-InboxItem -Id (New-TestProposal -Type 'set-priority' -Title 'bump' -Description 'high' -SourceId $aid).id
Assert-True ($pri.ok -and (Get-ActionItemField -Id $aid -Field 'priority') -eq 'high') 'set-priority: sets a verified priority on the target'
# defer (modify existing)
$def = Approve-InboxItem -Id (New-TestProposal -Type 'defer' -Title 'later' -Description '2026-09-01' -SourceId $aid).id
Assert-True ($def.ok -and (Get-ActionItemField -Id $aid -Field 'deferredUntil') -eq '2026-09-01') 'defer: sets a verified deferredUntil on the target'
# archive (retire existing)
$arc = Approve-InboxItem -Id (New-TestProposal -Type 'archive' -Title 'retire' -SourceId $aid).id
Assert-True ($arc.ok -and [bool](@((Get-ActionItemsData).items | Where-Object { $_.id -eq $aid })[0].archived)) 'archive: the target is verified archived'

# =====================================================================
Write-TestSection 'reasoning providers never write (the engine is the only writer)'
# =====================================================================
# building a proposal is NOT executing it: no owner write, no execution record
$aiBefore = @((Get-ActionItemsData).items).Count
$execBefore = @(Get-Executions -State 'all').Count
$null = New-TestProposal -Type 'task' -Title 'Just a proposal'
Assert-True ($aiBefore -eq @((Get-ActionItemsData).items).Count) 'proposing writes NOTHING to any owner store'
Assert-True (@(Get-Executions -State 'all').Count -eq $execBefore) 'proposing creates NO execution'

# =====================================================================
Write-TestSection 'restart safety: non-terminal executions recovered by re-verification'
# =====================================================================
$landed = (New-TestActionItems -Count 1 -Titles @('Landed'))[0]
$log = Get-ExecutionLog
$stuckOk = [pscustomobject]@{ id = 'EXE-90001'; proposalId = 'P-a'; type = 'task'; title = 'stuck-landed'; description = ''; source = ''; sourceId = ''; proposedDestination = ''; state = 'executing'; createdAt = 't'; updatedAt = 't'; attempts = 1; result = [pscustomobject]@{ ok = $true; destination = 'Action Items'; newId = $landed; message = 'm' }; history = @([pscustomobject]@{ state = 'executing'; at = 't'; detail = 'crash' }) }
$stuckNo = [pscustomobject]@{ id = 'EXE-90002'; proposalId = 'P-b'; type = 'task'; title = 'stuck-notlanded'; description = ''; source = ''; sourceId = ''; proposedDestination = ''; state = 'verifying'; createdAt = 't'; updatedAt = 't'; attempts = 1; result = [pscustomobject]@{ ok = $true; destination = 'Action Items'; newId = 'AI-GONE'; message = 'm' }; history = @([pscustomobject]@{ state = 'verifying'; at = 't'; detail = 'crash' }) }
$log.executions = @($log.executions) + $stuckOk + $stuckNo
Save-ExecutionLog $log
$rec = Restore-ActionEngine
Assert-True ($rec.recovered -eq 2) 'recovery processed both non-terminal records'
Assert-True ((Get-ExecutionById -Id 'EXE-90001').state -eq 'succeeded') 'a change that DID land is recovered to succeeded'
Assert-True ((Get-ExecutionById -Id 'EXE-90002').state -eq 'failed') 'a change that did NOT land is recovered to failed (safe to re-propose)'
Assert-True ((Get-ExecutionSummary).inFlight -eq 0) 'no execution is left dangling after recovery'
# recovery NEVER re-runs the write (no double-write): item count for the landed id stays 1
Assert-True (@((Get-ActionItemsData).items | Where-Object { $_.id -eq $landed }).Count -eq 1) 'recovery re-verifies but never re-executes (no double-write)'

# =====================================================================
Write-TestSection 'audit trail completeness'
# =====================================================================
Assert-True (@(Get-Executions -State 'all' | Where-Object { @($_.history).Count -ge 1 }).Count -eq @(Get-Executions -State 'all').Count) 'every execution carries a non-empty history'
$sum = Get-ExecutionSummary
Assert-True ($sum.total -eq (@(Get-Executions -State 'all').Count) -and $sum.total -ge 1) 'the audit summary counts every execution'

Complete-TestFile 'action-engine'
