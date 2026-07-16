# =====================================================================
# _harness.ps1 - shared harness for the Executive Reasoning Layer tests
# ---------------------------------------------------------------------
# Loads the kernel + the deterministic floor, redirects every identity write
# into a throwaway sandbox, and provides the assertion API and the fixtures
# each test file builds its providers from.
#
# SAFETY: identity.ps1 resolves Get-IdentityDir from $PSScriptRoot, which
# points at the REAL tony-alpha/identity - Jake's live runtime data. This
# harness overrides that function AFTER dot-sourcing so every write lands in
# %TEMP%, and Assert-Sandboxed refuses to run a single test if the override
# did not take. A test suite that can reach real data is not a test suite.
#
# No network. No API keys. No provider calls. Windows PowerShell 5.1.
# =====================================================================

$ErrorActionPreference = 'Stop'

# ---- load the system under test (paths are repo-relative, never absolute) ----
$script:CoreDir = (Resolve-Path (Join-Path $PSScriptRoot '..\..\core')).Path
. (Join-Path $script:CoreDir 'reasoning-layer.ps1')
. (Join-Path $script:CoreDir 'first-conversation.ps1')
. (Join-Path $script:CoreDir 'identity.ps1')
. (Join-Path $script:CoreDir 'understanding-engine.ps1')
. (Join-Path $script:CoreDir 'reasoning-local.ps1')

# ---- sandbox: every identity write goes here, never to the repo ----
$script:TestSandbox = Join-Path $env:TEMP ('giok-reasoning-tests-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $script:TestSandbox -Force | Out-Null

# THIS OVERRIDES identity.ps1's Get-IdentityDir. Order matters: it must come
# after the dot-source above, or the real store wins.
function Get-IdentityDir { return $script:TestSandbox }

# Refuse to run unless the redirect actually took effect.
function Assert-Sandboxed {
    $dir = [string](Get-IdentityDir)
    $repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..\..')).Path
    if ([string]::IsNullOrWhiteSpace($dir)) { throw 'HARNESS UNSAFE: Get-IdentityDir returned nothing.' }
    if (-not $dir.StartsWith($env:TEMP, [StringComparison]::OrdinalIgnoreCase)) {
        throw ("HARNESS UNSAFE: identity dir is not under TEMP: {0}" -f $dir)
    }
    if ($dir.StartsWith($repo, [StringComparison]::OrdinalIgnoreCase)) {
        throw ("HARNESS UNSAFE: identity dir points inside the repo: {0}" -f $dir)
    }
}

# ---- assertions ----
$script:TestPass = 0
$script:TestFail = 0
$script:TestFailures = @()

function Assert-True {
    param([bool]$Condition, [Parameter(Mandatory)][string]$Message)
    if ($Condition) {
        $script:TestPass++
        Write-Host ("  [PASS] {0}" -f $Message)
    }
    else {
        $script:TestFail++
        $script:TestFailures += $Message
        Write-Host ("  [FAIL] {0}" -f $Message)
    }
}

# For observations that are recorded on purpose but are NOT pass/fail gates
# (documented, accepted kernel behaviour). Never counted as a pass.
function Write-TestNote {
    param([Parameter(Mandatory)][string]$Message)
    Write-Host ("  [note] {0}" -f $Message)
}

function Write-TestSection {
    param([Parameter(Mandatory)][string]$Title)
    Write-Host ''
    Write-Host ("### {0} ###" -f $Title)
}

# Prints the summary and sets the exit code. Non-zero on any failure, which is
# what makes this suite usable from a runner or CI.
function Complete-TestFile {
    param([Parameter(Mandatory)][string]$Name)
    if (Test-Path $script:TestSandbox) { Remove-Item $script:TestSandbox -Recurse -Force -ErrorAction SilentlyContinue }
    Write-Host ''
    if ($script:TestFail -gt 0) {
        Write-Host ("{0}: {1} passed, {2} FAILED" -f $Name, $script:TestPass, $script:TestFail)
        foreach ($f in $script:TestFailures) { Write-Host ("    FAILED: {0}" -f $f) }
        exit 1
    }
    Write-Host ("{0}: {1} passed, 0 failed" -f $Name, $script:TestPass)
    exit 0
}

# ---- fixtures ----
# A synthetic onboarding answer. Deliberately dense: two amounts with different
# formats, a percentage and a time, so the grounding rules have real material to
# check. This is invented test content, not anyone's data.
$script:TestGoalAnswer = 'Hit 500 policies by summer and save $12,500 at 7.5% by 6:30am standup'

function New-TestState {
    $answers = [pscustomobject]@{}
    $map = [ordered]@{
        q_name       = 'Jake'
        q_areas      = 'Family, health, and the agency'
        q_goal       = $script:TestGoalAnswer
        q_challenge  = 'I am the bottleneck'
        q_protect    = 'Sunday dinner. Non-negotiable.'
        q_week       = 'Home by six'
        q_boundaries = 'Never email a client without asking me first'
    }
    foreach ($k in $map.Keys) { $answers | Add-Member -NotePropertyName $k -NotePropertyValue $map[$k] -Force }
    return [pscustomobject]@{ completed = $false; currentStep = 8; answers = $answers }
}

# A context object with a nested object and an array - the surface the
# context-mutator and array-clearer archetypes attack.
function New-TestContext {
    return [pscustomobject]@{
        note   = 'pristine'
        tags   = @('a', 'b')
        nested = [pscustomobject]@{ deep = 'clean' }
    }
}

function New-TestItem {
    # AllowEmptyString on purpose: "an item with no text" and "an item with no
    # source question" are themselves hostile fixtures the gate must reject, so
    # the fixture builder has to be able to construct them.
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Text,
        [AllowEmptyString()][string]$SourceAnswer = $script:TestGoalAnswer,
        [bool]$Edited = $false,
        [AllowEmptyString()][string]$SourceQuestionId = 'q_goal'
    )
    return [pscustomobject]@{
        id               = 'U-test'
        text             = $Text
        sourceQuestionId = $SourceQuestionId
        sourceQuestion   = '?'
        sourceAnswer     = $SourceAnswer
        reason           = '.'
        confidence       = 0.9
        band             = 'high'
        clarify          = ''
        edited           = $Edited
    }
}

