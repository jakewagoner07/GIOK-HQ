# =====================================================================
# identity-transaction.tests.ps1 - the atomic identity write
# ---------------------------------------------------------------------
# Approval is the ONLY path that writes Identity, and it must be all-or-nothing:
# a half-written identity is worse than no write at all. Invoke-IdentityTransaction
# serializes everything up front, snapshots what is on disk, writes, and restores
# every snapshot if any single write fails.
#
# WHY THIS FILE EXISTS IN ITS CURRENT FORM
# The scratchpad version of this test used [double]::NaN as a stand-in for "an
# object that cannot be serialized". That assumption is FALSE on Windows
# PowerShell 5.1: ConvertTo-Json happily emits {"n": NaN} (invalid JSON, no
# error), so the transaction succeeded, wrote the file, and the assertion failed
# for a reason that had nothing to do with the code under test. The old assertion
# was also self-cancelling - it read
#     PF($g2 -eq 'PRE-goals' -or $g2 -eq 'PRE-goals')
# i.e. the same condition twice, a copy/paste artifact that made the -or pointless.
#
# Both are fixed here. The serialization-failure fixture is now a hashtable keyed
# by a non-string object, which makes ConvertTo-Json throw deterministically -
# verified across both $ErrorActionPreference settings and repeated runs. The
# write-failure fixture is a read-only file, which is likewise deterministic.
#
# Production behaviour is NOT changed by this file. These are tests only.
# =====================================================================

. (Join-Path $PSScriptRoot '_harness.ps1')
Assert-Sandboxed

$dir = Get-IdentityDir

function Reset-Store {
    Get-ChildItem $dir -File -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
    Set-Content (Join-Path $dir 'goals.json') -Value '{"marker":"BASE-goals"}' -Encoding UTF8
    Set-Content (Join-Path $dir 'values.json') -Value '{"marker":"BASE-values"}' -Encoding UTF8
    # overview.json deliberately absent: it must not be left behind by a failure
}

function Get-Marker {
    param([string]$File)
    $p = Join-Path $dir $File
    if (-not (Test-Path $p)) { return '<absent>' }
    try { return [string]((Get-Content $p -Raw | ConvertFrom-Json).marker) } catch { return '<unparseable>' }
}

# A hashtable keyed by an OBJECT rather than a string. ConvertTo-Json throws on
# this deterministically - this is a real serialization failure, not an assumed one.
function New-UnserializableObject {
    $h = @{}
    $h[[pscustomobject]@{ key = 1 }] = 'value'
    return $h
}

# =====================================================================
Write-TestSection 'the fixtures themselves behave as assumed'
# =====================================================================
# Guard the guards: if these ever stop holding, every test below is meaningless.
$threw = $false
try { [void](New-UnserializableObject | ConvertTo-Json -Depth 12) } catch { $threw = $true }
Assert-True $threw 'the unserializable fixture really does make ConvertTo-Json throw'

$nanSerialized = $false
try { $j = [pscustomobject]@{ n = [double]::NaN } | ConvertTo-Json -Depth 12; $nanSerialized = ($j -match 'NaN') } catch { $nanSerialized = $false }
Write-TestNote ("platform fact: NaN does NOT fail ConvertTo-Json on PS 5.1 (serialized={0}) - never use it as a failure fixture" -f $nanSerialized)

# =====================================================================
Write-TestSection 'TEST A: a successful transaction writes everything'
# =====================================================================
Reset-Store
$ok = Invoke-IdentityTransaction -Writes @{
    'goals.json'    = [pscustomobject]@{ marker = 'NEW-goals' }
    'values.json'   = [pscustomobject]@{ marker = 'NEW-values' }
    'overview.json' = [pscustomobject]@{ marker = 'NEW-overview' }
}
Assert-True ($ok -eq $true) 'the transaction reports success'
Assert-True ((Get-Marker 'goals.json') -eq 'NEW-goals') ("goals.json committed (got '{0}')" -f (Get-Marker 'goals.json'))
Assert-True ((Get-Marker 'values.json') -eq 'NEW-values') ("values.json committed (got '{0}')" -f (Get-Marker 'values.json'))
Assert-True ((Get-Marker 'overview.json') -eq 'NEW-overview') ("overview.json created (got '{0}')" -f (Get-Marker 'overview.json'))

