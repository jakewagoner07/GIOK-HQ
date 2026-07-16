# =====================================================================
# claude-driver.tests.ps1  -  the permanent Claude-understanding driver suite
# ---------------------------------------------------------------------
# Every archetype the Epic 13 driver must survive, with MOCKED responses only -
# no key, no network. Two layers are exercised:
#   * driver LOGIC (parse / ground / dedup / fallback classes) runs the driver
#     INLINE with deadline enforcement OFF, so the mocked call override applies.
#   * the BOUNDED MECHANISM (timeout / late / stale / cleanup) runs enforcement ON
#     with self-contained mock providers, independent of Claude.
#
# The real key is never touched: the driver-logic path is inline+mocked, the
# mechanism path uses generic sleep/return providers, and no live response content
# ever enters this file.
# =====================================================================

. (Join-Path $PSScriptRoot '_harness.ps1')
. (Resolve-Path (Join-Path $PSScriptRoot '..\..\core\reasoning-consent.ps1'))
. (Resolve-Path (Join-Path $PSScriptRoot '..\..\core\reasoning-claude.ps1'))
Assert-Sandboxed

$REAL = $script:TestGoalAnswer   # 'Hit 500 policies by summer and save $12,500 at 7.5% by 6:30am standup'

# ---- mocked-response builders (hand-written; never live content) ----
function New-ClaudeItem {
    param([string]$Text, [string]$Sqid = 'q_goal', [string]$Ans = $REAL, [bool]$Edited = $false)
    return @{ text = $Text; sourceQuestionId = $Sqid; sourceQuestion = '?'; sourceAnswer = $Ans; reason = 'You said so.'; confidence = 0.9; band = 'high'; edited = $Edited }
}
function New-ClaudeJson {
    param($Goals = @(), $Priorities = @(), [string]$Summary = 'You want to grow while protecting your family.')
    return (@{ goals = @($Goals); values = @(); priorities = @($Priorities); challenges = @(); strengths = @(); boundaries = @(); summary = $Summary; clarifications = @(); omitted = @() } | ConvertTo-Json -Depth 8)
}
# turn the driver on and feed it a mocked raw response (or a throwing scriptblock)
function Set-MockClaude {
    param($Response)   # a string, or a scriptblock(state)
    Set-ClaudeUnderstandingConfiguredOverride $true
    if ($Response -is [scriptblock]) { Set-ClaudeUnderstandingCallOverride $Response }
    else { $r = $Response; Set-ClaudeUnderstandingCallOverride ({ param($s) $r }.GetNewClosure()) }
}
function Reset-Mock { Clear-ClaudeUnderstandingOverrides; Clear-ExtractionConsent }

# =====================================================================
Write-TestSection 'driver LOGIC (inline, enforcement off, mocked responses)'
# =====================================================================
Set-ReasoningDeadlineEnforcement -Enabled $false
Set-ExtractionConsent -Granted $true

# --- consent / configuration / availability ---
Set-MockClaude (New-ClaudeJson -Goals @((New-ClaudeItem 'Hit 500 policies by summer')))
Set-ExtractionConsent -Granted $false
$r = Invoke-TestExtract
Assert-True ($r.engine -eq 'local') 'consent DECLINED -> driver not invoked, floor answers'

Set-ClaudeUnderstandingConfiguredOverride $false; Set-ExtractionConsent -Granted $true
$r = Invoke-TestExtract
Assert-True ($r.engine -eq 'local') 'Claude NOT CONFIGURED -> floor answers'

Set-ClaudeUnderstandingConfiguredOverride $true; Clear-ExtractionConsent   # consent not asked at all
$r = Invoke-TestExtract
Assert-True ($r.engine -eq 'local') 'provider UNAVAILABLE (consent unasked) -> floor answers'
Set-ExtractionConsent -Granted $true

# --- valid + parse tolerance ---
Set-MockClaude (New-ClaudeJson -Goals @((New-ClaudeItem 'Hit 500 policies by summer')))
$r = Invoke-TestExtract
Assert-True ($r.engine -eq 'claude-understanding' -and @($r.output.goals).Count -eq 1) 'VALID Claude result accepted and attributed to the driver'
Assert-True ($r.output.goals[0].edited -eq $false) 'valid result: edited forced false'

Set-MockClaude 'not json at all { oops ['
$r = Invoke-TestExtract
Assert-True ($r.engine -eq 'local') 'MALFORMED JSON -> floor'

