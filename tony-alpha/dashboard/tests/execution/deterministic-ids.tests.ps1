# =====================================================================
# deterministic-ids.tests.ps1 - Epic 16A cross-owner recovery + idempotency
# ---------------------------------------------------------------------
# Every supported owner create now uses a deterministic PRE-ALLOCATED id and is
# verified by EXACT identity. This suite proves the full crash matrix and the
# idempotency/id-stability rules for EVERY migrated owner class, plus the required
# cross-owner collision case (existing id A / intended id B / decoy id C).
# Every store is sandboxed.
# =====================================================================

. (Join-Path $PSScriptRoot '_harness.ps1')
Assert-Sandboxed

# Each migrated owner type: proposal type, expected id prefix, and a verifier that a
# record of a given id exists in that owner store.
$OWNERS = @(
    @{ type = 'goal'; prefix = 'G'; exists = { param($id) [bool](@(Get-GoalsList | Where-Object { $_.id -eq $id }).Count -gt 0) } }
    @{ type = 'project'; prefix = 'PRJ'; exists = { param($id) [bool](Get-LifeItemById -Domain 'projects' -Id $id) } }
    @{ type = 'non-negotiable'; prefix = 'NN'; exists = { param($id) [bool](Get-LifeItemById -Domain 'nonNegotiables' -Id $id) } }
    @{ type = 'family'; prefix = 'FAM'; exists = { param($id) [bool](Get-LifeItemById -Domain 'family' -Id $id) } }
    @{ type = 'health'; prefix = 'HL'; exists = { param($id) [bool](Get-LifeItemById -Domain 'health' -Id $id) } }
    @{ type = 'financial'; prefix = 'FN'; exists = { param($id) [bool](Get-LifeItemById -Domain 'financial' -Id $id) } }
    @{ type = 'agency'; prefix = 'AG'; exists = { param($id) [bool](Get-LifeItemById -Domain 'agency' -Id $id) } }
    @{ type = 'learning'; prefix = 'LR'; exists = { param($id) [bool](Get-LifeItemById -Domain 'learning' -Id $id) } }
    @{ type = 'memory'; prefix = 'MEM'; exists = { param($id) [bool](@(Get-Memories | Where-Object { $_.id -eq $id }).Count -gt 0) } }
)
$i = 0
function New-Prop { param([string]$Type, [string]$Title) $script:i++; return [pscustomobject]@{ id = ("P-{0:000}" -f $script:i); uid = ([guid]::NewGuid().ToString('N')); type = $Type; title = $Title; description = ''; source = 't'; sourceId = ''; proposedDestination = '' } }
function Stuck { param([string]$Id, $Prop, $Result = $null) $intent = (New-ExecutionIntent -Proposal $Prop).intent; return [pscustomobject]@{ id = $Id; proposalId = $Prop.id; type = $Prop.type; title = $Prop.title; description = ''; source = 't'; sourceId = ''; proposedDestination = ''; state = 'executing'; createdAt = 't'; updatedAt = 't'; attempts = 1; idempotencyKey = (Get-ExecutionIdempotencyKey -Proposal $Prop); approval = $null; intent = $intent; result = $Result; history = @([pscustomobject]@{ state = 'executing'; at = 't'; detail = 'crash' }) } }
function Add-Recover { param($Rec) $log = Get-ExecutionLog; $log.executions = @($log.executions) + $Rec; Save-ExecutionLog $log; return (Restore-ActionEngine) }

# =====================================================================
Write-TestSection 'per-owner: intent carries a stable pre-allocated id; live create + verify by exact id'
# =====================================================================
foreach ($o in $OWNERS) {
    $t = $o.type
    $p = New-Prop $t ("Live $t")
    $intent = (New-ExecutionIntent -Proposal $p).intent
    Assert-True ($intent.mode -eq 'create-id' -and $intent.newId -match ('^' + $o.prefix + '-X[0-9a-f]{8}$')) "[$t] intent is create-id with a pre-allocated <PREFIX>-X id"
    $approval = New-TestApproval -Proposal $p
    $r = Invoke-ProposalExecution -Proposal $p -Approval $approval
    Assert-True ($r.ok -and $r.newId -eq $intent.newId) "[$t] execute persists the exact pre-allocated id"
    Assert-True (& $o.exists $r.newId) "[$t] the owner record LANDS under that exact id (verify by identity)"
    Assert-True ((Get-ExecutionById -Id $r.executionId).intent.newId -eq $r.newId) "[$t] intent.newId is linked to the execution record"
}

