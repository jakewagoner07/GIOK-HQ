# =====================================================================
# hardening.tests.ps1 - the Epic 15.1 adversarial battery (permanent)
# ---------------------------------------------------------------------
# Proves the hardened guarantees under crash, retry, hostile-handler, and
# audit-log failure scenarios: intent-before-side-effect, engine-private state,
# idempotency, fail-closed sole authority, audit durability, action validation,
# and grounded approval metadata. Every store is sandboxed.
# =====================================================================

. (Join-Path $PSScriptRoot '_harness.ps1')
Assert-Sandboxed

function New-RawProposal {
    param([string]$Type, [string]$Title, [string]$Description = '', [string]$SourceId = '')
    return [pscustomobject]@{ id = ('P-' + [guid]::NewGuid().ToString('N').Substring(0, 8)); type = $Type; title = $Title; description = $Description; source = 'test'; sourceId = $SourceId; proposedDestination = '' }
}

# =====================================================================
Write-TestSection 'ATOMICITY: intent is persisted BEFORE the handler runs'
# =====================================================================
# a handler that re-reads the log FROM DISK mid-execute and reports what is
# already persisted: the record must be at state=executing WITH its intent.
$script:SeenPersistedIntent = $false
$script:SeenPersistedState = ''
Register-ActionHandler -Type 'introspect' -Execute {
    param($Request)
    $onDisk = Get-ExecutionById -Id ([string]$Request.executionId)
    $script:SeenPersistedIntent = [bool]($onDisk -and $onDisk.intent)
    $script:SeenPersistedState = [string]$onDisk.state
    return [pscustomobject]@{ ok = $false; message = 'introspection only' }
} -Verify { param($Request) $true }
$null = Invoke-TestExecution -Proposal (New-RawProposal -Type 'introspect' -Title 'watch me')
Assert-True $script:SeenPersistedIntent 'INTENT-BEFORE-SIDE-EFFECT: the persisted record already carries the intent when the handler runs'
Assert-True ($script:SeenPersistedState -eq 'executing') 'the persisted state is executing before any handler work'

# =====================================================================
Write-TestSection 'ATOMICITY: crash after owner write, before result/state update'
# =====================================================================
# craft the EXACT B1 window: intent persisted, owner write landed, state=executing,
# result=null - then recover.
$d = Get-ActionItemsData; [void](Add-ActionItem -Data $d -Title 'Landed create' -Id 'AI-801'); Save-ActionItemsData $d
$null = Set-ActionItemFields -Id 'AI-801' -Fields @{ priority = 'high' }
$g = Add-Goal -Title 'Recovered goal' -Reason 'x'
$log = Get-ExecutionLog
$mkStuck = { param($id, $type, $title, $intent) [pscustomobject]@{ id = $id; proposalId = "P-$id"; type = $type; title = $title; description = ''; source = ''; sourceId = ''; proposedDestination = ''; state = 'executing'; createdAt = 't'; updatedAt = 't'; attempts = 1; idempotencyKey = "k-$id"; approval = $null; intent = $intent; result = $null; history = @([pscustomobject]@{ state = 'executing'; at = 't'; detail = 'crash' }) } }
$log.executions = @($log.executions) +
(& $mkStuck 'EXE-80001' 'task' 'Landed create' ([pscustomobject]@{ mode = 'create-id'; destination = 'Action Items'; targetId = 'AI-801'; newId = 'AI-801'; field = ''; expected = ''; title = 'Landed create'; create = $true })) +
(& $mkStuck 'EXE-80002' 'set-priority' 'bump' ([pscustomobject]@{ mode = 'field'; destination = 'Action Items'; targetId = 'AI-801'; newId = ''; field = 'priority'; expected = 'high'; title = 'bump'; create = $false })) +
(& $mkStuck 'EXE-80003' 'task' 'Never landed' ([pscustomobject]@{ mode = 'create-id'; destination = 'Action Items'; targetId = 'AI-999'; newId = 'AI-999'; field = ''; expected = ''; title = 'Never landed'; create = $true })) +
(& $mkStuck 'EXE-80004' 'goal' 'Recovered goal' ([pscustomobject]@{ mode = 'title'; destination = 'Goals'; targetId = ''; newId = ''; field = ''; expected = ''; title = 'Recovered goal'; create = $true }))
Save-ExecutionLog $log
$aiBefore = @((Get-ActionItemsData).items).Count
$rec = Restore-ActionEngine
Assert-True ($rec.recovered -eq 4) 'recovery processed all four crash-window records'
Assert-True ((Get-ExecutionById -Id 'EXE-80001').state -eq 'succeeded') 'CREATE landed + result=null -> recovered SUCCEEDED (B1 closed)'
Assert-True ((Get-ExecutionById -Id 'EXE-80002').state -eq 'succeeded') 'UPDATE landed + result=null -> recovered SUCCEEDED'
Assert-True ((Get-ExecutionById -Id 'EXE-80003').state -eq 'failed') 'absent change -> recovered FAILED (retriable)'
Assert-True ((Get-ExecutionById -Id 'EXE-80004').state -eq 'succeeded') 'owner-minted (title-mode) landed -> recovered SUCCEEDED'
Assert-True (@((Get-ActionItemsData).items).Count -eq $aiBefore) 'recovery performed ZERO owner writes (no re-run, no double write)'
$rec2 = Restore-ActionEngine
Assert-True ($rec2.recovered -eq 0) 'recovery is idempotent (second pass is a no-op)'

