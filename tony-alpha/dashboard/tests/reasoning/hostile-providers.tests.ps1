# =====================================================================
# hostile-providers.tests.ps1 - THE PERMANENT HOSTILE-PROVIDER BATTERY
# ---------------------------------------------------------------------
# Every provider archetype that has ever defeated or challenged the Executive
# Reasoning Layer lives here forever. Three of them (edited-abuser,
# gate-switcher, context-mutator) were live bypasses found by CTO review, not
# hypotheticals - each one accepted a fabrication before it was fixed.
#
# This file is the canonical list. If an archetype is not here, it is not
# protected. When a new archetype defeats the kernel, it gets added here in the
# same commit that fixes it - the fix and its proof ship together.
#
# The kernel's promise is about OUTPUT, not containment: drivers are trusted
# in-process PowerShell and are NOT sandboxed. These tests prove that a hostile
# driver cannot get a lie ACCEPTED, cannot poison anyone else's view of the
# request, and cannot stop the floor from answering.
# =====================================================================

. (Join-Path $PSScriptRoot '_harness.ps1')
Assert-Sandboxed

$REAL = $script:TestGoalAnswer

# =====================================================================
Write-TestSection 'Archetype 1-2: throwing provider / null provider'
# =====================================================================
Register-TestProvider -Name 'thrower' -Invoke { param($rq) throw 'boom' }
$r = Invoke-TestExtract
Assert-True ($r.ok -and $r.engine -eq 'local') ("throwing provider: no exception escapes, floor answered (engine={0})" -f $r.engine)
Assert-True ($r.degraded) 'throwing provider: result is honestly marked degraded'
Unregister-TestProvider 'thrower'

Register-TestProvider -Name 'nuller' -Invoke { param($rq) return $null }
$r = Invoke-TestExtract
Assert-True ($r.ok -and $r.engine -eq 'local') ("null provider: floor answered (engine={0})" -f $r.engine)
Unregister-TestProvider 'nuller'

# =====================================================================
Write-TestSection 'Archetype 3: unsupported-task provider (never consulted)'
# =====================================================================
# Claims only lifeos.reason, then would return junk. Asked for understanding.extract
# it must never be invoked at all - and the floor answering is NOT a degrade,
# because nothing was actually tried.
Register-TestProvider -Name 'offtopic' -Supports { param($t) $t -eq 'lifeos.reason' } -Invoke {
    param($rq) return (New-ReasoningResult -TaskId $rq.taskId -Ok $true -Output ([pscustomobject]@{ junk = 1 }) -Confidence 0.9)
}
$r = Invoke-TestExtract
Assert-True ($r.engine -eq 'local' -and -not $r.degraded) ("unsupported-task provider not consulted; floor served, not degraded (engine={0}, degraded={1})" -f $r.engine, $r.degraded)
Unregister-TestProvider 'offtopic'

# An accelerator that is registered but reports itself unavailable is skipped
# silently - the right answer for a structured task is the engine's real output.
Register-TestProvider -Name 'offline-model' -Supports { param($t) $true } -IsAvailable { $false } -Invoke {
    param($rq) return (New-ReasoningResult -TaskId $rq.taskId -Ok $true -Output ([pscustomobject]@{}) -Confidence 0.9)
}
$r = Invoke-TestExtract
Assert-True ($r.engine -eq 'local' -and -not $r.degraded) 'unavailable provider never invoked; floor served, not degraded'
Unregister-TestProvider 'offline-model'

# A driver whose capability probes themselves throw is simply not a candidate.
Register-TestProvider -Name 'badprobe' -Supports { param($t) throw 'nope' } -IsAvailable { throw 'nope' } -Invoke { param($rq) throw 'nope' }
$r = Invoke-TestExtract
Assert-True ($r.ok -and $r.engine -eq 'local') 'provider with throwing capability probes is not a candidate; floor answered'
Unregister-TestProvider 'badprobe'

# =====================================================================
Write-TestSection 'Archetype 4: claims-everything / greedy provider'
# =====================================================================
Register-TestProvider -Name 'greedy' -Supports { param($t) $true } -Invoke {
    param($rq) return (New-ReasoningResult -TaskId $rq.taskId -Ok $true -Output ([pscustomobject]@{ junk = 'not a real anything' }) -Confidence 0.99)
}
$escaped = @()
foreach ($t in @('goals.refine', 'briefing.compose', 'capture.classify', 'inbox.propose', 'lifeos.reason', 'coaching.advise')) {
    $rr = Invoke-ReasoningTask -TaskId $t -Payload ([pscustomobject]@{ x = 1 })
    if ($rr.ok -or $rr.engine -eq 'greedy') { $escaped += $t }
}
Assert-True ($escaped.Count -eq 0) ("greedy provider: all 6 unmigrated tasks fail closed (escaped={0})" -f $escaped.Count)
$r = Invoke-TestExtract
Assert-True ($r.ok -and $r.engine -eq 'local') 'greedy provider: junk rejected on the migrated task too; floor served'
Unregister-TestProvider 'greedy'

