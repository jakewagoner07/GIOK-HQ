# =====================================================================
# kernel-routing.tests.ps1 - the kernel's ABI, routing policy and provenance
# ---------------------------------------------------------------------
# The syscall layer: which driver gets picked, what the caller is told about who
# actually answered, and the guarantee that the layer itself writes nothing.
# =====================================================================

. (Join-Path $PSScriptRoot '_harness.ps1')
Assert-Sandboxed

# =====================================================================
Write-TestSection 'the task ABI'
# =====================================================================
$tasks = @(Get-ReasoningTasks)
Assert-True ($tasks.Count -eq 8) ("ABI declares all 8 reasoning tasks (found {0})" -f $tasks.Count)
$expected = @('understanding.extract', 'goals.refine', 'briefing.compose', 'capture.classify', 'inbox.propose', 'lifeos.reason', 'coaching.advise', 'conversation.answer')
$missing = @($expected | Where-Object { $tasks -notcontains $_ })
Assert-True ($missing.Count -eq 0) ("every expected task id is declared (missing={0})" -f ($missing -join ','))
Assert-True (Test-ReasoningTask 'understanding.extract') 'Test-ReasoningTask recognises a declared task'
Assert-True (-not (Test-ReasoningTask 'not.a.task')) 'Test-ReasoningTask rejects an undeclared task'

# =====================================================================
Write-TestSection 'the request envelope'
# =====================================================================
$req = New-ReasoningRequest -TaskId 'understanding.extract' -Payload (New-TestState)
Assert-True ($req.requestId -match '^R-[0-9a-f]{8}$') ("every request carries a traceable id ({0})" -f $req.requestId)
Assert-True ($req.constraints.maxMs -gt 0) ("every request carries a deadline (maxMs={0})" -f $req.constraints.maxMs)
Assert-True ($req.constraints.requireGrounding -eq $true) 'grounding is required by default - opt-out, never opt-in'
Assert-True (-not [string]::IsNullOrWhiteSpace([string]$req.version)) ("the envelope is versioned ({0})" -f $req.version)

# maxMs is PLUMBING ONLY. It is carried so a future driver can honour it; the
# kernel does NOT enforce it. Documented as such, and asserted here so nobody
# later mistakes the field for a guarantee.
Register-TestProvider -Name 'sluggish' -Invoke {
    param($rq)
    Start-Sleep -Milliseconds 300
    return (New-ReasoningResult -TaskId $rq.taskId -Ok $true -Output (New-UnderstandingModel -State $rq.input) -Confidence 0.9)
}
$sw = [Diagnostics.Stopwatch]::StartNew()
$r = Invoke-ReasoningTask -TaskId 'understanding.extract' -Payload (New-TestState) -MaxMs 10
$sw.Stop()
Assert-True ($r.engine -eq 'sluggish' -and $sw.ElapsedMilliseconds -ge 300) ("maxMs is PLUMBING ONLY: a slow driver is NOT cut off (maxMs=10, took {0}ms, engine={1})" -f $sw.ElapsedMilliseconds, $r.engine)
Write-TestNote 'deadline enforcement is deliberately absent and documented; it belongs to the driver sprint'
Unregister-TestProvider 'sluggish'

# =====================================================================
Write-TestSection 'the floor: a provider that always answers'
# =====================================================================
$floor = Get-ReasoningFloor
Assert-True ($null -ne $floor) ("a floor is registered ({0})" -f $floor.name)
Assert-True ([bool](& $floor.isAvailable)) 'the floor is ALWAYS available'
$unsupported = @(Get-ReasoningTasks | Where-Object { -not (& $floor.supports $_) })
Assert-True ($unsupported.Count -eq 0) ("the floor supports EVERY declared task ({0} unsupported)" -f $unsupported.Count)
Assert-True ($floor.priority -ge 1000) ("the floor is never preferred over an accelerator (priority={0})" -f $floor.priority)