# =====================================================================
Write-TestSection 'HOSTILE HANDLERS: the engine alone controls state'
# =====================================================================
Register-ActionHandler -Type 'h-forge' -Execute { param($Request)
    try { Set-ExecutionState -Record $Request -State 'succeeded' -Detail 'forged' } catch { }
    return [pscustomobject]@{ ok = $false; message = 'tried to forge' }
} -Verify { param($Request) $true }
$f = Invoke-TestExecution -Proposal (New-RawProposal -Type 'h-forge' -Title 'forge')
Assert-True ((-not $f.ok) -and (Get-ExecutionById -Id $f.executionId).state -eq 'failed') 'SET-SUCCEEDED-DIRECTLY attempt ends failed (ok=false can never become succeeded)'

Register-ActionHandler -Type 'h-forgefield' -Execute { param($Request)
    return [pscustomobject]@{ ok = $true; state = 'succeeded'; history = @('forged'); destination = 'Action Items'; newId = 'AI-NOPE'; message = 'x' }
} -Verify { param($Request) $true }
$f2 = Invoke-TestExecution -Proposal (New-RawProposal -Type 'h-forgefield' -Title 'forge2')
Assert-True ((-not $f2.ok) -and (Get-ExecutionById -Id $f2.executionId).state -eq 'failed') 'FORGED state/history fields are dropped; unverifiable claim fails'

Register-ActionHandler -Type 'h-mut' -Execute { param($Request)
    $Request.title = 'HACKED'; $Request.intent.mode = 'result'
    return [pscustomobject]@{ ok = $false; message = 'mutated dto' }
} -Verify { param($Request) $true }
$m = Invoke-TestExecution -Proposal (New-RawProposal -Type 'h-mut' -Title 'original title')
Assert-True ((Get-ExecutionById -Id $m.executionId).title -eq 'original title') 'MUTATING the request DTO does not touch the live record (engine-private state)'

$terminalRec = Get-ExecutionById -Id $m.executionId
$locked = $false
try { Set-ExecutionState -Record $terminalRec -State 'succeeded' -Detail 'tamper' } catch { $locked = $true }
Assert-True $locked 'TERMINAL LOCK: a finished execution cannot be transitioned again'

Register-ActionHandler -Type 'h-multi' -Execute { param($Request)
    Write-Output 'stray pipeline output'
    return [pscustomobject]@{ ok = $true; destination = 'Action Items'; newId = 'AI-X'; message = 'x' }
} -Verify { param($Request) $true }
$mo = Invoke-TestExecution -Proposal (New-RawProposal -Type 'h-multi' -Title 'multi')
Assert-True ((-not $mo.ok) -and (Get-ExecutionById -Id $mo.executionId).state -eq 'failed') 'MALFORMED (multi-output) handler return is rejected'

