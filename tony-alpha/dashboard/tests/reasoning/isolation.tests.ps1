# =====================================================================
# isolation.tests.ps1 - nothing a driver can touch is shared
# ---------------------------------------------------------------------
# The kernel takes ONE canonical snapshot of the whole mutable surface at entry -
# payload, constraints AND context - and every dispatch works from its own fresh
# clone. A driver that mutates its copy, then fails, throws or lies, cannot
# poison the fallback, another provider, a later validation, or the caller.
#
# Cloning the payload alone was NOT enough, and that gap was a real bypass:
# constraints were passed by reference, so a driver could set
# requireGrounding=$false on the shared object and the validator - reading that
# same object moments later - would switch its own gate off. Anything a driver
# can touch must be a copy, or it is an input to validation that the attacker
# controls.
# =====================================================================

. (Join-Path $PSScriptRoot '_harness.ps1')
Assert-Sandboxed

$REAL = $script:TestGoalAnswer

# =====================================================================
Write-TestSection 'the cloning primitive'
# =====================================================================
$src = New-TestState
$clone = Copy-ReasoningPayload $src
Assert-True ((ConvertTo-Snapshot $clone) -eq (ConvertTo-Snapshot $src)) 'a clone is value-identical to its source'
$clone.answers.q_goal = 'CHANGED'
Assert-True ($src.answers.q_goal -eq $REAL) 'mutating the clone does not touch the source (it is a real copy, not a reference)'
Assert-True ($null -eq (Copy-ReasoningPayload $null)) 'cloning null yields null'

# An uncloneable payload must yield null, so the router can refuse rather than
# hand out shared references it cannot guarantee.
$unclonable = @{}
$unclonable[[pscustomobject]@{ k = 1 }] = 'v'   # a hashtable keyed by an object: ConvertTo-Json throws
Assert-True ($null -eq (Copy-ReasoningPayload $unclonable)) 'an uncloneable payload yields null rather than a shared reference'

# ...and the kernel refuses the whole request instead of running unisolated.
$r = Invoke-ReasoningTask -TaskId 'understanding.extract' -Payload $unclonable
Assert-True (-not $r.ok -and $r.reasonCode -eq 'invalid-output') ("an uncloneable request is REFUSED truthfully rather than run unisolated (reasonCode={0})" -f $r.reasonCode)

# =====================================================================
Write-TestSection 'payload isolation: six hostile mutators'
# =====================================================================
$mutators = @(
    @{ n = 'modifies a nested answer, returns null'; inv = { param($rq) $rq.input.answers.q_goal = 'POISON'; return $null } }
    @{ n = 'removes a whole field, returns null'; inv = { param($rq) $rq.input.PSObject.Properties.Remove('answers'); return $null } }
    @{ n = 'adds a fabricated field, then throws'; inv = { param($rq) $rq.input | Add-Member -NotePropertyName injected -NotePropertyValue 'POISON' -Force; throw 'die' } }
    @{ n = 'mutates then throws'; inv = { param($rq) $rq.input.answers.q_areas = 'POISON'; throw 'die' } }
    @{ n = 'mutates several fields, returns null'; inv = { param($rq) $rq.input.currentStep = 999; $rq.input.answers.q_boundaries = 'POISON'; return $null } }
    @{ n = 'poisons every answer, returns junk'; inv = {
            param($rq)
            foreach ($p in @($rq.input.answers.PSObject.Properties.Name)) { $rq.input.answers.$p = 'POISON' }
            return (New-ReasoningResult -TaskId $rq.taskId -Ok $true -Output ([pscustomobject]@{ nonsense = 1 }) -Confidence 0.9)
        }
    }
)
foreach ($m in $mutators) {
    $state = New-TestState
    $before = ConvertTo-Snapshot $state
    Register-TestProvider -Name 'mutator' -Invoke $m.inv
    $r = Invoke-TestExtract $state
    Assert-True ((ConvertTo-Snapshot $state) -eq $before) ("{0}: caller's payload byte-identical" -f $m.n)
    Assert-True ($r.ok -and $r.engine -eq 'local' -and -not (Test-OutputLeaks $r 'POISON')) ("{0}: the floor answered from clean state" -f $m.n)
    Unregister-TestProvider 'mutator'
}

# =====================================================================
Write-TestSection 'constraints isolation'
# =====================================================================
# The gate-switcher bypass, at the unit level: a driver rewriting constraints
# must not change what the validator enforces.
$switchers = @(
    @{ n = 'sets requireGrounding=$false'; inv = { param($rq) $rq.constraints.requireGrounding = $false; return $null } }
    @{ n = 'removes requireGrounding'; inv = { param($rq) $rq.constraints.PSObject.Properties.Remove('requireGrounding'); return $null } }
    @{ n = 'replaces the constraints object'; inv = { param($rq) $rq.constraints = [pscustomobject]@{ maxMs = 1; requireGrounding = $false }; return $null } }
    @{ n = 'nulls the constraints object'; inv = { param($rq) $rq.constraints = $null; return $null } }
)
foreach ($s in $switchers) {
    $req = New-ReasoningRequest -TaskId 'understanding.extract' -Payload (New-TestState)
    $before = ConvertTo-Snapshot $req.constraints
    Register-TestProvider -Name 'switcher' -Invoke $s.inv
    [void](Invoke-Reasoning -Request $req)
    Assert-True ((ConvertTo-Snapshot $req.constraints) -eq $before) ("{0}: caller's constraints byte-identical" -f $s.n)
    Unregister-TestProvider 'switcher'
}

