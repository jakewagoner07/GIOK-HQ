# =====================================================================
# async-run.ps1  -  Off-UI-thread read-only work (Epic 9, Phase 2/5)
# ---------------------------------------------------------------------
# Measurement proved the deferred Home briefing ran the ENTIRE provider +
# context build (~35-40s cold) as one task on the WPF dispatcher, freezing
# the UI after Home painted. This helper runs that heavy READ-ONLY work on a
# persistent background runspace and returns only the finished, immutable
# data MODEL. The UI thread builds the WPF card from that model - the only
# thing that touches the dispatcher. Completion is detected by polling the
# async result from a DispatcherTimer (UI thread), so there is no cross-thread
# WPF access and no marshaling subtlety.
#
# Safety: ONE reusable worker runspace (modules loaded once, off-thread);
# in-flight instances are tracked and disposed; Stop-AsyncWorkers tears the
# whole thing down on window close so no orphan runspaces or file locks leak.
# The worker only ever READS (providers are read-only; no writes anywhere).
# =====================================================================

$ErrorActionPreference = 'Stop'

$script:AsyncWorkerRs = $null          # persistent worker runspace
$script:AsyncInFlight = New-Object System.Collections.ArrayList  # @{ ps; timer } to clean up
$script:AsyncDashRoot = $null          # dashboard dir (set by dashboard.ps1)

function Set-AsyncDashboardRoot { param([string]$Path) $script:AsyncDashRoot = $Path }

# Core + provider modules the worker needs to fetch signals and build a briefing
# MODEL. UI/theme are NOT loaded - the worker never builds WPF. Order matches
# dashboard.ps1 (registration side-effects depend on it).
$script:AsyncCoreMods = @('tony-core','action-items','capture','morning-brief','morning-experience','identity','life-os','executive-inbox','conversational-capture','end-of-day-audit','first-conversation','command-bar','tony-provider-contract','tony-decision-framework','tony-brain','tony-conversation','tony-observations','memory-manager','executive-cache','live-providers','google-oauth','email-intelligence','communications','crm-intelligence','executive-context','executive-priority','executive-timeline','executive-briefing','document-intelligence','workforce-engine','workforce-specialists','workforce-proposals','executive-management')
$script:AsyncProvMods = @('claude-provider','weather-provider','google-calendar-provider','gmail-provider','yahoo-provider','gohighlevel-provider')

function Get-AsyncWorkerRunspace {
    if ($script:AsyncWorkerRs -and $script:AsyncWorkerRs.RunspaceStateInfo.State -eq 'Opened') { return $script:AsyncWorkerRs }
    $rs = [runspacefactory]::CreateRunspace()
    $rs.ApartmentState = 'MTA'          # no WPF on the worker
    $rs.ThreadOptions = 'ReuseThread'
    $rs.Open()
    # Share the UI thread's synchronized signal cache into the worker so the worker
    # warms the SAME cache the UI-thread Inbox scan reads (one fetch per window).
    $shared = Get-Variable -Name GiokCache -Scope Script -ValueOnly -ErrorAction SilentlyContinue
    if ($shared) { try { $rs.SessionStateProxy.SetVariable('GiokSharedCache', $shared) } catch { } }
    $script:AsyncWorkerRs = $rs
    return $rs
}

# Is the async path usable? (Off when no dashboard root, e.g. isolated tests.)
function Test-AsyncAvailable { return [bool]$script:AsyncDashRoot }

