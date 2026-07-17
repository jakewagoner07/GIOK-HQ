# =====================================================================
# daily-plan.tests.ps1  -  the permanent Daily Executive Plan suite (Epic 14)
# ---------------------------------------------------------------------
# The Daily Plan is a READ-ONLY projection: it invents no facts and writes nothing;
# recommendations become PENDING Inbox proposals only on approval. These tests use
# MOCKED Claude responses and a sandboxed identity + inbox - no key, no network, no
# real data touched. Facts by machine; meaning by the human.
# =====================================================================

. (Join-Path $PSScriptRoot '_harness.ps1')
. (Resolve-Path (Join-Path $PSScriptRoot '..\..\core\reasoning-consent.ps1'))
. (Resolve-Path (Join-Path $PSScriptRoot '..\..\core\executive-inbox.ps1'))
. (Resolve-Path (Join-Path $PSScriptRoot '..\..\core\daily-plan.ps1'))
. (Resolve-Path (Join-Path $PSScriptRoot '..\..\core\reasoning-claude.ps1'))
Assert-Sandboxed

# sandbox the inbox too, so proposal tests never touch the real executive_inbox.json.
$script:PlanInboxPath = Join-Path $script:TestSandbox 'executive_inbox.json'
function Get-InboxPath { return $script:PlanInboxPath }

$REAL_GOAL = 'Hit 500 policies by summer and save $12,500 at 7.5%'

# a realistic Executive Context. calendar/email are pass-through (as in production).
function New-PlanContext {
    param([int]$CalCount = 2, [int]$FinDaysAway = 4, [bool]$FamilyToday = $true, [bool]$Empty = $false)
    if ($Empty) { return [pscustomobject]@{ generatedAt = '2026-07-16 09:00:00'; time = [pscustomobject]@{ date = '2026-07-16'; dayOfWeek = 'Thursday'; hour = 9; partOfDay = 'morning'; isWeekend = $false } } }
    $events = @(); 1..$CalCount | ForEach-Object { $events += [pscustomobject]@{ id = ("EV-$_"); title = ("Meeting $_"); start = '2026-07-16 10:00'; responseStatus = 'accepted' } }
    $fam = if ($FamilyToday) { @([pscustomobject]@{ id = 'FAM-001'; title = 'Daughter recital'; date = '2026-07-16'; daysAway = 0; kind = 'important-date' }) } else { @() }
    [pscustomobject]@{
        generatedAt = '2026-07-16 09:00:00'
        time        = [pscustomobject]@{ date = '2026-07-16'; dayOfWeek = 'Thursday'; hour = 9; partOfDay = 'morning'; isWeekend = $false }
        activeGoals = @([pscustomobject]@{ id = 'G-001'; title = 'Hit 500 policies by summer'; nextStep = 'Call 5 leads'; domain = 'agency'; targetDate = '2026-08-01' })
        calendar    = [pscustomobject]@{ todayCount = $CalCount; events = $events; conflicts = @(); insights = [pscustomobject]@{ today = [pscustomobject]@{ meetingHeavy = ($CalCount -ge 4); longestFreeBlock = [pscustomobject]@{ minutes = 90 } } } }
        email       = [pscustomobject]@{ summary = [pscustomobject]@{ attentionItems = @([pscustomobject]@{ messageId = 'M-1'; why = 'Client needs a quote reply'; subject = 'Quote?'; category = 'needs-reply'; from = 'jane' }) } }
        lifeDigest  = [pscustomobject]@{ family = [pscustomobject]@{ upcoming = $fam }; health = [pscustomobject]@{ items = @(); goals = @() }
            financial = [pscustomobject]@{ items = @([pscustomobject]@{ id = 'FN-001'; title = 'Pay quarterly taxes'; amount = '12500'; dueDate = '2026-07-20'; daysAway = $FinDaysAway; kind = 'obligation' }); goals = @() }; learning = [pscustomobject]@{ items = @(); goals = @() } }
        nonNegotiables = @([pscustomobject]@{ id = 'NN-001'; title = 'Sunday dinner with family' })
        inbox       = [pscustomobject]@{ pending = 1 }
        assessment  = [pscustomobject]@{ shouldClarify = [pscustomobject]@{ questions = @('Is the client review prepped?') }; conflict = [pscustomobject]@{ items = @() } }
    }
}
function Src { param($c) if (-not $c) { $c = New-PlanContext }; return (Get-DailyPlanSources -Context $c -Now ([datetime]'2026-07-16 09:00')) }
function PItem { param($t, $st, $sid, [bool]$appr = $false, $action = $null) @{ text = $t; sourceType = $st; sourceId = $sid; reason = 'r'; priority = 1; confidence = 0.9; requiresApproval = $appr; proposedAction = $action } }
function PlanJson {
    param($Top = @(), $Protect = @(), $Follow = @(), $Wait = @(), $Recs = @(), $Level = 'balanced')
    (@{ topOutcomes = @($Top); protect = @($Protect); followUps = @($Follow); canWait = @($Wait); recommendations = @($Recs); clarifications = @(); workload = @{ level = $Level; reason = 'x' } } | ConvertTo-Json -Depth 8)
}
function KV { param($model, $ps) (Test-ReasoningOutput -TaskId 'briefing.compose' -Result (New-ReasoningResult -TaskId 'briefing.compose' -Ok $true -Output $model -Confidence 0.8) -Request (New-ReasoningRequest -TaskId 'briefing.compose' -Payload $ps)).valid }