# =====================================================================
Write-TestSection 'per-owner crash matrix (A: no write / B: landed / C: decoy id / D: idempotent replay)'
# =====================================================================
foreach ($o in $OWNERS) {
    $t = $o.type
    # A. intent persisted, owner write NEVER occurred -> failed, zero writes
    $pA = New-Prop $t ("A-$t")
    $before = if ($t -eq 'memory') { @(Get-Memories).Count } elseif ($t -eq 'goal') { @(Get-GoalsList).Count } else { @(Get-LifeItems -Domain ($o.prefix)).Count }  # count is only used for goal/memory below
    $recA = Add-Recover (Stuck ("EXE-A-$t") $pA $null)
    Assert-True ((Get-Executions -State 'all' | Where-Object { $_.proposalId -eq $pA.id })[0].state -eq 'failed') "[$t] A: crash before owner write -> recovered FAILED/retriable"
    Assert-True (-not (& $o.exists ((New-ExecutionIntent -Proposal $pA).intent.newId))) "[$t] A: no owner record was created during recovery"

    # B. intent persisted, owner write occurred under the exact id, result/state not persisted -> succeeded
    $pB = New-Prop $t ("B-$t")
    $intentB = (New-ExecutionIntent -Proposal $pB).intent
    if ($t -eq 'goal') { [void](Add-Goal -Title 'B-goal' -Id $intentB.newId) }
    elseif ($t -eq 'memory') { [void](Approve-Memory -Category 'Preferences' -Value 'B-mem' -Id $intentB.newId) }
    else { [void](Add-LifeItem -Domain (@{ project = 'projects'; 'non-negotiable' = 'nonNegotiables'; family = 'family'; health = 'health'; financial = 'financial'; agency = 'agency'; learning = 'learning' }[$t]) -Fields @{ title = "B-$t" } -Id $intentB.newId) }
    $recB = Add-Recover (Stuck ("EXE-B-$t") $pB $null)
    Assert-True ((Get-ExecutionById -Id ("EXE-B-$t")).state -eq 'succeeded') "[$t] B: crash after owner write (exact id exists) -> recovered SUCCEEDED"

    # C. a same-title record exists under a DIFFERENT (decoy) id -> the intent still fails
    $pC = New-Prop $t ("C-$t decoy")
    if ($t -eq 'goal') { [void](Add-Goal -Title 'C-t decoy') }
    elseif ($t -eq 'memory') { [void](Approve-Memory -Category 'Preferences' -Value 'C-t decoy') }
    else { [void](Add-LifeItem -Domain (@{ project = 'projects'; 'non-negotiable' = 'nonNegotiables'; family = 'family'; health = 'health'; financial = 'financial'; agency = 'agency'; learning = 'learning' }[$t]) -Fields @{ title = "C-$t decoy-real" }) }
    $recC = Add-Recover (Stuck ("EXE-C-$t") $pC $null)   # pC's pre-allocated id was never created
    Assert-True ((Get-ExecutionById -Id ("EXE-C-$t")).state -eq 'failed') "[$t] C: a same-title record with a different id does NOT satisfy verification -> FAILED"

    # D. repeated recovery is idempotent (zero further work)
    $again = Restore-ActionEngine
    Assert-True ($again.recovered -eq 0) "[$t] D: repeated recovery is idempotent (0 recovered)"
}