# the decisive one: after the switcher runs, the gate must STILL reject a fabrication
Register-TestProvider -Name 'switch-and-lie' -Invoke {
    param($rq)
    $rq.constraints.requireGrounding = $false
    $m = New-UnderstandingModel -State $rq.input
    $m.goals = @((New-TestItem -Text 'Buy a yacht in Monaco'))
    return (New-ReasoningResult -TaskId $rq.taskId -Ok $true -Output $m -Confidence 0.9)
}
$r = Invoke-TestExtract
Assert-True ($r.engine -eq 'local' -and -not (Test-OutputLeaks $r 'yacht')) 'a driver that switches the gate off still cannot get its fabrication accepted'
Unregister-TestProvider 'switch-and-lie'

# =====================================================================
Write-TestSection 'context isolation'
# =====================================================================
$attacks = @(
    @{ n = 'overwrites a top-level context field'; inv = { param($rq) $rq.context.note = 'POISON'; return $null } }
    @{ n = 'overwrites a NESTED context field'; inv = { param($rq) $rq.context.nested.deep = 'POISON'; return $null } }
    @{ n = 'clears a context array'; inv = { param($rq) $rq.context.tags = @(); return $null } }
    @{ n = 'replaces the whole context object'; inv = { param($rq) $rq.context = [pscustomobject]@{ note = 'POISON' }; return $null } }
    @{ n = 'adds a field to context'; inv = { param($rq) $rq.context | Add-Member -NotePropertyName injected -NotePropertyValue 'POISON' -Force; return $null } }
)
foreach ($a in $attacks) {
    $ctx = New-TestContext
    $before = ConvertTo-Snapshot $ctx
    Register-TestProvider -Name 'ctx-attacker' -Invoke $a.inv
    $r = Invoke-Reasoning -Request (New-ReasoningRequest -TaskId 'understanding.extract' -Payload (New-TestState) -Context $ctx)
    Assert-True ((ConvertTo-Snapshot $ctx) -eq $before) ("{0}: caller's context byte-identical" -f $a.n)
    Assert-True ($r.ok -and $r.engine -eq 'local') ("{0}: floor still served" -f $a.n)
    Unregister-TestProvider 'ctx-attacker'
}

# =====================================================================
Write-TestSection 'drivers never see each other''s copies'
# =====================================================================
# Two mutators in a row: the second must see pristine input, not the first's damage.
Register-TestProvider -Name 'mutator-a' -Priority 1 -Invoke {
    param($rq)
    $rq.input.answers.q_goal = 'POISON-A'
    $rq.context.note = 'POISON-A'
    $rq.constraints.requireGrounding = $false
    return $null
}
$script:SeenByB = $null
Register-TestProvider -Name 'mutator-b' -Priority 2 -Invoke {
    param($rq)
    $script:SeenByB = [pscustomobject]@{ goal = $rq.input.answers.q_goal; note = $rq.context.note; rg = $rq.constraints.requireGrounding }
    return $null
}
[void](Invoke-Reasoning -Request (New-ReasoningRequest -TaskId 'understanding.extract' -Payload (New-TestState) -Context (New-TestContext)))
Assert-True ($script:SeenByB.goal -eq $REAL) ("the second driver saw a pristine PAYLOAD (goal='{0}')" -f $script:SeenByB.goal)
Assert-True ($script:SeenByB.note -eq 'pristine') ("the second driver saw a pristine CONTEXT (note='{0}')" -f $script:SeenByB.note)
Assert-True ($script:SeenByB.rg -eq $true) ("the second driver saw pristine CONSTRAINTS (requireGrounding={0})" -f $script:SeenByB.rg)
Unregister-TestProvider 'mutator-a'
Unregister-TestProvider 'mutator-b'

# and the FLOOR - the last line of defence - receives pristine state too
Register-TestProvider -Name 'pre-mutator' -Invoke {
    param($rq)
    $rq.input.answers.q_goal = 'POISON'
    $rq.constraints.requireGrounding = $false
    return $null
}
$r = Invoke-TestExtract
$grounded = [bool](@($r.output.goals) | Where-Object { $_.sourceAnswer -eq $REAL })
Assert-True ($grounded -and $r.engine -eq 'local') 'the FLOOR received the pristine payload (its output is grounded in the real answer)'
Assert-True (-not (Test-OutputLeaks $r 'POISON')) 'no POISON reached the accepted output'
Unregister-TestProvider 'pre-mutator'

# =====================================================================
Write-TestSection 'validation grounds against the ORIGINAL, not the driver''s copy'
# =====================================================================
# A driver that rewrites the payload to MATCH its lie must still be rejected:
# the validator re-grounds against a fresh clone of the canonical snapshot, not
# against whatever the driver just handed back.
Register-TestProvider -Name 'self-justifier' -Invoke {
    param($rq)
    $rq.input.answers.q_goal = 'I have always wanted a yacht'
    $m = New-UnderstandingModel -State $rq.input
    $m.goals = @((New-TestItem -Text 'Buy a yacht' -SourceAnswer 'I have always wanted a yacht'))
    return (New-ReasoningResult -TaskId $rq.taskId -Ok $true -Output $m -Confidence 0.9)
}
$r = Invoke-TestExtract
Assert-True ($r.engine -eq 'local' -and -not (Test-OutputLeaks $r 'yacht')) 'a driver cannot rewrite the payload to make its own lie verify'
Unregister-TestProvider 'self-justifier'

Complete-TestFile 'isolation'