# =====================================================================
Write-TestSection 'local Daily Plan (the permanent floor)'
# =====================================================================
$ps = Src
$r = Invoke-ReasoningTask -TaskId 'briefing.compose' -Payload $ps
Assert-True ($r.ok -and $r.engine -eq 'local') 'local Daily Plan output through the kernel (floor)'
Assert-True ($r.providerName -eq 'local') 'LOCAL fallback attribution stamped by the kernel'
$plan = $r.output
Assert-True (@($plan.topOutcomes).Count -ge 1) 'topOutcomes present'
Assert-True ([bool](@($plan.protect) | Where-Object { $_.sourceType -eq 'life:family' })) 'FAMILY-BEFORE-FINANCIAL: family-today is in protect'
# family placed before financial in the plan ordering
$famPri = @(@($plan.protect) | Where-Object { $_.sourceType -eq 'life:family' })[0].priority
$finItem = @(@($plan.canWait) + @($plan.followUps) | Where-Object { $_.sourceType -eq 'life:financial' })
Assert-True ($famPri -le 2) 'family commitment ranked at the top priority'
Assert-True (@($plan.recommendations | Where-Object { $_.requiresApproval -and $_.proposedAction }).Count -ge 1) 'recommendations require approval + carry a proposedAction'
Assert-True (@($plan.recommendations | Where-Object { $_.requiresApproval -and -not $_.proposedAction }).Count -eq 0) 'no recommendation requires approval without a proposedAction'

# =====================================================================
Write-TestSection 'overload classification (evidence only)'
# =====================================================================
$light = Invoke-ReasoningTask -TaskId 'briefing.compose' -Payload (Src (New-PlanContext -CalCount 1 -FamilyToday $false))
Assert-True ($light.output.workload.level -eq 'light') 'a quiet day classifies as light'
$over = Invoke-ReasoningTask -TaskId 'briefing.compose' -Payload (Src (New-PlanContext -CalCount 6))
Assert-True ($over.output.workload.level -eq 'overloaded' -and $over.output.workload.reason -match 'scheduled commitment') 'six commitments -> overloaded, with the evidence stated'
Assert-True ($over.output.workload.reason -notmatch '(?i)burn|stress|depress|anxi') 'overload NEVER diagnoses a medical/mental condition'

# =====================================================================
Write-TestSection 'empty context'
# =====================================================================
$empty = Invoke-ReasoningTask -TaskId 'briefing.compose' -Payload (Src (New-PlanContext -Empty $true))
Assert-True ($empty.ok -and $empty.engine -eq 'local' -and $empty.output.workload.level -eq 'light') 'empty context -> calm light plan, no fabrication'
Assert-True (@($empty.output.topOutcomes).Count -eq 0 -and @($empty.output.protect).Count -eq 0) 'empty context invents nothing'