# =====================================================================
Write-TestSection 'Archetype 5-6: malformed result / missing required fields'
# =====================================================================
Register-TestProvider -Name 'malformed' -Invoke {
    param($rq) return (New-ReasoningResult -TaskId $rq.taskId -Ok $true -Output ([pscustomobject]@{ nonsense = $true }) -Confidence 0.9)
}
$r = Invoke-TestExtract
Assert-True ($r.engine -eq 'local' -and @($r.output.goals).Count -gt 0) 'malformed model (no sections) rejected; floor answered'
Unregister-TestProvider 'malformed'

# Not even a ReasoningResult - a bare object with none of the contract fields.
Register-TestProvider -Name 'fieldless' -Invoke { param($rq) return ([pscustomobject]@{ whatever = 1 }) }
$r = Invoke-TestExtract
Assert-True ($r.ok -and $r.engine -eq 'local') 'missing required fields (non-contract object) rejected; floor answered'
Unregister-TestProvider 'fieldless'

# Structurally plausible but semantically empty: right shape, no grounding.
Register-TestProvider -Name 'wellformed-empty' -Invoke {
    param($rq) return (New-ReasoningResult -TaskId $rq.taskId -Ok $true -Output ([pscustomobject]@{ goals = @(); meta = [pscustomobject]@{ v = 1 }; summary = 'plausible' }) -Confidence 0.9)
}
$r = Invoke-TestExtract
Assert-True ($r.engine -eq 'local') 'well-formed-but-sectionless model rejected; floor answered'
Unregister-TestProvider 'wellformed-empty'

# =====================================================================
Write-TestSection 'Archetype 7-12: the liars (fabrication with a real citation)'
# =====================================================================
# Epic 13A philosophy: the MACHINE validates FACTS, the HUMAN validates MEANING.
# Each returns a structurally perfect model whose ONE goal is crafted. The gate
# rejects fabricated FACTS (numbers, dates, currency, proper nouns) and the
# zero-overlap absurdity floor, while ACCEPTING honest semantic compression - the
# review screen is where wording is judged. A gate that rejects paraphrase is just
# a reject-everything stub; a gate that accepts fabricated facts is a liar.
$liars = @(
    # fabricated FACTS -> machine rejects
    @{ n = 'fabricated sourceAnswer (cites words never said)'; i = (New-TestItem -Text 'Hit 500 policies by summer' -SourceAnswer 'I have always wanted a yacht'); pass = $false }
    @{ n = 'fabricated number'; i = (New-TestItem -Text 'Save $999,999 this year'); pass = $false }
    @{ n = 'fabricated person'; i = (New-TestItem -Text 'Meet Sarah Thompson weekly'); pass = $false }
    @{ n = 'fabricated company'; i = (New-TestItem -Text 'Sign the Acme Corporation deal'); pass = $false }
    @{ n = 'fabricated city'; i = (New-TestItem -Text 'Grow policies in Chicago'); pass = $false }
    @{ n = 'fabricated date'; i = (New-TestItem -Text 'Finish by 11:45pm on December 25'); pass = $false }
    @{ n = 'absurdity: unrelated + real citation'; i = (New-TestItem -Text 'Buy a yacht in Monaco'); pass = $false }
    # honest MEANING -> machine accepts, human judges
    @{ n = 'semantic compression (evenings at home) MUST PASS'; i = (New-TestItem -Text 'Protect evenings at home' -SourceAnswer 'Home by six' -SourceQuestionId 'q_week'); pass = $true }
    @{ n = 'valid paraphrase (MUST PASS)'; i = (New-TestItem -Text 'Reach 500 policies before the summer'); pass = $true }
    @{ n = 'multi-number grounded (MUST PASS)'; i = (New-TestItem -Text 'Save $12,500 at 7.5% by 6:30am'); pass = $true }
)
foreach ($c in $liars) {
    Register-CraftingProvider -Name 'liar' -Goals @($c.i)
    $r = Invoke-TestExtract
    $accepted = ($r.engine -eq 'liar')
    Assert-True ($accepted -eq $c.pass) ("{0}: {1}" -f $c.n, $(if ($accepted) { 'accepted' } else { 'rejected' }))
    Unregister-TestProvider 'liar'
}

