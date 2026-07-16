# =====================================================================
# Run-ReasoningTests.ps1 - the Executive Reasoning Layer test suite
# ---------------------------------------------------------------------
# Runs every *.tests.ps1 in this folder and reports one summary.
#
#   .\Run-ReasoningTests.ps1
#   .\Run-ReasoningTests.ps1 -Filter hostile      # only files matching *hostile*
#   .\Run-ReasoningTests.ps1 -Verbose             # stream each file's own output
#
# Exit code is 0 only if every file passed - non-zero otherwise, so this is
# usable from a hook, a script, or CI without reading the text.
#
# Each file runs in its OWN PowerShell process. That is deliberate: the provider
# registry is process-global module state, and a test that registers a hostile
# driver must not be able to leak it into the next file. Isolation by process is
# the cheap, obvious way to guarantee that.
#
# No network. No API keys. No provider calls. Windows PowerShell 5.1 (STA).
# =====================================================================

[CmdletBinding()]
param(
    [string]$Filter = '*'
)

$ErrorActionPreference = 'Stop'

$files = @(Get-ChildItem -Path $PSScriptRoot -Filter '*.tests.ps1' -File | Sort-Object Name)
if ($Filter -ne '*') { $files = @($files | Where-Object { $_.Name -like ("*{0}*" -f $Filter) }) }

if ($files.Count -eq 0) {
    Write-Host ("No test files matched filter '{0}' in {1}" -f $Filter, $PSScriptRoot)
    exit 1
}

Write-Host ''
Write-Host '======================================================================'
Write-Host ' Executive Reasoning Layer - test suite'
Write-Host (' {0} test file(s) in {1}' -f $files.Count, $PSScriptRoot)
Write-Host '======================================================================'

$results = @()
$sw = [Diagnostics.Stopwatch]::StartNew()

foreach ($f in $files) {
    Write-Host ''
    Write-Host ('---- {0} ----' -f $f.Name)
    $fsw = [Diagnostics.Stopwatch]::StartNew()

    # -File (not -Command) so the child's exit code is the script's exit code.
    $out = & powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File $f.FullName 2>&1
    $code = $LASTEXITCODE
    $fsw.Stop()

    $summary = @($out | Where-Object { $_ -match ': \d+ passed,' } | Select-Object -Last 1)
    $failLines = @($out | Where-Object { $_ -match '\[FAIL\]' })

    if ($VerbosePreference -eq 'Continue') {
        $out | ForEach-Object { Write-Host ("   {0}" -f $_) }
    }
    else {
        if ($summary.Count -gt 0) { Write-Host ("   {0}" -f $summary[0]) }
        foreach ($fl in $failLines) { Write-Host ("   {0}" -f $fl) }
        # a file that crashed rather than asserting has no summary line - show why
        if ($summary.Count -eq 0) {
            Write-Host '   (no summary line - the file did not complete; last output follows)'
            $out | Select-Object -Last 12 | ForEach-Object { Write-Host ("   {0}" -f $_) }
        }
    }

    $results += [pscustomobject]@{
        Name     = $f.Name
        ExitCode = $code
        Passed   = ($code -eq 0)
        Ms       = $fsw.ElapsedMilliseconds
    }
}

$sw.Stop()

Write-Host ''
Write-Host '======================================================================'
Write-Host ' SUMMARY'
Write-Host '======================================================================'
foreach ($r in $results) {
    Write-Host ('  {0,-42} {1,-6} {2,6} ms' -f $r.Name, $(if ($r.Passed) { 'PASS' } else { 'FAIL' }), $r.Ms)
}

$failed = @($results | Where-Object { -not $_.Passed })
Write-Host ''
if ($failed.Count -gt 0) {
    Write-Host ('RESULT: {0} of {1} test file(s) FAILED ({2:N1}s)' -f $failed.Count, $results.Count, ($sw.Elapsed.TotalSeconds))
    foreach ($r in $failed) { Write-Host ('  FAILED: {0} (exit {1})' -f $r.Name, $r.ExitCode) }
    exit 1
}
Write-Host ('RESULT: all {0} test file(s) passed ({1:N1}s)' -f $results.Count, ($sw.Elapsed.TotalSeconds))
exit 0