# =====================================================================
Write-TestSection 'the validator: facts by machine'
# =====================================================================
Assert-True (KV $plan $ps) 'the floor plan passes its own validator'
Assert-True (-not (KV ($(($p = New-DailyPlanLocal -PlanSources $ps); $p.topOutcomes = @((New-DailyPlanItem -Text 'Meet a new client at 3pm' -SourceType 'calendar' -SourceId 'EV-999' -Reason 'x')); $p)) $ps)) 'invented APPOINTMENT (EV-999 not in context) -> REJECT'
Assert-True (-not (KV ($(($p = New-DailyPlanLocal -PlanSources $ps); $p.topOutcomes = @((New-DailyPlanItem -Text 'Finish the audit by Friday' -SourceType 'timeline' -SourceId 'TL-999' -Reason 'x')); $p)) $ps)) 'invented DEADLINE (fabricated timeline id) -> REJECT'
Assert-True (-not (KV ($(($p = New-DailyPlanLocal -PlanSources $ps); $p.topOutcomes = @((New-DailyPlanItem -Text 'Call Sarah Thompson' -SourceType 'goal' -SourceId 'G-777' -Reason 'x')); $p)) $ps)) 'invented PERSON via fake source -> REJECT'
Assert-True (-not (KV ($(($p = New-DailyPlanLocal -PlanSources $ps); $p.topOutcomes = @((New-DailyPlanItem -Text 'Save $40,000' -SourceType 'life:financial' -SourceId 'FN-999' -Reason 'x')); $p)) $ps)) 'invented DOLLAR AMOUNT via fake source -> REJECT'
Assert-True (-not (KV ($(($p = New-DailyPlanLocal -PlanSources $ps); $p.topOutcomes = @((New-DailyPlanItem -Text 'x' -SourceType 'goal' -SourceId 'ZZZ-1' -Reason 'x')); $p)) $ps)) 'FALSE source id -> REJECT'
Assert-True (-not (KV ($(($p = New-DailyPlanLocal -PlanSources $ps); $p.topOutcomes = @((New-DailyPlanItem -Text 'x' -SourceType 'horoscope' -SourceId 'G-001' -Reason 'x')); $p)) $ps)) 'UNSUPPORTED sourceType -> REJECT'
$flood = @(); 1..50 | ForEach-Object { $flood += (New-DailyPlanItem -Text 'Call 5 leads' -SourceType 'goal' -SourceId 'G-001' -Reason 'x') }
Assert-True (-not (KV ($(($p = New-DailyPlanLocal -PlanSources $ps); $p.canWait = $flood; $p)) $ps)) 'EXCESSIVE plan items -> REJECT (whole)'
Assert-True (-not (KV ($(($p = New-DailyPlanLocal -PlanSources $ps); $it = @($p.topOutcomes)[0]; $it.text = 'I have scheduled the follow-up for you'; $p)) $ps)) 'AUTOMATIC-ACTION claim -> REJECT'
Assert-True (-not (KV ($(($p = New-DailyPlanLocal -PlanSources $ps); $rec = @($p.recommendations)[0]; $rec.requiresApproval = $false; $p)) $ps)) 'recommendation MISSING requiresApproval -> REJECT'
# mixed valid + one unsafe -> whole reject
$mixed = New-DailyPlanLocal -PlanSources $ps
$mixed.canWait = @((New-DailyPlanItem -Text 'Call 5 leads' -SourceType 'goal' -SourceId 'G-001' -Reason 'ok'), (New-DailyPlanItem -Text 'bad' -SourceType 'goal' -SourceId 'G-BAD' -Reason 'x'))
Assert-True (-not (KV $mixed $ps)) 'MIXED valid + unsafe -> the WHOLE result is rejected (no partial merge)'