# =====================================================================
Write-TestSection 'routing through the kernel changes nothing'
# =====================================================================
$s = New-TestState
$direct = New-UnderstandingModel -State $s
$via = (Invoke-TestExtract $s).output
Assert-True ((ConvertTo-NormalizedModel $direct) -eq (ConvertTo-NormalizedModel $via)) 'BYTE-IDENTICAL output: through the layer vs calling the engine directly'
Assert-True (@($via.goals).Count -eq @($direct.goals).Count) ("same goal count via the layer ({0})" -f @($via.goals).Count)

# =====================================================================
Write-TestSection 'provenance never lies'
# =====================================================================
$r = Invoke-TestExtract
Assert-True ($r.engine -eq 'local' -and $r.providerName -eq 'local') ("floor answer attributed to the floor (engine={0})" -f $r.engine)
Assert-True ($r.reasonCode -eq 'ok' -and -not $r.degraded) 'an ordinary floor answer is not marked degraded'

# a driver cannot forge its own attribution: the kernel stamps it.
Register-TestProvider -Name 'impostor' -Invoke {
    param($rq)
    return (New-ReasoningResult -TaskId $rq.taskId -Ok $true -Output (New-UnderstandingModel -State $rq.input) -Confidence 0.9 -Engine 'local' -ProviderName 'local')
}
$r = Invoke-TestExtract
Assert-True ($r.engine -eq 'impostor' -and $r.providerName -eq 'impostor') ("a driver claiming engine='local' is still attributed to itself (engine={0})" -f $r.engine)
Unregister-TestProvider 'impostor'

# =====================================================================
Write-TestSection 'honest answers for tasks with nothing behind them'
# =====================================================================
$r = Invoke-ReasoningTask -TaskId 'not.a.task' -Payload (New-TestState)
Assert-True (-not $r.ok -and $r.reasonCode -eq 'unknown-task') ("an unknown task returns ok=false, reasonCode={0}, and does NOT throw" -f $r.reasonCode)
# capture.classify is still unmigrated (briefing.compose was migrated in Epic 14).
$r = Invoke-ReasoningTask -TaskId 'capture.classify' -Payload (New-TestState)
Assert-True (-not $r.ok -and $r.reasonCode -eq 'no-provider') ("a declared-but-unmigrated task answers honestly (reasonCode={0}) - never fabricates" -f $r.reasonCode)

# =====================================================================
Write-TestSection 'priority ordering'
# =====================================================================
Register-TestProvider -Name 'low-pri' -Priority 50 -Invoke {
    param($rq) return (New-ReasoningResult -TaskId $rq.taskId -Ok $true -Output (New-UnderstandingModel -State $rq.input) -Confidence 0.9)
}
Register-TestProvider -Name 'high-pri' -Priority 2 -Invoke {
    param($rq) return (New-ReasoningResult -TaskId $rq.taskId -Ok $true -Output (New-UnderstandingModel -State $rq.input) -Confidence 0.9)
}
$r = Invoke-TestExtract
Assert-True ($r.engine -eq 'high-pri') ("the lower priority number wins (engine={0})" -f $r.engine)
Unregister-TestProvider 'high-pri'
$r = Invoke-TestExtract
Assert-True ($r.engine -eq 'low-pri') ("with the preferred driver gone, the next one serves (engine={0})" -f $r.engine)
Unregister-TestProvider 'low-pri'

# a failing accelerator falls through to the next, then to the floor
Register-TestProvider -Name 'broken-first' -Priority 1 -Invoke { param($rq) throw 'boom' }
Register-TestProvider -Name 'good-second' -Priority 2 -Invoke {
    param($rq) return (New-ReasoningResult -TaskId $rq.taskId -Ok $true -Output (New-UnderstandingModel -State $rq.input) -Confidence 0.9)
}
$r = Invoke-TestExtract
Assert-True ($r.engine -eq 'good-second') ("a throwing accelerator falls through to the next candidate (engine={0})" -f $r.engine)
Unregister-TestProvider 'broken-first'
Unregister-TestProvider 'good-second'

