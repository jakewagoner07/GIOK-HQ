# =====================================================================
# _harness.ps1 - shared harness for the Executive Action Engine tests (Epic 15)
# ---------------------------------------------------------------------
# Loads the engine + its owner stores and redirects EVERY writable store into a
# throwaway %TEMP% sandbox: identity/goals, life_os, tony_memory, action_items,
# the executive inbox, AND the execution_log. Assert-Sandboxed refuses to run a
# single test unless every redirect took effect - a suite that can reach Jake's
# real data (the 11 runtime files) is not a test suite.
#
# No network. No API keys. Windows PowerShell 5.1.
# =====================================================================

$ErrorActionPreference = 'Stop'

$script:CoreDir = (Resolve-Path (Join-Path $PSScriptRoot '..\..\core')).Path
. (Join-Path $script:CoreDir 'tony-core.ps1')
. (Join-Path $script:CoreDir 'action-items.ps1')
. (Join-Path $script:CoreDir 'identity.ps1')
. (Join-Path $script:CoreDir 'life-os.ps1')
. (Join-Path $script:CoreDir 'memory-manager.ps1')
. (Join-Path $script:CoreDir 'executive-inbox.ps1')
. (Join-Path $script:CoreDir 'action-engine.ps1')

# ---- sandbox: one temp dir; every store path points inside it ----
$script:TestSandbox = Join-Path $env:TEMP ('giok-execution-tests-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path (Join-Path $script:TestSandbox 'identity') -Force | Out-Null

function Remove-TestSandbox {
    if ($script:TestSandbox -and (Test-Path $script:TestSandbox)) {
        Remove-Item $script:TestSandbox -Recurse -Force -ErrorAction SilentlyContinue
    }
}
try { Register-EngineEvent -SourceIdentifier ([System.Management.Automation.PsEngineEvent]::Exiting) -Action { Remove-TestSandbox } | Out-Null } catch { }

# THESE OVERRIDE the owner path resolvers. Order matters: after the dot-sources.
function Get-IdentityDir       { return (Join-Path $script:TestSandbox 'identity') }
function Get-ActionItemsPath   { return (Join-Path $script:TestSandbox 'action_items.json') }
function Get-InboxPath         { return (Join-Path $script:TestSandbox 'executive_inbox.json') }
function Get-ExecutionLogPath  { return (Join-Path $script:TestSandbox 'execution_log.json') }
function Get-LifeOsPath        { return (Join-Path $script:TestSandbox 'life_os.json') }
function Get-MemoryPath        { return (Join-Path $script:TestSandbox 'tony_memory.json') }

function Assert-Sandboxed {
    $repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..\..')).Path
    $paths = @{
        identity   = (Get-IdentityDir)
        actionItems = (Get-ActionItemsPath)
        inbox      = (Get-InboxPath)
        execLog    = (Get-ExecutionLogPath)
        lifeOs     = (Get-LifeOsPath)
        memory     = (Get-MemoryPath)
    }
    foreach ($k in $paths.Keys) {
        $p = [string]$paths[$k]
        if ([string]::IsNullOrWhiteSpace($p)) { throw ("HARNESS UNSAFE: {0} path is empty" -f $k) }
        if (-not $p.StartsWith($env:TEMP, [StringComparison]::OrdinalIgnoreCase)) { throw ("HARNESS UNSAFE: {0} not under TEMP: {1}" -f $k, $p) }
        if ($p.StartsWith($repo, [StringComparison]::OrdinalIgnoreCase)) { throw ("HARNESS UNSAFE: {0} points inside the repo: {1}" -f $k, $p) }
    }
}

# ---- assertions ----
$script:TestPass = 0
$script:TestFail = 0
$script:TestFailures = @()
function Assert-True {
    param([bool]$Condition, [Parameter(Mandatory)][string]$Message)
    if ($Condition) { $script:TestPass++; Write-Host ("  [PASS] {0}" -f $Message) }
    else { $script:TestFail++; $script:TestFailures += $Message; Write-Host ("  [FAIL] {0}" -f $Message) }
}
function Write-TestNote { param([Parameter(Mandatory)][string]$Message) Write-Host ("  [note] {0}" -f $Message) }
function Write-TestSection { param([Parameter(Mandatory)][string]$Title) Write-Host ''; Write-Host ("### {0} ###" -f $Title) }
function Complete-TestFile {
    param([Parameter(Mandatory)][string]$Name)
    Remove-TestSandbox
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
# create N action items in the sandboxed store, return their ids
function New-TestActionItems {
    param([int]$Count = 1, [string[]]$Titles)
    $ids = @()
    $d = Get-ActionItemsData
    for ($i = 0; $i -lt $Count; $i++) {
        $t = if ($Titles -and $i -lt $Titles.Count) { $Titles[$i] } else { ("Task {0}" -f ($i + 1)) }
        $id = Get-NextActionId -Data $d
        [void](Add-ActionItem -Data $d -Title $t -Id $id)
        $ids += $id
    }
    Save-ActionItemsData $d
    return , $ids   # comma prevents PowerShell unwrapping a single-element array to a scalar
}
function New-TestProposal {
    param([string]$Type = 'task', [string]$Title = 'Do a thing', [string]$Description = '', [string]$SourceId = '', [string]$Source = 'test')
    return (Add-InboxProposal -DiscoveredBy 'Tony' -Type $Type -Title $Title -Description $Description -Source $Source -SourceId $SourceId)
}
function Get-ExecHistoryStates { param([string]$Id) return @((Get-ExecutionById -Id $Id).history | ForEach-Object { [string]$_.state }) }
