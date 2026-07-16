# =====================================================================
# limits.tests.ps1 - re-entrancy and the result-size cap
# ---------------------------------------------------------------------
# Two bounded resources: stack depth and result size. Both fail LOUDLY and
# WHOLLY - a truncated result pretending to be complete would be a quiet lie,
# and a driver that recurses forever would take the UI thread with it.
# =====================================================================

. (Join-Path $PSScriptRoot '_harness.ps1')
Assert-Sandboxed

$REAL = $script:TestGoalAnswer

# =====================================================================
Write-TestSection 're-entrancy guard'
# =====================================================================
$script:Depth = 0
Register-TestProvider -Name 'inf-recursor' -Invoke {
    param($rq)
    $script:Depth++
    return (Invoke-Reasoning -Request $rq)   # UNBOUNDED recursion, on purpose
}
$r = Invoke-TestExtract
Assert-True ($script:Depth -le 8) ("unbounded recursion is cut at the depth limit (re-entered {0}x)" -f $script:Depth)
Assert-True ($null -ne $r) 'the recursion storm still produces a result object rather than a stack overflow'
Unregister-TestProvider 'inf-recursor'

# the guard must RESET - a depth counter that leaks would break every later call
$r = Invoke-TestExtract
Assert-True ($r.ok -and $r.engine -eq 'local') 'ordinary calls are unaffected after the recursion storm (the guard resets)'
$r = Invoke-TestExtract
Assert-True ($r.ok -and $r.engine -eq 'local') 'and again - the depth counter did not leak'

# a driver that recurses a FIXED, small number of times still gets a real answer
$script:Nested = 0
Register-TestProvider -Name 'polite-recursor' -Invoke {
    param($rq)
    $script:Nested++
    if ($script:Nested -le 2) { return (Invoke-Reasoning -Request $rq) }
    return (New-ReasoningResult -TaskId $rq.taskId -Ok $true -Output (New-UnderstandingModel -State $rq.input) -Confidence 0.9)
}
$r = Invoke-TestExtract
Assert-True ($null -ne $r -and $r.ok) 'a shallow, terminating re-entrant driver is not punished'
Unregister-TestProvider 'polite-recursor'

# =====================================================================
Write-TestSection 'result-size cap'
# =====================================================================
Assert-True ((Get-UEMaxExtractItems) -eq 200) ("the cap is documented and queryable (Get-UEMaxExtractItems = {0})" -f (Get-UEMaxExtractItems))

# just under the cap: a large-but-legal result is ACCEPTED. Without this, the cap
# test would pass on a kernel that rejects everything.
$cap = Get-UEMaxExtractItems
$under = @()
1..($cap - 15) | ForEach-Object { $under += (New-TestItem -Text 'Hit 500 policies by summer') }
$script:CraftedGoals = $under
Register-CraftingProvider -Name 'under-cap'
$r = Invoke-TestExtract
Assert-True ($r.engine -eq 'under-cap') ("{0} grounded items (under the cap) are ACCEPTED (engine={1})" -f $under.Count, $r.engine)
Unregister-TestProvider 'under-cap'

# one over the cap: REJECTED
$over = @()
1..($cap + 1) | ForEach-Object { $over += (New-TestItem -Text 'Hit 500 policies by summer') }
$script:CraftedGoals = $over
Register-CraftingProvider -Name 'over-cap'
$r = Invoke-TestExtract
Assert-True ($r.engine -eq 'local') ("{0} items (one over the cap) are REJECTED (engine={1})" -f $over.Count, $r.engine)
Assert-True (@($r.output.goals).Count -lt 10) 'the over-cap result is rejected WHOLE - never truncated and passed off as complete'
Unregister-TestProvider 'over-cap'

# a massive flood is rejected quickly and without exhausting anything
$flood = @()
1..5000 | ForEach-Object { $flood += (New-TestItem -Text 'Hit 500 policies by summer') }
$script:CraftedGoals = $flood
Register-CraftingProvider -Name 'flooder'
$sw = [Diagnostics.Stopwatch]::StartNew()
$r = Invoke-TestExtract
$sw.Stop()
Assert-True ($r.engine -eq 'local') ("a 5,000-item flood is REJECTED (engine={0}, {1}ms)" -f $r.engine, $sw.ElapsedMilliseconds)
Assert-True ($r.ok) 'after rejecting the flood, the floor still answers'
Unregister-TestProvider 'flooder'

# the cap counts items across ALL sections, not just goals
$m = New-UnderstandingModel -State (New-TestState)
$spread = @()
1..70 | ForEach-Object { $spread += (New-TestItem -Text 'Family' -SourceAnswer 'Family, health, and the agency' -SourceQuestionId 'q_areas') }
$m.goals = $spread; $m.values = $spread; $m.priorities = $spread   # 210 total, each section under 200
$v = Test-ReasoningOutput -TaskId 'understanding.extract' `
    -Result (New-ReasoningResult -TaskId 'understanding.extract' -Ok $true -Output $m -Confidence 0.9) `
    -Request (New-ReasoningRequest -TaskId 'understanding.extract' -Payload (New-TestState))
Assert-True (-not $v.valid) ("the cap counts items across ALL sections, not per-section (210 spread over 3 sections -> {0})" -f $v.reason)

Complete-TestFile 'limits'