# whole-result rejection: one bad item among good ones kills the ENTIRE result.
# No partial merge - a half-trusted result is not a thing.
Register-CraftingProvider -Name 'one-bad-apple' -Goals @((New-TestItem -Text 'Hit 500 policies by summer'), (New-TestItem -Text 'Buy a yacht'))
$r = Invoke-TestExtract
Assert-True ($r.engine -eq 'local' -and -not (Test-OutputLeaks $r 'yacht')) 'one bad item rejects the WHOLE result - no partial merge'
Unregister-TestProvider 'one-bad-apple'

# =====================================================================
Write-TestSection 'Archetype 13: edited-abuser (a provider cannot forge edited=true)'
# =====================================================================
# THE BYPASS: 'edited' means "the user typed this themselves", so edited items
# were exempt from grounding. A provider could stamp edited=true on a fabrication
# and skip the entire gate. Now edited=true in PROVIDER output is illegitimate by
# construction and rejects the whole result.
Register-CraftingProvider -Name 'edited-abuser' -Goals @((New-TestItem -Text 'Buy a yacht in Monaco' -SourceAnswer 'never said this' -Edited $true))
$r = Invoke-TestExtract
Assert-True ((-not (Test-OutputLeaks $r 'yacht')) -and $r.engine -eq 'local') ("edited-abuser: edited=true + fabricated goal REJECTED (engine={0})" -f $r.engine)
Unregister-TestProvider 'edited-abuser'

# edited=true on an otherwise PERFECTLY grounded item must ALSO be rejected -
# the flag itself is the violation, not the content.
Register-CraftingProvider -Name 'edited-abuser' -Goals @((New-TestItem -Text 'Hit 500 policies by summer' -Edited $true))
$r = Invoke-TestExtract
Assert-True ($r.engine -eq 'local') ("edited-abuser: edited=true + VALID grounded goal also REJECTED (engine={0})" -f $r.engine)
Unregister-TestProvider 'edited-abuser'

# ...and the SAME item with edited=false passes. This is the control that proves
# we rejected the forged flag, not the content.
Register-CraftingProvider -Name 'edited-abuser' -Goals @((New-TestItem -Text 'Hit 500 policies by summer' -Edited $false))
$r = Invoke-TestExtract
Assert-True ($r.engine -eq 'edited-abuser') ("edited-abuser: same item with edited=false ACCEPTED (engine={0})" -f $r.engine)
Unregister-TestProvider 'edited-abuser'

# =====================================================================
Write-TestSection 'Archetype 14: gate-switcher (constraints are not a provider input)'
# =====================================================================
# THE BYPASS: constraints were passed by reference, so a driver could set
# requireGrounding=$false on the shared object and the validator - reading that
# same object moments later - would switch its own gate off.
$switches = @(
    @{ n = 'sets requireGrounding=$false'; m = { param($rq) $rq.constraints.requireGrounding = $false } }
    @{ n = 'removes requireGrounding'; m = { param($rq) $rq.constraints.PSObject.Properties.Remove('requireGrounding') } }
    @{ n = 'replaces the whole constraints object'; m = { param($rq) $rq.constraints = [pscustomobject]@{ maxMs = 1; requireGrounding = $false } } }
)
foreach ($x in $switches) {
    $script:Switch = $x.m
    Register-TestProvider -Name 'gate-switcher' -Invoke {
        param($rq)
        & $script:Switch $rq
        $m = New-UnderstandingModel -State $rq.input
        $m.goals = @((New-TestItem -Text 'Buy a yacht in Monaco'))
        return (New-ReasoningResult -TaskId $rq.taskId -Ok $true -Output $m -Confidence 0.9)
    }
    $r = Invoke-TestExtract
    Assert-True ((-not (Test-OutputLeaks $r 'yacht')) -and $r.engine -eq 'local') ("gate-switcher {0}: fabrication REJECTED (engine={1})" -f $x.n, $r.engine)
    Unregister-TestProvider 'gate-switcher'
}

# The caller's own constraints object must survive a mutating provider untouched.
$req = New-ReasoningRequest -TaskId 'understanding.extract' -Payload (New-TestState)
$before = ConvertTo-Snapshot $req.constraints
Register-TestProvider -Name 'gs-caller' -Invoke { param($rq) $rq.constraints.requireGrounding = $false; $rq.constraints.maxMs = 1; return $null }
[void](Invoke-Reasoning -Request $req)
Assert-True (((ConvertTo-Snapshot $req.constraints) -eq $before) -and $req.constraints.requireGrounding) "gate-switcher: caller's CONSTRAINTS byte-identical after a mutating provider"
Unregister-TestProvider 'gs-caller'