# =====================================================================
Write-TestSection 'Claude briefing.compose (mocked; facts + fallback)'
# =====================================================================
Set-ReasoningDeadlineEnforcement -Enabled $false
Set-ClaudeUnderstandingConfiguredOverride $true
Set-ExecutiveReasoningConsent -Granted $true
$goodRec = PItem 'Add an action item: call 5 leads' 'goal' 'G-001' $true @{ type = 'create-action'; title = 'Call 5 leads'; detail = 'x' }
Set-ClaudePlanCallOverride ({ param($p) PlanJson -Top @((PItem 'Move the goal forward' 'goal' 'G-001')) -Protect @((PItem 'Protect Sunday dinner' 'nonNegotiable' 'NN-001')) -Recs @($goodRec) }.GetNewClosure())
$r = Invoke-ReasoningTask -TaskId 'briefing.compose' -Payload $ps
Assert-True ($r.engine -eq 'claude-understanding' -and $r.ok) 'VALID Claude plan accepted; VALID attribution to the driver'
Assert-True ($r.output.recommendations[0].requiresApproval -and $r.output.recommendations[0].proposedAction.type -eq 'create-action') 'Claude recommendation requires approval + valid action'
Set-ClaudePlanCallOverride ({ param($p) 'not json {' }.GetNewClosure())
Assert-True ((Invoke-ReasoningTask -TaskId 'briefing.compose' -Payload $ps).engine -eq 'local') 'MALFORMED plan -> local fallback'
Set-ClaudePlanCallOverride ({ param($p) PlanJson -Top @((PItem 'x' 'goal' 'G-XYZ')) }.GetNewClosure())
Assert-True ((Invoke-ReasoningTask -TaskId 'briefing.compose' -Payload $ps).engine -eq 'local') 'Claude cites a FALSE source -> local fallback'
Set-ClaudePlanCallOverride ({ param($p) PlanJson -Recs @((PItem 'wire funds' 'goal' 'G-001' $true @{ type = 'wire-money'; title = 'x'; detail = 'x' })) }.GetNewClosure())
Assert-True ((Invoke-ReasoningTask -TaskId 'briefing.compose' -Payload $ps).engine -eq 'local') 'Claude fabricates an ACTION TYPE -> local fallback'
Set-ClaudePlanCallOverride ({ param($p) throw 'server on fire' }.GetNewClosure())
$r = Invoke-ReasoningTask -TaskId 'briefing.compose' -Payload $ps
Assert-True ($r.engine -eq 'local' -and (Get-ClaudeUnderstandingLastAttempt).fallbackReason) 'PROVIDER FAILURE -> calm local fallback with a truthful reason'

Write-TestSection 'consent (task-scoped)'
$prov = Get-ReasoningProviders | Where-Object { $_.name -eq 'claude-understanding' }
Set-ClaudePlanCallOverride ({ param($p) throw 'should never run' }.GetNewClosure())
Clear-ExecutiveReasoningConsent
Assert-True ((Invoke-ReasoningTask -TaskId 'briefing.compose' -Payload $ps).engine -eq 'local') 'CONSENT DECLINED (unasked) -> driver not invoked, floor answers'
Set-ExtractionConsent -Granted $true
Assert-True (-not (& $prov.isAvailableForTask 'briefing.compose')) 'onboarding consent does NOT grant daily planning (task-scoped)'
Set-ClaudeUnderstandingConfiguredOverride $false; Set-ExecutiveReasoningConsent -Granted $true
Assert-True (-not (& $prov.isAvailableForTask 'briefing.compose')) 'UNCONFIGURED Claude -> not available (no data leaves)'
Set-ClaudeUnderstandingConfiguredOverride $true
Clear-ExtractionConsent; Clear-ExecutiveReasoningConsent; Clear-ClaudeUnderstandingOverrides; Set-ClaudePlanCallOverride $null
Set-ReasoningDeadlineEnforcement -Enabled $true