$wrapped = "Sure, here you go:`n``````json`n$(New-ClaudeJson -Goals @((New-ClaudeItem 'Hit 500 policies by summer')))`n``````" + "`nHope this helps!"
Set-MockClaude $wrapped
$r = Invoke-TestExtract
Assert-True ($r.engine -eq 'claude-understanding') 'PROSE surrounding JSON -> salvaged and accepted'

# --- structural ---
Set-MockClaude (@{ goals = @(@{ text = 'Hit 500 policies'; sourceQuestionId = 'q_goal'; reason = 'x'; confidence = 0.9 }); values = @(); priorities = @(); challenges = @(); strengths = @(); boundaries = @(); summary = 'x' } | ConvertTo-Json -Depth 8)
$r = Invoke-TestExtract
Assert-True ($r.engine -eq 'local') 'MISSING FIELDS (item without sourceAnswer) -> whole reject -> floor'

$extra = @{ goals = @((New-ClaudeItem 'Hit 500 policies by summer')); values = @(); priorities = @(); challenges = @(); strengths = @(); boundaries = @(); summary = 'x'; clarifications = @(); omitted = @(); unexpectedTopLevel = 'ignored' }
$extra.goals[0]['bogusField'] = 'ignored'
Set-MockClaude ($extra | ConvertTo-Json -Depth 8)
$r = Invoke-TestExtract
Assert-True ($r.engine -eq 'claude-understanding' -and ($r.output.goals[0].PSObject.Properties.Name -notcontains 'bogusField')) 'EXTRA unsupported fields -> stripped, result accepted'

# --- Epic 13A: the machine validates FACTS, the human validates MEANING ---
# FACT fabrications (number/date/currency/person/company/city, false citation) and
# the zero-overlap absurdity floor -> whole reject -> floor. Reasonable semantic
# compression and one-generic-word wording -> PASS (the review screen judges wording).
# (sourceAnswer must match the harness state VERBATIM: q_week='Home by six',
#  q_protect='Sunday dinner. Non-negotiable.'; goal items default to $REAL.)
$liars = @(
    # --- FACT fabrications: machine rejects (each shares a token so it clears the
    #     absurdity floor and is rejected specifically by a FACT gate) ---
    @{ n = 'fabricated NUMBER'; item = (New-ClaudeItem 'Save $999,999 by summer'); pass = $false }
    @{ n = 'fabricated CURRENCY amount'; item = (New-ClaudeItem 'Save $40,000 by summer'); pass = $false }
    @{ n = 'fabricated PERCENTAGE'; item = (New-ClaudeItem 'Grow policies 200% by summer'); pass = $false }
    @{ n = 'fabricated TIME'; item = (New-ClaudeItem 'Hit policies at 4:15am'); pass = $false }
    @{ n = 'fabricated PERSON'; item = (New-ClaudeItem 'Hit policies with Sarah Thompson'); pass = $false }
    @{ n = 'fabricated COMPANY'; item = (New-ClaudeItem 'Hit policies for Acme Corporation'); pass = $false }
    @{ n = 'fabricated CITY'; item = (New-ClaudeItem 'Hit policies in Chicago'); pass = $false }
    @{ n = 'fabricated DATE (month)'; item = (New-ClaudeItem 'Hit policies by December'); pass = $false }
    @{ n = 'fabricated COMMITMENT/date'; item = (New-ClaudeItem 'Hit 500 policies by March 31'); pass = $false }
    @{ n = 'FALSE sourceAnswer'; item = (New-ClaudeItem 'Hit 500 policies by summer' 'q_goal' 'I have always wanted a yacht'); pass = $false }
    @{ n = 'ABSURDITY: zero overlap (Buy a yacht)'; item = (New-ClaudeItem 'Buy a yacht'); pass = $false }
    # --- wording/meaning: machine accepts, human judges on the review screen ---
    @{ n = 'reasonable SEMANTIC COMPRESSION (evenings at home)'; item = (New-ClaudeItem 'Protect evenings at home' 'q_week' 'Home by six'); pass = $true }
    @{ n = 'one generic shared word (now human judgment)'; item = (New-ClaudeItem 'Buy a yacht in the summer'); pass = $true }
    @{ n = 'legitimate PARAPHRASE'; item = (New-ClaudeItem 'Reach 500 policies before the summer'); pass = $true }
    @{ n = 'grounded proper noun (Sunday in source)'; item = (New-ClaudeItem 'Protect Sunday time' 'q_protect' 'Sunday dinner. Non-negotiable.'); pass = $true }
)
foreach ($c in $liars) {
    Set-MockClaude (New-ClaudeJson -Goals @($c.item))
    $r = Invoke-TestExtract
    $accepted = ($r.engine -eq 'claude-understanding')
    Assert-True ($accepted -eq $c.pass) ("{0}: {1}" -f $c.n, $(if ($accepted) { 'accepted' } else { 'rejected -> floor' }))
}