# =====================================================================
Write-TestSection 'TEST B: a mid-transaction WRITE failure rolls everything back'
# =====================================================================
Reset-Store
$ro = Join-Path $dir 'values.json'
(Get-Item $ro).IsReadOnly = $true          # deterministic write failure
try {
    $ok2 = Invoke-IdentityTransaction -Writes @{
        'goals.json'    = [pscustomobject]@{ marker = 'SHOULD-NOT-PERSIST' }
        'values.json'   = [pscustomobject]@{ marker = 'SHOULD-NOT-PERSIST' }
        'overview.json' = [pscustomobject]@{ marker = 'SHOULD-NOT-PERSIST' }
    }
}
finally {
    if (Test-Path $ro) { (Get-Item $ro).IsReadOnly = $false }
}
Assert-True ($ok2 -eq $false) 'the transaction reports failure (returned false)'
Assert-True ((Get-Marker 'goals.json') -eq 'BASE-goals') ("goals.json rolled back to its original content (got '{0}')" -f (Get-Marker 'goals.json'))
Assert-True ((Get-Marker 'values.json') -eq 'BASE-values') ("values.json unchanged (got '{0}')" -f (Get-Marker 'values.json'))
Assert-True ((Get-Marker 'overview.json') -eq '<absent>') 'overview.json did not exist before, so it is not left behind'
# Note: Invoke-IdentityTransaction iterates a hashtable, so write ORDER is not
# guaranteed. The assertions above hold for every order - that is the point of
# all-or-nothing.

# =====================================================================
Write-TestSection 'TEST C: an unserializable object aborts BEFORE touching disk'
# =====================================================================
# This is the assertion the NaN fixture was never actually testing. The guarantee:
# serialization happens up front, so a bad object leaves the store byte-identical.
Reset-Store
$beforeGoals = [System.IO.File]::ReadAllText((Join-Path $dir 'goals.json'))
$beforeValues = [System.IO.File]::ReadAllText((Join-Path $dir 'values.json'))
$threwAtCaller = $false
$ok3 = $null
try {
    $ok3 = Invoke-IdentityTransaction -Writes @{
        'goals.json'  = [pscustomobject]@{ marker = 'SHOULD-NOT-PERSIST' }
        'values.json' = (New-UnserializableObject)
    }
}
catch { $threwAtCaller = $true }
Assert-True (-not $threwAtCaller) 'a bad object never throws into the approval UI - the transaction returns instead'
Assert-True ($ok3 -eq $false) 'the transaction reports failure for an unserializable write'
Assert-True (([System.IO.File]::ReadAllText((Join-Path $dir 'goals.json'))) -eq $beforeGoals) 'goals.json is BYTE-IDENTICAL - the good write never happened either'
Assert-True (([System.IO.File]::ReadAllText((Join-Path $dir 'values.json'))) -eq $beforeValues) 'values.json is BYTE-IDENTICAL'
Assert-True ((Get-Marker 'goals.json') -eq 'BASE-goals') ("goals.json still holds its original marker (got '{0}')" -f (Get-Marker 'goals.json'))

# =====================================================================
Write-TestSection 'TEST D: the store is untouched by a no-op'
# =====================================================================
Reset-Store
$before = @{}
foreach ($f in @('goals.json', 'values.json')) { $before[$f] = [System.IO.File]::ReadAllText((Join-Path $dir $f)) }
$ok4 = Invoke-IdentityTransaction -Writes @{}
Assert-True ($ok4 -eq $true) 'an empty transaction succeeds trivially'
$unchanged = $true
foreach ($f in @('goals.json', 'values.json')) { if ([System.IO.File]::ReadAllText((Join-Path $dir $f)) -ne $before[$f]) { $unchanged = $false } }
Assert-True $unchanged 'an empty transaction leaves every file byte-identical'

Complete-TestFile 'identity-transaction'