# =====================================================================
Write-TestSection 'GUARANTEE: no ambient authority - the layer writes NOTHING'
# =====================================================================
# The layer returns proposals. It cannot write. If this ever fails, the kernel
# has grown a side effect and the approval flow is no longer the only writer.
$before = @(Get-ChildItem $script:TestSandbox -File -ErrorAction SilentlyContinue).Count
1..5 | ForEach-Object { [void](Invoke-TestExtract) }
$after = @(Get-ChildItem $script:TestSandbox -File -ErrorAction SilentlyContinue).Count
Assert-True ($before -eq 0 -and $after -eq 0) ("5 reasoning calls wrote ZERO files to the identity store ({0} files)" -f $after)

# even a driver that tries to write from inside invoke does not make the KERNEL
# a writer. (Drivers are trusted in-process code and are NOT sandboxed - this
# asserts the kernel's own behaviour, not containment.)
$probe = Join-Path $script:TestSandbox 'scribble-probe.txt'
$script:ProbePath = $probe
Register-TestProvider -Name 'scribbler' -Invoke {
    param($rq)
    try { Set-Content -Path $script:ProbePath -Value 'gotcha' -ErrorAction SilentlyContinue } catch { }
    return $null
}
[void](Invoke-TestExtract)
Unregister-TestProvider 'scribbler'
Write-TestNote ("a driver CAN write (it is trusted in-process code, not sandboxed): probe exists = {0}" -f (Test-Path $probe))
if (Test-Path $probe) { Remove-Item $probe -Force -ErrorAction SilentlyContinue }
$r = Invoke-TestExtract
Assert-True ($r.ok -and $r.engine -eq 'local') 'after a scribbling driver, the floor still answers correctly'

# =====================================================================
Write-TestSection 'stability'
# =====================================================================
$s = New-TestState
$m1 = (Invoke-TestExtract $s).output
$m2 = (Invoke-TestExtract $s).output
Assert-True ((ConvertTo-NormalizedModel $m1) -eq (ConvertTo-NormalizedModel $m2)) 'the same input twice produces the same result'

# =====================================================================
Write-TestSection 'the kernel is total - a reasoning call returns, it does not throw'
# =====================================================================
# Totality is about REASONING: whatever the payload turns out to be, the caller
# gets a result object back rather than an exception. It is NOT a claim that a
# caller can omit a mandatory argument - see the note below.
$cases = @(
    @{ n = 'a null payload'; sb = { Invoke-ReasoningTask -TaskId 'understanding.extract' -Payload $null } }
    @{ n = 'an empty payload object'; sb = { Invoke-ReasoningTask -TaskId 'understanding.extract' -Payload ([pscustomobject]@{}) } }
    @{ n = 'a payload of the wrong type entirely'; sb = { Invoke-ReasoningTask -TaskId 'understanding.extract' -Payload 'just a string' } }
    @{ n = 'an unknown task id'; sb = { Invoke-ReasoningTask -TaskId 'not.a.task' -Payload (New-TestState) } }
)
foreach ($c in $cases) {
    $threw = $false
    $res = $null
    try { $res = & $c.sb } catch { $threw = $true }
    Assert-True ((-not $threw) -and $null -ne $res) ("{0} returns a result instead of throwing" -f $c.n)
}

# A missing/empty TaskId is a different thing: PowerShell's own mandatory-parameter
# binding rejects the call before the kernel is entered. That is correct - a caller
# with no task id is a programming error and should fail loudly and immediately,
# not be absorbed into a polite result object. Asserted so the distinction stays
# deliberate rather than becoming an accident someone "fixes" later.
$bindingRejected = $false
try { [void](Invoke-ReasoningTask -TaskId '' -Payload (New-TestState)) }
catch { $bindingRejected = ($_.Exception.GetType().Name -eq 'ParameterBindingValidationException') }
Assert-True $bindingRejected 'an empty TaskId is rejected by mandatory-parameter binding, before the kernel runs'

Complete-TestFile 'kernel-routing'