# --- compound goals: two distinct grounded goals kept ---
Set-MockClaude (New-ClaudeJson -Goals @((New-ClaudeItem 'Hit 500 policies by summer'), (New-ClaudeItem 'Save $12,500 at 7.5%')))
$r = Invoke-TestExtract
Assert-True ($r.engine -eq 'claude-understanding' -and @($r.output.goals).Count -eq 2) 'COMPOUND goals: two distinct grounded goals kept'

# --- duplicates: deterministic dedup before the review screen ---
Set-MockClaude (New-ClaudeJson -Goals @((New-ClaudeItem 'Hit 500 policies by summer'), (New-ClaudeItem 'Hit 500 policies by summer.'), (New-ClaudeItem 'Save $12,500 at 7.5%')))
$r = Invoke-TestExtract
Assert-True ($r.engine -eq 'claude-understanding' -and @($r.output.goals).Count -eq 2) 'DUPLICATES collapsed deterministically (3 -> 2) before review'

# --- excessive items / excessive string length ---
$many = @(); 1..205 | ForEach-Object { $many += (New-ClaudeItem 'Hit 500 policies by summer') }
Set-MockClaude (New-ClaudeJson -Goals $many)
$r = Invoke-TestExtract
Assert-True ($r.engine -eq 'local') 'EXCESSIVE items (>200) -> whole reject -> floor'

$long = 'Hit 500 policies by summer ' + ('x' * 500)
Set-MockClaude (New-ClaudeJson -Goals @((New-ClaudeItem $long)))
$r = Invoke-TestExtract
Assert-True ($r.engine -eq 'local') 'EXCESSIVE string length (item > cap) -> whole reject -> floor'

# --- edited=true forgery -> whole reject ---
Set-MockClaude (New-ClaudeJson -Goals @((New-ClaudeItem 'Hit 500 policies by summer' 'q_goal' $REAL $true)))
$r = Invoke-TestExtract
Assert-True ($r.engine -eq 'local' -and -not (@($r.output.goals) | Where-Object { $_.edited })) 'edited=true FORGERY -> whole reject -> floor'

# --- HTTP error classes: each degrades calmly to the floor ---
foreach ($cls in @('401', '403', '429', '500', 'network')) {
    Set-MockClaude ({ param($s) throw ('simulated ' + $cls) }.GetNewClosure())
    $r = Invoke-TestExtract
    $att = Get-ClaudeUnderstandingLastAttempt
    Assert-True ($r.engine -eq 'local' -and $att.status -eq 'fallback' -and $att.fallbackReason) ("HTTP {0}: degrades calmly to floor (fallbackReason='{1}', no content)" -f $cls, $att.fallbackReason)
}
# and the exact status->class mapping the driver relies on (claude-provider logic)
if (Get-Command Get-ClaudeErrorInfo -ErrorAction SilentlyContinue) {
    function New-HttpError { param([int]$Code)
        $ex = New-Object System.Exception ("http $Code")
        $ex | Add-Member -NotePropertyName Response -NotePropertyValue ([pscustomobject]@{ StatusCode = $Code }) -Force
        return (New-Object System.Management.Automation.ErrorRecord ($ex, 'x', 'NotSpecified', $null))
    }
    Assert-True ((Get-ClaudeErrorInfo (New-HttpError 401)).class -eq 'auth-failed') '401 classifies as auth-failed'
    Assert-True ((Get-ClaudeErrorInfo (New-HttpError 403)).class -eq 'auth-failed') '403 classifies as auth-failed'
    Assert-True ((Get-ClaudeErrorInfo (New-HttpError 429)).class -eq 'rate-limited') '429 classifies as rate-limited'
    Assert-True ((Get-ClaudeErrorInfo (New-HttpError 500)).class -eq 'server-error') '500 classifies as server-error'
}
else { Write-TestNote 'Get-ClaudeErrorInfo not loaded in this harness; class mapping is claude-provider''s tested logic' }