function Register-TestProvider {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][scriptblock]$Invoke,
        [int]$Priority = 1,
        [scriptblock]$Supports,
        [scriptblock]$IsAvailable
    )
    if (-not $Supports) { $Supports = { param($t) $t -eq 'understanding.extract' } }
    if (-not $IsAvailable) { $IsAvailable = { $true } }
    Register-ReasoningProvider -Provider ([pscustomobject]@{
            name        = $Name
            description = ("test provider: {0}" -f $Name)
            isFloor     = $false
            priority    = $Priority
            supports    = $Supports
            isAvailable = $IsAvailable
            invoke      = $Invoke
        })
}

function Unregister-TestProvider {
    param([Parameter(Mandatory)][string]$Name)
    Unregister-ReasoningProvider -Name $Name
}

# An accelerator that returns a real floor model with its goals replaced by the
# crafted items in $script:CraftedGoals. This is how nearly every hostile
# archetype smuggles its payload: a structurally perfect model, one bad item.
function Register-CraftingProvider {
    param([Parameter(Mandatory)][string]$Name, [int]$Priority = 1)
    Register-TestProvider -Name $Name -Priority $Priority -Invoke {
        param($rq)
        $m = New-UnderstandingModel -State $rq.input
        $m.goals = @($script:CraftedGoals)
        return (New-ReasoningResult -TaskId $rq.taskId -Ok $true -Output $m -Confidence 0.9)
    }
}

function Invoke-TestExtract {
    param($State)
    if (-not $State) { $State = New-TestState }
    return (Invoke-ReasoningTask -TaskId 'understanding.extract' -Payload $State)
}

# Did any text the provider tried to smuggle survive into the accepted output?
function Test-OutputLeaks {
    param($Result, [Parameter(Mandatory)][string]$Needle)
    if (-not $Result -or -not $Result.output) { return $false }
    $items = @($Result.output.goals) + @($Result.output.priorities) + @($Result.output.values) +
    @($Result.output.challenges) + @($Result.output.strengths) + @($Result.output.boundaries)
    return [bool](@($items) | Where-Object { $_ -and (([string]$_.text) -like ("*{0}*" -f $Needle)) })
}

# Timestamps and per-build ids legitimately vary; everything else must not.
function ConvertTo-NormalizedModel {
    param($Model)
    $j = $Model | ConvertTo-Json -Depth 12
    $j = $j -replace '"builtAt":\s*"[^"]*"', '"builtAt":"X"'
    $j = $j -replace '"id":\s*"U-[0-9a-f]{8}"', '"id":"U-X"'
    return $j
}

function ConvertTo-Snapshot {
    param($Object)
    if ($null -eq $Object) { return '<null>' }
    return ($Object | ConvertTo-Json -Depth 12 -Compress)
}