# =====================================================================
Write-TestSection 'bounded timeout / stale / close (mechanism)'
# =====================================================================
function New-BoundedPlan { param($Name, $Work) [pscustomobject]@{ name = $Name; isFloor = $false; priority = 5; bounded = $true; supports = { param($t) $t -eq 'briefing.compose' }; isAvailable = { $true }; boundedWork = $Work; invoke = { param($rq) $null } } }
$slow = New-BoundedPlan 'slow-plan' { param($j, $d) Start-Sleep -Milliseconds 1500; return @{ ok = $true; output = [pscustomobject]@{ x = 1 }; confidence = 0.9; clarifications = @(); reasonCode = 'ok'; requestId = 'x' } }
Register-ReasoningProvider -Provider $slow
$r = Invoke-ReasoningTask -TaskId 'briefing.compose' -Payload $ps -MaxMs 150
Assert-True ($r.engine -eq 'local' -and $r.fallbackReason -eq 'timeout') 'TIMEOUT -> local floor + fallbackReason=timeout'
Assert-True ((Get-ReasoningWorkerStats).inFlight -ge 1) 'CLOSE DURING PLANNING: an abandoned worker is tracked'
Stop-ReasoningWorkers
Assert-True ((Get-ReasoningWorkerStats).inFlight -eq 0) 'Stop-ReasoningWorkers reaps every worker (no orphans)'
Unregister-ReasoningProvider -Name 'slow-plan'
$stale = New-BoundedPlan 'stale-plan' { param($j, $d) return @{ ok = $true; output = [pscustomobject]@{ x = 1 }; confidence = 0.9; clarifications = @(); reasonCode = 'ok'; requestId = 'OLD-REQUEST' } }
$g = Invoke-CandidateGuarded -Provider $stale -Request (New-ReasoningRequest -TaskId 'briefing.compose' -Payload $ps -MaxMs 200) -TimeoutMs 3000
Assert-True ($null -eq $g.result -and $g.fallbackReason -eq 'stale') 'STALE completion (requestId mismatch) discarded'

# =====================================================================
Write-TestSection 'read-only: no writes; proposals pending-only; no re-fetch'
# =====================================================================
$before = @(Get-ChildItem $script:TestSandbox -File -ErrorAction SilentlyContinue).Count
1..3 | ForEach-Object { $null = Invoke-ReasoningTask -TaskId 'briefing.compose' -Payload (Src) }
$after = @(Get-ChildItem $script:TestSandbox -File -ErrorAction SilentlyContinue).Count
Assert-True ($before -eq 0 -and $after -eq 0) 'NO WRITES during plan generation (zero files in the identity/inbox sandbox)'
# provider signals are not fetched twice: composing must NOT call a live fetcher.
$script:FetchCalls = 0
function Get-CalendarSignal { param($Now) $script:FetchCalls++; return $null }
$null = New-DailyPlanLocal -PlanSources (Src)
$null = Get-DailyPlanSources -Context (New-PlanContext) -Now ([datetime]'2026-07-16 09:00')
Assert-True ($script:FetchCalls -eq 0) 'PROVIDER SIGNALS NOT FETCHED TWICE: composing reads calendar/email from the context, never re-fetches'
# a recommendation -> pending Inbox proposal (approval only), and it stays pending
$rec = @((Invoke-ReasoningTask -TaskId 'briefing.compose' -Payload (Src)).output.recommendations)[0]
if ($rec) {
    $sub = Submit-DailyPlanRecommendation -Recommendation $rec
    Assert-True ($sub.ok) 'approving a recommendation creates a proposal'
    $items = @(Get-InboxItems -Status 'pending')
    Assert-True ($items.Count -ge 1 -and (@($items | Where-Object { $_.status -eq 'pending' }).Count -eq $items.Count)) 'PROPOSALS REMAIN PENDING-ONLY (no auto-write to a domain store)'
    Assert-True ($items[0].source -eq 'daily-plan') 'the proposal is attributed to daily-plan and awaits approval'
}
else { Write-TestNote 'no recommendation to propose in this fixture' }

