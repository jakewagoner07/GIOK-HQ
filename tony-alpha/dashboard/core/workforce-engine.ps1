# =====================================================================
# workforce-engine.ps1  —  Tony's management layer (the Workforce Engine)
# ---------------------------------------------------------------------
# Tony never becomes a specialist. Tony MANAGES specialists. This is the
# provider-neutral framework that lets Tony delegate analysis to specialist
# agents, receive their standard reports, reject poor ones, request another
# review, merge multiple reports, and present ONE recommendation to Jake -
# while remaining the single Executive Chief of Staff and the only executive
# decision maker.
#
# Specialists ANALYZE and RECOMMEND; they never act, never talk to Jake
# directly, and cannot bypass Tony - every report flows into Tony's merge and
# only Tony's synthesis reaches Jake. Specialists use EXISTING provider
# outputs (Get-Email, Get-Calendar, Document Intelligence, and the Priority /
# Timeline engines when present) - no duplicate provider logic, no new
# storage, no independent agent memory. The Decision Framework keeps final
# authority over the merged recommendation.
#
# Every specialist exposes the SAME interface (registered object):
#   name         <string>   e.g. 'Email Analyst'
#   purpose      <string>   what it is for
#   capabilities <string[]> what it can do
#   relevant     <scriptblock> param($task) -> [bool]
#   analyze      <scriptblock> param($request) -> a standard REPORT
#   status       <scriptblock> -> { available; detail }
#
# A standard REPORT (New-SpecialistReport):
#   specialist purpose input output confidence evidence status
#   recommendedActions assessment scope generatedAt
# =====================================================================

$ErrorActionPreference = 'Stop'

# ---- the specialist registry (mirrors the live-provider pattern) ----
$script:Specialists = [ordered]@{}

function Register-Specialist {
    param([Parameter(Mandatory)] $Specialist)
    if ($Specialist.name -and $Specialist.analyze) { $script:Specialists[$Specialist.name] = $Specialist }
}
function Get-Specialists { return @($script:Specialists.Values) }
function Get-Specialist { param([string]$Name) return $script:Specialists[$Name] }
function Get-WorkforceRoster {
    return @(Get-Specialists | ForEach-Object {
            $st = if ($_.status) { try { & $_.status } catch { [pscustomobject]@{ available = $false; detail = 'status error' } } } else { [pscustomobject]@{ available = $true; detail = '' } }
            [pscustomobject]@{ name = $_.name; purpose = $_.purpose; capabilities = @($_.capabilities); available = [bool]$st.available; detail = $st.detail }
        })
}

# ---- the standard report every specialist returns ------------------
function New-SpecialistReport {
    param(
        [Parameter(Mandatory)][string]$Specialist,
        [string]$Purpose = '', [string]$Input = '', [string]$Output = '',
        [double]$Confidence = 0.0, $Evidence = @(), [string]$Status = 'ok',
        $RecommendedActions = @(), [string]$Assessment = 'informational', [string]$Scope = ''
    )
    return [pscustomobject]@{
        specialist         = $Specialist
        purpose            = $Purpose
        input              = $Input
        output             = $Output
        confidence         = [math]::Round([math]::Max(0.0, [math]::Min(1.0, $Confidence)), 2)
        evidence           = @($Evidence)     # each: { source; sourceId; detail }
        status             = $Status          # ok | degraded | no-data | unavailable | error
        recommendedActions = @($RecommendedActions)
        assessment         = $Assessment      # needs-attention | clear | informational
        scope              = $Scope           # domain tag (for conflict detection)
        generatedAt        = (Get-Date)
    }
}

# ---- delegation: assign work, receive reports ----------------------
function Get-RelevantSpecialists {
    param([string]$Task)
    return @(Get-Specialists | Where-Object { $_.relevant -and (& { try { [bool](& $_.relevant $Task) } catch { $false } }) })
}

# Assign ONE piece of work to ONE specialist and receive its report.
function Invoke-Specialist {
    param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)] $Request)
    $s = Get-Specialist $Name
    if (-not $s -or -not $s.analyze) { return $null }
    try { return (& $s.analyze $Request) }
    catch { return (New-SpecialistReport -Specialist $Name -Status 'error' -Confidence 0.0 -Output ('Could not complete the review: {0}' -f $_.Exception.Message)) }
}

# ---- quality control: Tony rejects poor reports --------------------
function Test-ReportAcceptable {
    param($Report)
    if (-not $Report) { return $false }
    if ($Report.status -in @('unavailable', 'no-data', 'error')) { return $false }
    if ($Report.confidence -lt 0.35 -and @($Report.evidence).Count -eq 0) { return $false }
    return $true
}