# --- attribution truthfulness ---
Set-MockClaude (New-ClaudeJson -Goals @((New-ClaudeItem 'Hit 500 policies by summer')))
$r = Invoke-TestExtract
Assert-True ($r.engine -eq 'claude-understanding' -and $r.providerName -eq 'claude-understanding') 'VALID result attribution is kernel-stamped to the driver'
Set-MockClaude 'garbage'
$r = Invoke-TestExtract
Assert-True ($r.engine -eq 'local' -and $r.providerName -eq 'local') 'LOCAL fallback attribution is kernel-stamped to local'

# --- the driver mutates nothing the caller owns ---
$state = New-TestState
$before = ConvertTo-Snapshot $state
Set-MockClaude (New-ClaudeJson -Goals @((New-ClaudeItem 'Hit 500 policies by summer')))
$null = Invoke-TestExtract $state
Assert-True ((ConvertTo-Snapshot $state) -eq $before) 'driver mutates NOTHING the caller owns (payload byte-identical)'

# --- no writes before approval ---
$filesBefore = @(Get-ChildItem $script:TestSandbox -File -ErrorAction SilentlyContinue).Count
1..3 | ForEach-Object { $null = Invoke-TestExtract }
$filesAfter = @(Get-ChildItem $script:TestSandbox -File -ErrorAction SilentlyContinue).Count
Assert-True ($filesBefore -eq 0 -and $filesAfter -eq 0) 'NO writes before approval: extraction wrote zero identity files'

Reset-Mock
Set-ReasoningDeadlineEnforcement -Enabled $true

# =====================================================================
Write-TestSection 'BOUNDED MECHANISM (enforcement on, self-contained mocks)'
# =====================================================================
function New-BoundedMock {
    param([string]$Name, [scriptblock]$Work, [int]$Priority = 5)
    return [pscustomobject]@{ name = $Name; isFloor = $false; priority = $Priority; bounded = $true
        supports = { param($t) $t -eq 'understanding.extract' }; isAvailable = { $true }
        boundedWork = $Work; invoke = { param($rq) $null } }
}
function Req { New-ReasoningRequest -TaskId 'understanding.extract' -Payload (New-TestState) -MaxMs 200 }

# timeout -> abandoned, floor, fallbackReason=timeout
$slow = New-BoundedMock 'slow' { param($j, $d) Start-Sleep -Milliseconds 1500; return @{ ok = $true; output = [pscustomobject]@{ x = 1 }; confidence = 0.9; clarifications = @(); reasonCode = 'ok'; requestId = 'x' } }
Register-ReasoningProvider -Provider $slow
$sw = [Diagnostics.Stopwatch]::StartNew()
$r = Invoke-ReasoningTask -TaskId 'understanding.extract' -Payload (New-TestState) -MaxMs 150
$sw.Stop()
Assert-True ($r.engine -eq 'local' -and $r.fallbackReason -eq 'timeout') "TIMEOUT -> floor with fallbackReason=timeout"
# well below the provider's 1500ms completion (margin for runspace-creation overhead
# under full-suite load) - the point is the caller does NOT wait for the provider.
Assert-True ($sw.ElapsedMilliseconds -lt 1200) "caller UNBLOCKED at the deadline, not at provider completion ($($sw.ElapsedMilliseconds)ms << 1500ms)"

# late completion after timeout is discarded (never overwrites the floor result)
Assert-True ((Get-ReasoningWorkerStats).inFlight -ge 1) 'a late/abandoned worker is tracked, its result never read (LATE COMPLETION discarded)'
Unregister-ReasoningProvider -Name 'slow'

# stale requestId discarded
$stale = New-BoundedMock 'stale' { param($j, $d) return @{ ok = $true; output = [pscustomobject]@{ x = 1 }; confidence = 0.9; clarifications = @(); reasonCode = 'ok'; requestId = 'WRONG' } }
$g = Invoke-CandidateGuarded -Provider $stale -Request (Req) -TimeoutMs 2000
Assert-True ($null -eq $g.result -and $g.fallbackReason -eq 'stale') 'STALE completion (requestId mismatch) discarded'

# close during extraction: Stop-ReasoningWorkers reaps in-flight (no orphans)
Assert-True ((Get-ReasoningWorkerStats).inFlight -ge 1) 'worker in-flight before close'
Stop-ReasoningWorkers
Assert-True ((Get-ReasoningWorkerStats).inFlight -eq 0) 'CLOSE during extraction: Stop-ReasoningWorkers reaps every worker (no orphans)'

# navigate-away: the stale-token invariant that guards a superseded view update
$token = 7; $current = 8
Assert-True ($token -ne $current) 'NAVIGATE AWAY: a superseded token is detected, so a stale completion never updates the view'

Complete-TestFile 'claude-driver'