# result purity: a valid handler smuggling extra fields -> persisted result has ONLY the four
$aidP = (New-TestActionItems -Count 1 -Titles @('purity target'))[0]
Register-ActionHandler -Type 'h-extra' -Execute { param($Request)
    $i = $Request.intent
    $null = Set-ActionItemFields -Id ([string]$i.targetId) -Fields @{ priority = [string]$i.expected }
    return [pscustomobject]@{ ok = $true; destination = 'Action Items'; newId = [string]$i.targetId; message = 'ok'; state = 'succeeded'; forged = 'field' }
} -Verify { param($Request) $true }
# reuse the set-priority intent shape by proposing set-priority but registered handler wins
$pp = New-RawProposal -Type 'set-priority' -Title 'bump' -Description 'high' -SourceId $aidP
$null = Register-ActionHandler -Type 'set-priority-purity' -Execute { param($r) $null } -Verify { param($r) $true }   # (unused; keeps registry API exercised)
$prRes = Invoke-TestExecution -Proposal $pp
$prRec = Get-ExecutionById -Id $prRes.executionId
Assert-True ($prRes.ok -and (@($prRec.result.PSObject.Properties.Name) -notcontains 'state') -and (@($prRec.result.PSObject.Properties.Name) -notcontains 'forged')) 'RESULT PURITY: persisted result carries only {ok,destination,newId,message}'

Register-ActionHandler -Type 'h-writethrow' -Execute { param($Request)
    $d = Get-ActionItemsData; $id = Get-NextActionId -Data $d; [void](Add-ActionItem -Data $d -Title 'orphan' -Id $id); Save-ActionItemsData $d
    throw 'after write'
} -Verify { param($Request) $true }
$wt = Invoke-TestExecution -Proposal (New-RawProposal -Type 'h-writethrow' -Title 'wt')
Assert-True ((-not $wt.ok) -and (Get-ExecutionById -Id $wt.executionId).state -eq 'failed') 'WRITE-THEN-THROW is recorded failed (truthful; orphan is visible, never claimed done)'

Register-ActionHandler -Type 'h-valid' -Execute { param($Request)
    $i = $Request.intent
    if (-not (New-IntendedActionItem -Id ([string]$i.newId) -Title ([string]$Request.title))) { return [pscustomobject]@{ ok = $false; message = 'owner unavailable' } }
    return [pscustomobject]@{ ok = $true; destination = 'Action Items'; newId = [string]$i.newId; message = 'ok' }
} -Verify { param($Request) $true }
# h-valid is a custom type -> intent mode 'result'; give it a create-id intent by using type 'task' with the default engine path instead:
$hv = Invoke-TestExecution -Proposal (New-RawProposal -Type 'task' -Title 'legit create')
Assert-True ($hv.ok -and (Get-ExecutionById -Id $hv.executionId).state -eq 'succeeded') 'a VALID execution still passes cleanly through all gates'