# ---- merge: Tony's synthesis into ONE recommendation ---------------
# Combines accepted reports, records rejected ones, detects conflicting
# opinions (same scope, opposing assessment), aggregates confidence, decides
# whether verification or Jake's raw review is warranted, and lets the
# Decision Framework keep final authority. Transparent by construction:
# specialistsUsed + evidence + reasoning are always present.
function Merge-SpecialistReports {
    param($Reports, [string]$Task = '', $Context = $null)
    $all = @($Reports | Where-Object { $_ })
    $accepted = @($all | Where-Object { Test-ReportAcceptable $_ })
    $rejected = @($all | Where-Object { -not (Test-ReportAcceptable $_) } | ForEach-Object {
            [pscustomobject]@{ specialist = $_.specialist; status = $_.status; confidence = $_.confidence; reason = $(if ($_.status -in @('unavailable', 'no-data')) { 'nothing to review' } elseif ($_.status -eq 'error') { 'the review failed' } else { 'confidence too low without evidence' }) }
        })

    $conf = if ($accepted.Count -gt 0) { [math]::Round((($accepted | Measure-Object -Property confidence -Average).Average), 2) } else { 0.0 }

    # conflicting specialist opinions: same scope, opposing assessment
    $conflicts = @()
    for ($i = 0; $i -lt $accepted.Count; $i++) {
        for ($j = $i + 1; $j -lt $accepted.Count; $j++) {
            $a = $accepted[$i]; $b = $accepted[$j]
            if ($a.scope -and ($a.scope -eq $b.scope) -and ($a.assessment -ne $b.assessment) -and ($a.assessment -in @('needs-attention', 'clear')) -and ($b.assessment -in @('needs-attention', 'clear'))) {
                $conflicts += [pscustomobject]@{ scope = $a.scope; between = @($a.specialist, $b.specialist); a = $a.assessment; b = $b.assessment }
            }
        }
    }

    # Decision Framework keeps FINAL authority over the recommendation.
    $guidance = $null
    if ($Context -and (Get-Command Evaluate-TonyDecision -ErrorAction SilentlyContinue)) {
        try {
            $guidance = Evaluate-TonyDecision -Identity $Context.identity -Vision $Context.vision -Goals $Context.goals -Mission $Context.mission `
                -CoreValues $Context.values -AnnualTheme $Context.annualTheme -NonNegotiables @() -Family $null -Health $null -Financial $null `
                -CurrentWorkspace 'Home' -CurrentQuestion $Task -OpenTasks $Context.openTasks -RecentAudits @()
        } catch { }
    }

    $recommendedActions = @($accepted | ForEach-Object { $_.recommendedActions } | ForEach-Object { $_ } | Where-Object { $_ } | Select-Object -Unique)
    $evidence = @($accepted | ForEach-Object { $_.evidence } | ForEach-Object { $_ } | Where-Object { $_ })
    $specialistsUsed = @($accepted | ForEach-Object { $_.specialist })

    # decision rules
    $lowConf = @($accepted | Where-Object { $_.confidence -lt 0.5 })
    $needsVerification = [bool]($lowConf.Count -gt 0)
    $showRawToJake = [bool](($conflicts.Count -gt 0) -or ($conf -lt 0.4 -and $accepted.Count -gt 0))

    # a deterministic combined summary (the provider will voice Tony's version)
    $lines = @($accepted | Where-Object { $_.output } | ForEach-Object { ('{0}: {1}' -f $_.specialist, $_.output) })
    $summary = if ($accepted.Count -eq 0) {
        'No specialist had anything to report on that right now.'
    } else {
        ($lines -join ' ')
    }

    $reasoning = if ($accepted.Count -eq 0) { 'Nothing to delegate produced a usable report.' }
    elseif ($conflicts.Count -gt 0) { 'The specialists disagreed on one point, so I am flagging it for your call.' }
    elseif ($needsVerification) { 'One report was low-confidence, so treat it as a lead, not a certainty.' }
    else { ('Combined {0} specialist report(s) into one read.' -f $accepted.Count) }

    return [pscustomobject]@{
        source             = 'workforce'
        task               = $Task
        specialistsUsed    = $specialistsUsed
        reports            = @($accepted)
        rejected           = @($rejected)
        evidence           = @($evidence)
        recommendedActions = @($recommendedActions)
        confidence         = $conf
        conflicts          = @($conflicts)
        needsVerification  = $needsVerification
        showRawToJake      = $showRawToJake
        guidance           = $guidance      # Decision Framework - final authority
        reasoning          = $reasoning
        summary            = $summary
        generatedAt        = (Get-Date)
    }
}

# ---- THE management call: Tony delegates + merges ------------------
# Given a task (Jake's question) and the single Executive Context, Tony picks
# the relevant specialists (or a caller-specified subset), assigns the work,
# collects their standard reports, and merges them into one recommendation.
function Invoke-Workforce {
    param([string]$Task, $Context = $null, [datetime]$Now = (Get-Date), [string[]]$Only = @())
    $specs = if (@($Only).Count -gt 0) { @($Only | ForEach-Object { Get-Specialist $_ } | Where-Object { $_ }) } else { @(Get-RelevantSpecialists -Task $Task) }
    $req = [pscustomobject]@{ task = $Task; context = $Context; now = $Now }
    $reports = @($specs | ForEach-Object { Invoke-Specialist -Name $_.name -Request $req })
    return (Merge-SpecialistReports -Reports @($reports) -Task $Task -Context $Context)
}

# Is a question something Tony should DELEGATE (a status/review/what-happened
# ask), rather than answer directly? Conservative on purpose - most questions
# are answered by Tony without convening the workforce.
function Test-WorkforceRelevant {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
    return [bool]($Text -match "(?i)\b(what happened|catch me up|caught up|overnight|since (yesterday|last night)|bring me up to speed|status|what.?s (new|going on|the latest)|review my|summarize my|what needs (my )?attention|where do (things|we) stand|run the numbers|debrief|whats new)\b")
}