# Run $Work (a scriptblock that returns immutable data) on the worker runspace;
# when it finishes, call $OnComplete($result) on the UI thread. $ArgList is
# passed to $Work. Never throws to the caller; on worker error $OnComplete gets
# $null so the caller can show a calm degraded state.
function Start-AsyncWork {
    param(
        [Parameter(Mandatory)][scriptblock]$Work,
        [Parameter(Mandatory)][scriptblock]$OnComplete,
        [object[]]$ArgList = @(),
        [int]$PollMs = 100
    )
    $rs = Get-AsyncWorkerRunspace
    $ps = [powershell]::Create(); $ps.Runspace = $rs
    [void]$ps.AddScript($Work)
    foreach ($a in $ArgList) { [void]$ps.AddArgument($a) }
    $handle = $ps.BeginInvoke()
    $entry = @{ ps = $ps; timer = $null }
    [void]$script:AsyncInFlight.Add($entry)
    # Capture a LOCAL reference to the tracking list: inside a GetNewClosure body
    # $script:* resolves to the closure's own (empty) scope, so the shared list
    # must be reached through a captured local (it is a reference type, so the
    # Remove still mutates the one real list).
    $inflight = $script:AsyncInFlight

    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds($PollMs)
    $entry.timer = $timer
    $timer.Add_Tick({
        if (-not $handle.IsCompleted) { return }
        $timer.Stop()
        $result = $null
        try { $result = $ps.EndInvoke($handle) } catch { $result = $null }
        try { $ps.Dispose() } catch { }
        [void]$inflight.Remove($entry)
        # $OnComplete runs here on the UI thread (DispatcherTimer tick) - the only
        # place WPF is touched. A single unwrapped result is passed straight through.
        $payload = if ($result -is [System.Collections.IEnumerable] -and $result -isnot [string] -and @($result).Count -eq 1) { @($result)[0] } else { $result }
        try { & $OnComplete $payload } catch { }
    }.GetNewClosure())
    $timer.Start()
    return $entry
}

# Build the worker scriptblock (Home briefing MODEL) with the module lists baked
# in. The worker loads modules ONCE, fetches signals through the shared cached
# wrappers, and returns the pure data model - no WPF, no writes.
# Returns a scriptblock: param($DashRoot,$NowTicks,$Name).
function Get-AsyncBriefingWork {
    $coreList = ($script:AsyncCoreMods | ForEach-Object { "'$_'" }) -join ','
    $provList = ($script:AsyncProvMods | ForEach-Object { "'$_'" }) -join ','
    $text = @"
param(`$DashRoot, `$NowTicks, `$Name)
`$ErrorActionPreference = 'Stop'
if (-not `$global:GiokWorkerLoaded) {
    `$core = Join-Path `$DashRoot 'core'; `$prov = Join-Path `$DashRoot 'providers'
    foreach (`$m in @($coreList)) { . (Join-Path `$core ("`$m.ps1")) }
    foreach (`$p in @($provList)) { . (Join-Path `$prov ("`$p.ps1")) }
    `$global:GiokWorkerLoaded = `$true
}
`$now = [datetime]`$NowTicks
`$cal = `$null; if (Get-Command Get-CalendarSignal -ErrorAction SilentlyContinue) { try { `$cal = Get-CalendarSignal -Now `$now } catch { `$cal = `$null } }
`$em  = `$null; if (Get-Command Get-CommunicationsSignal -ErrorAction SilentlyContinue) { try { `$em = Get-CommunicationsSignal -Now `$now } catch { `$em = `$null } }
if (Get-Command Get-TonyExecutiveBriefing -ErrorAction SilentlyContinue) {
    try { return (Get-TonyExecutiveBriefing -CurrentWorkspace 'Home' -Now `$now -Name `$Name -Calendar `$cal -Email `$em) } catch { return `$null }
}
return `$null
"@
    return [scriptblock]::Create($text)
}

# Dispose every in-flight instance and the worker runspace. Call on window close.
function Stop-AsyncWorkers {
    foreach ($e in @($script:AsyncInFlight)) {
        try { if ($e.timer) { $e.timer.Stop() } } catch { }
        try { if ($e.ps) { $e.ps.Stop(); $e.ps.Dispose() } } catch { }
    }
    $script:AsyncInFlight.Clear()
    try { if ($script:AsyncWorkerRs) { $script:AsyncWorkerRs.Close(); $script:AsyncWorkerRs.Dispose() } } catch { }
    $script:AsyncWorkerRs = $null
}

# Diagnostics: counts only, no content.
function Get-AsyncStats {
    [pscustomobject]@{ inFlight = @($script:AsyncInFlight).Count; workerOpen = [bool]($script:AsyncWorkerRs -and $script:AsyncWorkerRs.RunspaceStateInfo.State -eq 'Opened') }
}