# =====================================================================
Write-TestSection 'Epic 14A: text-fact grounding (a valid id cannot conceal fabricated text)'
# =====================================================================
# A fixture whose sources carry REAL facts to ground against: a goal that names
# "Sarah Chen" and the number 500, plus the standard non-negotiable.
$fx = [pscustomobject]@{
    generatedAt = '2026-07-16 09:00:00'
    time        = [pscustomobject]@{ date = '2026-07-16'; dayOfWeek = 'Thursday'; hour = 9; partOfDay = 'morning'; isWeekend = $false }
    activeGoals = @(
        [pscustomobject]@{ id = 'FG-001'; title = 'Grow the agency'; nextStep = ''; domain = 'agency'; targetDate = '' },
        [pscustomobject]@{ id = 'FG-002'; title = 'Follow up with Sarah Chen'; nextStep = 'Reach 500 active policies'; domain = 'agency'; targetDate = '' }
    )
    nonNegotiables = @([pscustomobject]@{ id = 'NN-001'; title = 'Sunday dinner with family' })
}
$fps = Get-DailyPlanSources -Context $fx -Now ([datetime]'2026-07-16 09:00')
function FPlan { param($Text, $SourceType = 'goal', $SourceId = 'FG-001', $Reason = 'ok') $p = New-EmptyDailyPlan -Now ([datetime]'2026-07-16 09:00') -Engine 'x' -ContextVersion ([string]$fps.contextVersion); $p.topOutcomes = @((New-DailyPlanItem -Text $Text -SourceType $SourceType -SourceId $SourceId -Reason $Reason)); return $p }
function FKV { param($p) (Test-ReasoningOutput -TaskId 'briefing.compose' -Result (New-ReasoningResult -TaskId 'briefing.compose' -Ok $true -Output $p -Confidence 0.8) -Request (New-ReasoningRequest -TaskId 'briefing.compose' -Payload $fps)).valid }

# THE Epic 14 CTO-review gap example: real goal id, fabricated person + amount + time.
Assert-True (-not (FKV (FPlan 'Call Robert Kessler about the $80,000 wire at 3pm'))) 'GAP CLOSED: real goal id + fabricated person/amount/time -> REJECT'

# --- required REJECT cases (a fabricated fact riding a valid source id) ---
Assert-True (-not (FKV (FPlan 'Meet Robert about the renewal')))   'real id + fabricated PERSON -> reject'
Assert-True (-not (FKV (FPlan 'Prep the Acme partnership')))        'real id + fabricated COMPANY -> reject'
Assert-True (-not (FKV (FPlan 'Fly to Chicago for the pitch')))     'real id + fabricated CITY -> reject'
Assert-True (-not (FKV (FPlan 'Chase the $80,000 wire')))           'real id + fabricated AMOUNT -> reject'
Assert-True (-not (FKV (FPlan 'Push for a 25% increase')))          'real id + fabricated PERCENTAGE -> reject'
Assert-True (-not (FKV (FPlan 'Be ready by 3:45 today')))          'real id + fabricated TIME -> reject'
Assert-True (-not (FKV (FPlan 'File it by 09/30 sharp')))           'real id + fabricated DIGIT-FORM DATE -> reject'
Assert-True (-not (FKV (FPlan 'Wrap this before December')))        'real id + fabricated MONTH NAME -> reject'
# valid source + third-person completed-action claim
Assert-True (-not (FKV (FPlan 'Meeting scheduled with the team')))  'valid id + completed-action claim (Meeting scheduled) -> reject'
Assert-True (-not (FKV (FPlan 'Email sent to the client')))         'valid id + completed-action claim (Email sent) -> reject'
Assert-True (-not (FKV (FPlan 'Booked your flight for the trip')))  'valid id + completed-action claim (leading Booked) -> reject'
# one valid item + one unsafe item -> the WHOLE result rejects
$mix14a = New-EmptyDailyPlan -Now ([datetime]'2026-07-16 09:00') -Engine 'x' -ContextVersion ([string]$fps.contextVersion)
$mix14a.topOutcomes = @((New-DailyPlanItem -Text 'Grow the agency' -SourceType 'goal' -SourceId 'FG-001' -Reason 'ok'))
$mix14a.protect     = @((New-DailyPlanItem -Text 'Sunday dinner with family' -SourceType 'nonNegotiable' -SourceId 'NN-001' -Reason 'ok'))
$mix14a.followUps   = @((New-DailyPlanItem -Text 'Wire the $80,000 today' -SourceType 'goal' -SourceId 'FG-001' -Reason 'ok'))
Assert-True (-not (FKV $mix14a)) 'one valid + one unsafe item -> WHOLE result rejects (no partial merge)'

