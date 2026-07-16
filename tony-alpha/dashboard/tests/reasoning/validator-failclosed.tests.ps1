# =====================================================================
# validator-failclosed.tests.ps1 - the privilege boundary
# ---------------------------------------------------------------------
# Validators are the MMU: nothing reaches a caller without passing one, and a
# validator that CANNOT verify must REJECT. "I couldn't check" is not "it's fine".
#
# This distinction is not academic. The first version of the grounding gate
# guarded its check with `if ($state ...)`, so when the payload failed to arrive
# the check was silently skipped and a fabricated goal sailed through. The gate
# failed OPEN. Everything here exists to keep that from coming back.
# =====================================================================

. (Join-Path $PSScriptRoot '_harness.ps1')
Assert-Sandboxed

$REAL = $script:TestGoalAnswer

# =====================================================================
Write-TestSection 'unmigrated tasks fail CLOSED (no engine behind them yet)'
# =====================================================================
# These six tasks are declared in the ABI but nothing implements them, so the
# kernel has no way to police an answer. No result is acceptable from ANY
# provider. The first version of this accepted any non-null output while its own
# comment claimed otherwise - code and comment now agree.
$unmigrated = @('goals.refine', 'briefing.compose', 'capture.classify', 'inbox.propose', 'lifeos.reason', 'coaching.advise')
foreach ($t in $unmigrated) {
    $r = Invoke-ReasoningTask -TaskId $t -Payload ([pscustomobject]@{ x = 1 })
    Assert-True (-not $r.ok -and $r.reasonCode -eq 'no-provider') ("{0}: fails closed with an honest reasonCode ({1})" -f $t, $r.reasonCode)
}

# ...and they stay closed even when a provider insists it can serve them.
Register-TestProvider -Name 'eager' -Supports { param($t) $true } -Invoke {
    param($rq) return (New-ReasoningResult -TaskId $rq.taskId -Ok $true -Output ([pscustomobject]@{ plausible = 'looking' }) -Confidence 0.99)
}
foreach ($t in $unmigrated) {
    $r = Invoke-ReasoningTask -TaskId $t -Payload ([pscustomobject]@{ x = 1 })
    Assert-True (-not ($r.ok -and $r.engine -eq 'eager')) ("{0}: a willing provider still cannot smuggle a result through" -f $t)
}
Unregister-TestProvider 'eager'

# =====================================================================
Write-TestSection 'the grounding gate cannot be skipped'
# =====================================================================
# The exact regression that once failed OPEN: no source state on the request.
# The validator must reject rather than wave the item through unverified.
$vResult = Test-ReasoningOutput -TaskId 'understanding.extract' `
    -Result (New-ReasoningResult -TaskId 'understanding.extract' -Ok $true -Output (New-UnderstandingModel -State (New-TestState)) -Confidence 0.9) `
    -Request ([pscustomobject]@{ taskId = 'understanding.extract'; input = $null; constraints = [pscustomobject]@{ requireGrounding = $true } })
Assert-True (-not $vResult.valid) ("no source state on the request -> REJECT, not skip (reason: {0})" -f $vResult.reason)

# =====================================================================
Write-TestSection 'structural validation'
# =====================================================================
$structural = @(
    @{ n = 'no output at all'; o = $null }
    @{ n = 'output missing every section'; o = ([pscustomobject]@{ nonsense = $true }) }
    @{ n = 'output missing meta'; o = ([pscustomobject]@{ goals = @(); values = @(); priorities = @(); challenges = @(); strengths = @(); boundaries = @() }) }
)
foreach ($c in $structural) {
    $v = Test-ReasoningOutput -TaskId 'understanding.extract' `
        -Result (New-ReasoningResult -TaskId 'understanding.extract' -Ok $true -Output $c.o -Confidence 0.9) `
        -Request (New-ReasoningRequest -TaskId 'understanding.extract' -Payload (New-TestState))
    Assert-True (-not $v.valid) ("{0}: rejected ({1})" -f $c.n, $v.reason)
}