# =====================================================================
Write-TestSection 'Archetype 15: context-mutator (the caller''s context is not shared)'
# =====================================================================
$ctx = New-TestContext
$ctxBefore = ConvertTo-Snapshot $ctx
Register-TestProvider -Name 'context-mutator' -Invoke {
    param($rq)
    if ($rq.context) { $rq.context.note = 'POISON'; $rq.context.nested.deep = 'POISON' }
    return $null
}
$r = Invoke-Reasoning -Request (New-ReasoningRequest -TaskId 'understanding.extract' -Payload (New-TestState) -Context $ctx)
Assert-True ((ConvertTo-Snapshot $ctx) -eq $ctxBefore) ("context-mutator: caller's CONTEXT byte-identical (note='{0}', nested='{1}')" -f $ctx.note, $ctx.nested.deep)
Assert-True ($r.ok -and $r.engine -eq 'local') 'context-mutator: floor still served cleanly'
Unregister-TestProvider 'context-mutator'

# =====================================================================
Write-TestSection 'Archetype 16-17: nested payload mutator / array clearer'
# =====================================================================
$state = New-TestState
$stateBefore = ConvertTo-Snapshot $state
Register-TestProvider -Name 'nested-mutator' -Invoke {
    param($rq)
    $rq.input.answers.q_goal = 'POISON'
    $rq.input.answers.q_boundaries = 'POISON'
    $rq.input.currentStep = 999
    return $null
}
$r = Invoke-TestExtract $state
Assert-True ((ConvertTo-Snapshot $state) -eq $stateBefore) "nested payload mutator: caller's nested answers byte-identical"
Assert-True ($r.ok -and $r.engine -eq 'local' -and -not (Test-OutputLeaks $r 'POISON')) 'nested payload mutator: floor output clean, no POISON'
Unregister-TestProvider 'nested-mutator'

# array clearer: empties an array inside the context. PowerShell unwraps arrays
# in ways that have bitten this kernel before, so the array case is its own test.
$ctx2 = New-TestContext
$ctx2Before = ConvertTo-Snapshot $ctx2
Register-TestProvider -Name 'array-clearer' -Invoke {
    param($rq)
    if ($rq.context) { $rq.context.tags = @(); $rq.context.tags.Clear() 2>$null }
    return $null
}
$r = Invoke-Reasoning -Request (New-ReasoningRequest -TaskId 'understanding.extract' -Payload (New-TestState) -Context $ctx2)
Assert-True ((ConvertTo-Snapshot $ctx2) -eq $ctx2Before) ("array clearer: caller's context array intact (tags={0})" -f @($ctx2.tags).Count)
Assert-True (@($ctx2.tags).Count -eq 2) 'array clearer: the array still holds its 2 original entries'
Unregister-TestProvider 'array-clearer'

# =====================================================================
Write-TestSection 'Archetype 18-20: mutate-then-null / mutate-then-throw / mutate-then-valid-looking'
# =====================================================================
# A driver that mutates and THEN fails must not leave its poison behind for the
# floor. Mutation and failure are separate acts; neither excuses the other.
$mutators = @(
    @{ n = 'mutate-then-null'; inv = { param($rq) $rq.input.answers.q_goal = 'POISON'; $rq.constraints.requireGrounding = $false; return $null } }
    @{ n = 'mutate-then-throw'; inv = { param($rq) $rq.input.answers.q_goal = 'POISON'; $rq.constraints.requireGrounding = $false; throw 'die' } }
    @{ n = 'mutate-then-valid-looking result'; inv = {
            param($rq)
            $rq.input.answers.q_goal = 'POISON'
            $rq.constraints.requireGrounding = $false
            return (New-ReasoningResult -TaskId $rq.taskId -Ok $true -Output ([pscustomobject]@{ nonsense = 1 }) -Confidence 0.99)
        }
    }
)
foreach ($m in $mutators) {
    $s = New-TestState
    $sBefore = ConvertTo-Snapshot $s
    Register-TestProvider -Name 'mutator' -Invoke $m.inv
    $r = Invoke-TestExtract $s
    $grounded = [bool](@($r.output.goals) | Where-Object { $_.sourceAnswer -eq $REAL })
    Assert-True ($r.ok -and $r.engine -eq 'local' -and -not (Test-OutputLeaks $r 'POISON')) ("{0}: floor served clean output (engine={1})" -f $m.n, $r.engine)
    Assert-True ((ConvertTo-Snapshot $s) -eq $sBefore) ("{0}: caller's payload byte-identical" -f $m.n)
    Assert-True $grounded ("{0}: the FLOOR received the pristine payload (output grounded in the real answer)" -f $m.n)
    Unregister-TestProvider 'mutator'
}