# --- required PASS cases (facts by machine; meaning by the human) ---
Assert-True (FKV (FPlan 'Grow the agency'))                                     'grounded, fact-free -> pass'
Assert-True (FKV (FPlan 'Reach out to Sarah Chen on renewals' 'goal' 'FG-002')) 'grounded NAME (Sarah Chen in the source) -> pass'
Assert-True (FKV (FPlan 'Push toward 500 active policies' 'goal' 'FG-002'))     'grounded NUMBER (500 in the source) -> pass'
Assert-True (FKV (FPlan 'Advance the agency this quarter'))                     'semantic compression / paraphrase -> pass'
Assert-True (FKV (FPlan 'Protect Sunday dinner tonight' 'nonNegotiable' 'NN-001')) 'grounded proper noun (Sunday) + wording change -> pass'
$recOk14a = New-EmptyDailyPlan -Now ([datetime]'2026-07-16 09:00') -Engine 'x' -ContextVersion ([string]$fps.contextVersion)
$recOk14a.topOutcomes = @((New-DailyPlanItem -Text 'Grow the agency' -SourceType 'goal' -SourceId 'FG-001' -Reason 'ok'))
$recOk14a.recommendations = @((New-DailyPlanItem -Text 'Consider preparing a reply' -SourceType 'goal' -SourceId 'FG-001' -Reason 'A timely reply helps; nothing is sent until you approve it.' -RequiresApproval $true -ProposedAction (New-DailyPlanAction -Type 'prepare-message' -Title 'Prepare a reply')))
Assert-True (FKV $recOk14a) 'write-producing proposal: requiresApproval=true + advisory wording -> pass'
$recNo14a = New-EmptyDailyPlan -Now ([datetime]'2026-07-16 09:00') -Engine 'x' -ContextVersion ([string]$fps.contextVersion)
$recNo14a.recommendations = @((New-DailyPlanItem -Text 'Follow up with Sarah Chen when you can' -SourceType 'goal' -SourceId 'FG-002' -Reason 'ok' -RequiresApproval $false))
Assert-True (FKV $recNo14a) 'non-write recommendation: requiresApproval=false -> pass'

# --- END-TO-END through the kernel + Claude driver mock: fabricated free text on a
#     real id is rejected whole and the deterministic floor answers (engine=local). ---
Set-ReasoningDeadlineEnforcement -Enabled $false
Set-ClaudeUnderstandingConfiguredOverride $true
Set-ExecutiveReasoningConsent -Granted $true
Set-ClaudePlanCallOverride ({ param($p) PlanJson -Top @((PItem 'Call Robert about the $80,000 wire' 'goal' 'G-001')) }.GetNewClosure())
$e2e14a = Invoke-ReasoningTask -TaskId 'briefing.compose' -Payload $ps
Assert-True ($e2e14a.ok -and $e2e14a.engine -eq 'local') 'END-TO-END: provider fabricates free text on a real id -> whole reject -> local floor serves'
Clear-ExecutiveReasoningConsent; Clear-ClaudeUnderstandingOverrides; Set-ClaudePlanCallOverride $null
Set-ReasoningDeadlineEnforcement -Enabled $true

# --- LABELLED KNOWN LIMITATIONS (Epic 13A residuals; documented in daily-plan.ps1 and
#     backstopped by the MANDATORY review-before-write screen). These intentionally PASS
#     the deterministic machine gate - the human removes them at review. ---
Assert-True (FKV (FPlan 'Robert should get a call'))            'KNOWN LIMITATION: sentence-initial proper noun (Robert leads) is not caught deterministically'
Assert-True (FKV (FPlan 'Ship it for eighty thousand dollars')) 'KNOWN LIMITATION: an amount written entirely as WORDS is not caught deterministically'
Assert-True (FKV (FPlan 'Sync with the ACME team'))            'KNOWN LIMITATION: an all-uppercase organization is exempted as an acronym'

Complete-TestFile 'daily-plan'