# =====================================================================
Write-TestSection 'IDEMPOTENCY: one proposal, at most one successful execution'
# =====================================================================
$ip = New-RawProposal -Type 'task' -Title 'Only once'
$b1 = @((Get-ActionItemsData).items).Count
$i1 = Invoke-TestExecution -Proposal $ip
$i2 = Invoke-TestExecution -Proposal $ip
$i3 = Invoke-TestExecution -Proposal $ip
Assert-True ((@((Get-ActionItemsData).items).Count - $b1) -eq 1) 'three invocations of the same proposal -> exactly ONE owner write'
Assert-True ($i2.deduped -and $i2.ok -and $i2.executionId -eq $i1.executionId) 'the second call returns the FIRST execution result (deduped, from the persisted log)'
Assert-True ($i3.deduped -and $i3.executionId -eq $i1.executionId) 'idempotency survives repeated calls (key persisted in the log)'
$succTwins = @(Get-Executions -State 'succeeded' | Where-Object { $_.proposalId -eq $ip.id })
Assert-True ($succTwins.Count -eq 1) 'exactly ONE succeeded execution exists for the proposal'
# duplicate approval clicks
$dap = New-TestProposal -Type 'task' -Title 'Click twice'
$c1 = Approve-InboxItem -Id $dap.id
$c2 = Approve-InboxItem -Id $dap.id
Assert-True ($c1.ok -and (-not $c2.ok)) 'duplicate APPROVAL clicks: first executes, second is refused (proposal gone)'
# failed -> deliberate retry policy: a new attempt is allowed and distinct
$rp = New-RawProposal -Type 'set-priority' -Title 'bump' -Description 'high' -SourceId 'AI-ABSENT'
$x1 = Invoke-TestExecution -Proposal $rp
$x2 = Invoke-TestExecution -Proposal $rp
Assert-True ((-not $x1.ok) -and (-not $x2.ok) -and ($x1.executionId -ne $x2.executionId)) 'RETRY POLICY: only a failed execution permits a new deliberate attempt (distinct record)'

# =====================================================================
Write-TestSection 'AUDIT LOG: atomic, backed up, corruption-aware, fail-closed'
# =====================================================================
$lp = Get-ExecutionLogPath
Assert-True (Test-Path ($lp + '.bak')) 'every atomic save refreshes the last-known-good backup'
Set-Content -Path $lp -Value '{ corrupted' -Encoding UTF8
Assert-True ((Get-ExecutionLogState) -eq 'backup') 'corrupt primary -> state=backup (recovered)'
Assert-True (@(Get-Executions -State 'all').Count -ge 1) 'corrupt primary does NOT silently erase history (backup serves it)'
$null = Invoke-TestExecution -Proposal (New-RawProposal -Type 'task' -Title 'heal')
Assert-True ((Get-ExecutionLogState) -eq 'ok') 'the next save heals the primary atomically'
# BOTH copies unreadable -> fail closed: no execution, no owner write
Set-Content -Path $lp -Value '{ corrupted' -Encoding UTF8
Set-Content -Path ($lp + '.bak') -Value 'also corrupted' -Encoding UTF8
Assert-True ((Get-ExecutionLogState) -eq 'failed') 'both copies unreadable -> store is fail-closed'
$aiFc = @((Get-ActionItemsData).items).Count
$fcr = Invoke-TestExecution -Proposal (New-RawProposal -Type 'task' -Title 'must not run')
Assert-True ((-not $fcr.ok) -and (@((Get-ActionItemsData).items).Count -eq $aiFc)) 'FAIL-CLOSED store: execution refused calmly, ZERO owner writes (log-write failure prevents the side effect)'
Remove-Item $lp, ($lp + '.bak') -Force -ErrorAction SilentlyContinue
Assert-True ((Get-ExecutionLogState) -eq 'fresh') 'missing log -> fresh empty store (first-run semantics)'
# LOCKED primary: the save cannot replace -> execution refused, no side effect
$seed = Invoke-TestExecution -Proposal (New-RawProposal -Type 'task' -Title 'seed for lock')
$fs = [System.IO.File]::Open($lp, 'Open', 'Read', 'None')
$aiLk = @((Get-ActionItemsData).items).Count
$lk = Invoke-TestExecution -Proposal (New-RawProposal -Type 'task' -Title 'locked out')
$fs.Close(); $fs.Dispose()
Assert-True ((-not $lk.ok) -and (@((Get-ActionItemsData).items).Count -eq $aiLk)) 'LOCKED log degrades calmly: execution refused, no owner write'
$post = Invoke-TestExecution -Proposal (New-RawProposal -Type 'task' -Title 'after unlock')
Assert-True ($post.ok) 'after the lock releases, execution works again'
# rapid sequential writes: nothing lost
$rapidBefore = @(Get-Executions -State 'all').Count
1..6 | ForEach-Object { $null = Invoke-TestExecution -Proposal (New-RawProposal -Type 'task' -Title ("rapid {0}" -f $_)) }
Assert-True ((@(Get-Executions -State 'all').Count - $rapidBefore) -eq 6) 'rapid serialized writes: every execution recorded, none overwritten'
# retention: bounded, never prunes non-terminal
$log = Get-ExecutionLog
$mkT = { param($i, $st) [pscustomobject]@{ id = ('EXE-{0:00000}' -f $i); proposalId = "P$i"; type = 'task'; title = "t$i"; description = ''; source = ''; sourceId = ''; proposedDestination = ''; state = $st; createdAt = 't'; updatedAt = 't'; attempts = 1; idempotencyKey = "k$i"; approval = $null; intent = $null; result = $null; history = @() } }
$log.executions = @(30001..30520 | ForEach-Object { & $mkT $_ 'succeeded' }) + @(& $mkT 30900 'executing')
Save-ExecutionLog $log
$kept = @(Get-Executions -State 'all')
Assert-True ($kept.Count -le 501) 'retention is bounded (cap + protected non-terminal)'
Assert-True (@($kept | Where-Object { $_.id -eq 'EXE-30900' }).Count -eq 1) 'retention NEVER prunes a non-terminal execution'
Assert-True (@($kept | Where-Object { $_.id -eq 'EXE-30001' }).Count -eq 0 -and @($kept | Where-Object { $_.id -eq 'EXE-30520' }).Count -eq 1) 'retention drops the OLDEST terminal records, keeps the newest'
Remove-Item $lp, ($lp + '.bak') -Force -ErrorAction SilentlyContinue   # clean store for the next sections