# a section is missing exactly one of the six -> still rejected
foreach ($drop in @('goals', 'values', 'priorities', 'challenges', 'strengths', 'boundaries')) {
    $m = New-UnderstandingModel -State (New-TestState)
    $m.PSObject.Properties.Remove($drop)
    $v = Test-ReasoningOutput -TaskId 'understanding.extract' `
        -Result (New-ReasoningResult -TaskId 'understanding.extract' -Ok $true -Output $m -Confidence 0.9) `
        -Request (New-ReasoningRequest -TaskId 'understanding.extract' -Payload (New-TestState))
    Assert-True (-not $v.valid) ("a model missing the '{0}' section is rejected" -f $drop)
}

# =====================================================================
Write-TestSection 'item-level grounding rules'
# =====================================================================
# Each case is one crafted item in an otherwise real model. 'pass' encodes the
# rule: invention is rejected, honest restatement survives.
$items = @(
    @{ n = 'item with no text'; i = (New-TestItem -Text ''); pass = $false }
    @{ n = 'item with no sourceQuestionId'; i = (New-TestItem -Text 'Hit 500 policies by summer' -SourceQuestionId ''); pass = $false }
    @{ n = 'item citing a question that does not exist'; i = (New-TestItem -Text 'Hit 500 policies by summer' -SourceQuestionId 'q_nope'); pass = $false }
    @{ n = 'sourceAnswer not verbatim (one word changed)'; i = (New-TestItem -Text 'Hit 500 policies by summer' -SourceAnswer ($REAL -replace 'summer', 'winter')); pass = $false }
    @{ n = 'fabricated number riding a true citation'; i = (New-TestItem -Text 'Save $999,999 this year'); pass = $false }
    @{ n = 'number present but reformatted (12500 vs $12,500)'; i = (New-TestItem -Text 'Save 12500 dollars'); pass = $true }
    @{ n = 'percentage grounded in the answer'; i = (New-TestItem -Text 'Save at 7.5% consistently'); pass = $true }
    @{ n = 'time grounded in the answer'; i = (New-TestItem -Text 'Be ready for the 6:30am standup'); pass = $true }
    @{ n = 'text sharing nothing with the citation'; i = (New-TestItem -Text 'Buy a yacht'); pass = $false }
    @{ n = 'honest paraphrase'; i = (New-TestItem -Text 'Reach 500 policies before the summer'); pass = $true }
)
foreach ($c in $items) {
    $m = New-UnderstandingModel -State (New-TestState)
    $m.goals = @($c.i)
    $v = Test-ReasoningOutput -TaskId 'understanding.extract' `
        -Result (New-ReasoningResult -TaskId 'understanding.extract' -Ok $true -Output $m -Confidence 0.9) `
        -Request (New-ReasoningRequest -TaskId 'understanding.extract' -Payload (New-TestState))
    Assert-True ($v.valid -eq $c.pass) ("{0}: {1}" -f $c.n, $(if ($v.valid) { 'accepted' } else { ("rejected - " + $v.reason) }))
}

# =====================================================================
Write-TestSection 'the floor gets no privilege - it passes the SAME gate'
# =====================================================================
$m = New-UnderstandingModel -State (New-TestState)
$v = Test-ReasoningOutput -TaskId 'understanding.extract' `
    -Result (New-ReasoningResult -TaskId 'understanding.extract' -Ok $true -Output $m -Confidence 0.9 -Engine 'local' -ProviderName 'local') `
    -Request (New-ReasoningRequest -TaskId 'understanding.extract' -Payload (New-TestState))
Assert-True $v.valid 'the deterministic floor''s own output passes the same validator it enforces on others'

# =====================================================================
Write-TestSection 'documented, accepted behaviour (recorded, not gated)'
# =====================================================================
# Grounded duplicates under the cap DO pass the kernel. This is deliberate: the
# review screen is the dedup and consent point, not the validator. Recorded here
# so the behaviour is a decision, not a surprise.
$m = New-UnderstandingModel -State (New-TestState)
$dupes = @()
1..50 | ForEach-Object { $dupes += (New-TestItem -Text 'Hit 500 policies by summer') }
$m.goals = $dupes
$v = Test-ReasoningOutput -TaskId 'understanding.extract' `
    -Result (New-ReasoningResult -TaskId 'understanding.extract' -Ok $true -Output $m -Confidence 0.9) `
    -Request (New-ReasoningRequest -TaskId 'understanding.extract' -Payload (New-TestState))
Write-TestNote ("50 grounded duplicates under the cap: valid={0} (the REVIEW SCREEN is the dedup consent point)" -f $v.valid)

Complete-TestFile 'validator-failclosed'