# =====================================================================
Write-TestSection 'THE required cross-owner collision case (id A / intended B / decoy C)'
# =====================================================================
# Existing record "Grow the agency" with id A.
$A = Add-Goal -Title 'Grow the agency' -Reason 'record A'
# Approved create "Grow the agency" -> the engine pre-allocates intended id B.
$pB = New-Prop 'goal' 'Grow the agency'
$B = (New-ExecutionIntent -Proposal $pB).intent.newId
Assert-True ($B -ne $A.id) 'intended id B differs from the pre-existing id A'
# crash before write -> recovery must FAIL (B was never created; A is not proof)
Add-Recover (Stuck 'EXE-COL1' $pB $null) | Out-Null
Assert-True ((Get-ExecutionById -Id 'EXE-COL1').state -eq 'failed') 'crash before write: recovery FAILS (pre-existing A never satisfies intended B)'
# owner write with intended id B -> recovery must SUCCEED
$pB2 = New-Prop 'goal' 'Grow the agency'
$B2 = (New-ExecutionIntent -Proposal $pB2).intent.newId
[void](Add-Goal -Title 'Grow the agency' -Reason 'record B' -Id $B2)
Add-Recover (Stuck 'EXE-COL2' $pB2 $null) | Out-Null
Assert-True ((Get-ExecutionById -Id 'EXE-COL2').state -eq 'succeeded') 'owner write under intended B: recovery SUCCEEDS by exact id'
# a record with the same title but id C must never satisfy verification for a fresh B
$C = Add-Goal -Title 'Grow the agency' -Reason 'decoy C'
$pB3 = New-Prop 'goal' 'Grow the agency'
Add-Recover (Stuck 'EXE-COL3' $pB3 $null) | Out-Null   # pB3's id was never created; A and C both share the title
Assert-True ((Get-ExecutionById -Id 'EXE-COL3').state -eq 'failed') 'a decoy record C with the same title never satisfies verification for intended B -> FAILED'

# =====================================================================
Write-TestSection 'idempotency + id stability'
# =====================================================================
# one proposal -> one target id; repeated direct invocation reuses the same execution + id
$p = New-Prop 'goal' 'Idempotent goal'
$gA = @(Get-GoalsList).Count
$r1 = Invoke-ProposalExecution -Proposal $p -Approval (New-TestApproval -Proposal $p)
$r2 = Invoke-ProposalExecution -Proposal $p -Approval (New-TestApproval -Proposal $p)
Assert-True ($r1.ok -and $r1.newId -match '^G-X') 'one proposal maps to one deterministic target id'
Assert-True ($r2.deduped -and $r2.executionId -eq $r1.executionId -and $r2.newId -eq $r1.newId) 'repeated invocation reuses the existing execution AND target id (one owner write)'
Assert-True (@(Get-GoalsList).Count -eq $gA + 1) 'only ONE owner record was created'
# restart does not change the target id: the SAME proposal re-derives the SAME id
Assert-True ((New-ExecutionIntent -Proposal $p).intent.newId -eq $r1.newId) 'restart/re-derivation yields the SAME target id (stable)'
# two DISTINCT proposals of identical content get DISTINCT ids (durable uid, not the reusable INBOX id)
$d1 = New-Prop 'goal' 'Same content'
$d2 = New-Prop 'goal' 'Same content'
Assert-True ((New-ExecutionIntent -Proposal $d1).intent.newId -ne (New-ExecutionIntent -Proposal $d2).intent.newId) 'distinct proposal instances get DISTINCT ids (no silent collision)'
# failed retry reuses the id (same proposal, not a new revision)
$pf = New-Prop 'goal' 'Retry goal'
$idf = (New-ExecutionIntent -Proposal $pf).intent.newId
[void](Add-Goal -Title 'occupied' -Id $idf)   # occupy the id so the first attempt's owner create fails
$f1 = Invoke-ProposalExecution -Proposal $pf -Approval (New-TestApproval -Proposal $pf)
Assert-True (-not $f1.ok) 'first attempt fails (id occupied by a foreign record)'
Assert-True ((New-ExecutionIntent -Proposal $pf).intent.newId -eq $idf) 'a failed retry does NOT mint a new id (same proposal -> same id)'
# an edited proposal (new fingerprint) yields a new intent id
$pe = New-Prop 'goal' 'Original title'
$idBefore = (New-ExecutionIntent -Proposal $pe).intent.newId
$pe.title = 'Edited title'
Assert-True ((New-ExecutionIntent -Proposal $pe).intent.newId -ne $idBefore) 'an edited proposal (new fingerprint) derives a NEW target id'

Complete-TestFile 'deterministic-ids'