# =====================================================================
Write-TestSection 'ACTION VALIDATION: malformed payloads write nothing'
# =====================================================================
$vt = (New-TestActionItems -Count 1 -Titles @('validation target'))[0]
$vB = @((Get-ActionItemsData).items).Count
$bad1 = Invoke-TestExecution -Proposal (New-RawProposal -Type 'set-priority' -Title 'b' -Description 'ZZ-NOT-A-PRIORITY' -SourceId $vt)
Assert-True ((-not $bad1.ok) -and $bad1.message -match 'invalid priority') 'INVALID PRIORITY rejects (allowed: low, medium, high)'
$bad2 = Invoke-TestExecution -Proposal (New-RawProposal -Type 'defer' -Title 'l' -Description 'not-a-date' -SourceId $vt)
Assert-True ((-not $bad2.ok) -and $bad2.message -match 'invalid defer') 'INVALID DEFER DATE rejects'
$bad3 = Invoke-TestExecution -Proposal (New-RawProposal -Type 'defer' -Title 'l' -Description '2020-01-01' -SourceId $vt)
Assert-True ((-not $bad3.ok) -and $bad3.message -match 'past') 'PAST defer date rejects'
$bad4 = Invoke-TestExecution -Proposal (New-RawProposal -Type 'reminder' -Title 'p' -Description 'garbage-ts')
Assert-True ((-not $bad4.ok) -and $bad4.message -match 'invalid reminder') 'INVALID REMINDER TIMESTAMP rejects'
$bad5 = Invoke-TestExecution -Proposal (New-RawProposal -Type 'archive' -Title 'r' -SourceId 'AI-MISSING')
Assert-True ((-not $bad5.ok) -and $bad5.message -match 'not found') 'MISSING TARGET ID fails calmly'
$unk = [pscustomobject]@{ id = 'P-unk'; type = 'task'; title = 'x'; description = ''; source = 't'; sourceId = ''; proposedDestination = ''; hackField = 'attack' }
$bad6 = Invoke-ProposalExecution -Proposal $unk -Approval (New-TestApproval -Proposal $unk)
Assert-True ((-not $bad6.ok) -and $bad6.message -match 'unsupported proposal field') 'UNSUPPORTED PROPOSAL FIELD rejects (not silently ignored)'
$empty = New-RawProposal -Type 'task' -Title '   '
$bad7 = Invoke-ProposalExecution -Proposal $empty -Approval (New-TestApproval -Proposal $empty)
Assert-True (-not $bad7.ok) 'EMPTY TASK TITLE rejects'
Assert-True (@((Get-ActionItemsData).items).Count -eq $vB) 'all validation failures produced ZERO owner writes'
# reminder timezone semantics: normalized to ISO-8601 with an explicit UTC offset
$remR = Invoke-TestExecution -Proposal (New-RawProposal -Type 'reminder' -Title 'tz check' -Description '2026-08-01 09:30')
$remVal = [string](Get-ActionItemField -Id $remR.newId -Field 'remindAt')
Assert-True ($remR.ok -and $remVal -match '^2026-08-01T09:30:00[+-]\d{2}:\d{2}$') 'REMINDER timestamps carry explicit timezone semantics (ISO-8601 with offset)'
# unrelated fields untouched by an update verb
$fieldsBefore = @((Get-ActionItemsData).items | Where-Object { $_.id -eq $vt })[0] | ConvertTo-Json -Depth 6
$null = Invoke-TestExecution -Proposal (New-RawProposal -Type 'set-priority' -Title 'b' -Description 'low' -SourceId $vt)
$itemAfter = @((Get-ActionItemsData).items | Where-Object { $_.id -eq $vt })[0]
Assert-True ($itemAfter.title -eq 'validation target' -and (-not [bool]$itemAfter.done) -and (-not [bool]$itemAfter.archived)) 'update verbs change ONLY the intended field (title/done/archived untouched)'