# A LATER provider must see pristine everything, even after an earlier one
# mutated its own copy.
$ctx3 = New-TestContext
Register-TestProvider -Name 'first-mutator' -Priority 1 -Invoke {
    param($rq)
    $rq.constraints.requireGrounding = $false
    $rq.context.note = 'POISON'
    $rq.input.answers.q_goal = 'POISON'
    return $null
}
$script:Witnessed = $null
Register-TestProvider -Name 'witness' -Priority 2 -Invoke {
    param($rq)
    $script:Witnessed = [pscustomobject]@{ rg = $rq.constraints.requireGrounding; note = $rq.context.note; goal = $rq.input.answers.q_goal }
    return $null
}
[void](Invoke-Reasoning -Request (New-ReasoningRequest -TaskId 'understanding.extract' -Payload (New-TestState) -Context $ctx3))
Assert-True (($script:Witnessed.rg -eq $true) -and ($script:Witnessed.note -eq 'pristine') -and ($script:Witnessed.goal -eq $REAL)) ("LATER provider saw pristine constraints(rg={0}) + context('{1}') + payload" -f $script:Witnessed.rg, $script:Witnessed.note)
Unregister-TestProvider 'first-mutator'
Unregister-TestProvider 'witness'

# =====================================================================
Write-TestSection 'Archetype 21: excessive-result flood'
# =====================================================================
$flood = @()
1..201 | ForEach-Object { $flood += (New-TestItem -Text 'Hit 500 policies by summer') }
Register-CraftingProvider -Name 'flooder' -Goals $flood
$r = Invoke-TestExtract
Assert-True ($r.engine -eq 'local') ("excessive-result flood: 201 items REJECTED by the size cap (engine={0})" -f $r.engine)
Assert-True (@($r.output.goals).Count -lt 10) 'excessive-result flood: rejected outright, never truncated-and-passed'
Unregister-TestProvider 'flooder'

# =====================================================================
Write-TestSection 'Archetype 22: recursive provider'
# =====================================================================
$script:Depth = 0
Register-TestProvider -Name 'recursor' -Invoke { param($rq) $script:Depth++; return (Invoke-Reasoning -Request $rq) }
$r = Invoke-TestExtract
Assert-True ($script:Depth -le 8 -and $null -ne $r) ("recursive provider: unbounded recursion cut at depth {0}, no stack overflow" -f $script:Depth)
Unregister-TestProvider 'recursor'
$r = Invoke-TestExtract
Assert-True ($r.ok -and $r.engine -eq 'local') 'recursive provider: ordinary calls unaffected after the recursion storm'

# =====================================================================
Write-TestSection 'Archetype 23: the valid accelerator that MUST pass'
# =====================================================================
# Without this, every test above could be satisfied by a kernel that rejects
# everything. This is the one that proves the gate is a gate, not a wall.
Register-TestProvider -Name 'honest-accel' -Invoke {
    param($rq) return (New-ReasoningResult -TaskId $rq.taskId -Ok $true -Output (New-UnderstandingModel -State $rq.input) -Confidence 0.9)
}
$r = Invoke-TestExtract
Assert-True ($r.engine -eq 'honest-accel' -and -not $r.degraded) ("valid accelerator IS used and attributed to it (engine={0}, degraded={1})" -f $r.engine, $r.degraded)
Assert-True ($r.ok -and @($r.output.goals).Count -gt 0) 'valid accelerator: real output delivered'
Unregister-TestProvider 'honest-accel'

# =====================================================================
Write-TestSection 'the floor is unchanged by all of the above'
# =====================================================================
$s = New-TestState
$direct = New-UnderstandingModel -State $s
$via = (Invoke-TestExtract $s).output
Assert-True ((ConvertTo-NormalizedModel $direct) -eq (ConvertTo-NormalizedModel $via)) 'BYTE-IDENTICAL floor output through the kernel vs called directly'
$r = Invoke-TestExtract
Assert-True ($r.ok -and $r.engine -eq 'local' -and @($r.output.goals).Count -gt 0) 'floor output still passes the floor''s own gate (no privileged path)'

Complete-TestFile 'hostile-providers'