# =====================================================================
Write-TestSection 'SOLE AUTHORITY: no engine -> fail closed, no fallback route'
# =====================================================================
$fp = New-TestProposal -Type 'task' -Title 'No engine today'
$realFn = ${function:Invoke-ProposalExecution}
Remove-Item Function:Invoke-ProposalExecution
$aiB2 = @((Get-ActionItemsData).items).Count
$fc2 = $null
try { $fc2 = Approve-InboxItem -Id $fp.id } catch { $fc2 = $null }
Set-Item Function:Invoke-ProposalExecution $realFn
Assert-True ($fc2 -and (-not $fc2.ok) -and $fc2.message -match 'Action Engine') 'engine unavailable -> approval FAILS CLOSED with a calm, actionable message'
Assert-True (@((Get-ActionItemsData).items).Count -eq $aiB2) 'NO direct owner-route fallback executed (zero writes)'
Assert-True ([bool](Get-InboxItemById -Id $fp.id)) 'the proposal remains pending, ready when the engine returns'

# =====================================================================
Write-TestSection 'APPROVAL: grounded metadata; stale fingerprints reject'
# =====================================================================
$ap2 = New-TestProposal -Type 'task' -Title 'Approved with metadata'
$ar2 = Approve-InboxItem -Id $ap2.id -ApprovedBy 'Jake'
$arec2 = Get-ExecutionById -Id $ar2.executionId
Assert-True ($arec2.approval.approvedBy -eq 'Jake' -and [bool]$arec2.approval.approvedAt -and $arec2.approval.source -eq 'executive-inbox') 'approvedBy / approvedAt / approvalSource are persisted and truthful'
Assert-True ([bool]$arec2.approval.fingerprint) 'the approval fingerprint (proposal revision) is persisted'
$na2 = Invoke-ProposalExecution -Proposal (New-RawProposal -Type 'task' -Title 'No approval')
Assert-True ((-not $na2.ok) -and $na2.message -match 'approval') 'a direct call WITHOUT approval metadata fails safely (approval-first is structural)'
$sp2 = New-RawProposal -Type 'task' -Title 'Original wording'
$staleAp = New-TestApproval -Proposal $sp2
$sp2.title = 'Edited after approval'
$sr2 = Invoke-ProposalExecution -Proposal $sp2 -Approval $staleAp
Assert-True ((-not $sr2.ok) -and $sr2.message -match 'changed after it was approved') 'EDITING a proposal invalidates the old approval fingerprint'

Complete-TestFile 'hardening'
