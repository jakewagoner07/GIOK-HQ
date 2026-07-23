# =====================================================================
# owner-create-ids.tests.ps1 - the owner create-with-id contract (Epic 16A)
# ---------------------------------------------------------------------
# Every supported owner-create function accepts an optional caller-supplied STABLE
# id: when omitted, behaviour is unchanged (sequential); when supplied, the EXACT id
# is persisted after two gates - well-formed for the owner, and not a duplicate. This
# is the contract the Action Engine relies on to pre-allocate ids and verify by exact
# identity. Every store is sandboxed.
# =====================================================================

. (Join-Path $PSScriptRoot '_harness.ps1')
Assert-Sandboxed

# =====================================================================
Write-TestSection 'Add-Goal -Id contract'
# =====================================================================
$g = Add-Goal -Title 'Alpha' -Id 'G-Xabc12300'
Assert-True ($g -and $g.id -eq 'G-Xabc12300') 'supplied goal id is persisted EXACTLY'
Assert-True (@(Get-GoalsList | Where-Object { $_.id -eq 'G-Xabc12300' }).Count -eq 1) 'the owner returns/persists the actual id'
Assert-True ($null -eq (Add-Goal -Title 'dup' -Id 'G-Xabc12300')) 'a DUPLICATE goal id rejects safely (null)'
Assert-True ($null -eq (Add-Goal -Title 'bad' -Id 'MEM-999')) 'a wrong-prefix goal id rejects'
Assert-True ($null -eq (Add-Goal -Title 'bad2' -Id 'not an id')) 'a malformed goal id rejects'
$g2 = Add-Goal -Title 'Legacy caller'
Assert-True ($g2 -and $g2.id -match '^G-\d+$') 'the no-id (legacy) caller is unchanged (sequential G-NNN)'
Assert-True (@(Get-GoalsList | Where-Object { $_.title -eq 'Alpha' }).Count -eq 1) 'a rejected duplicate wrote NOTHING (still one Alpha)'

# =====================================================================
Write-TestSection 'Add-LifeItem -Id contract (all migrated domains)'
# =====================================================================
$lifeMap = @{ projects = 'PRJ'; nonNegotiables = 'NN'; family = 'FAM'; health = 'HL'; financial = 'FN'; agency = 'AG'; learning = 'LR' }
foreach ($dom in $lifeMap.Keys) {
    $prefix = $lifeMap[$dom]
    $id = ("{0}-Xfeed{1:00}" -f $prefix, ($prefix.Length))
    $r = Add-LifeItem -Domain $dom -Fields @{ title = ("T-$dom") } -Id $id
    Assert-True ($r -and $r.id -eq $id) ("Add-LifeItem [$dom]: supplied id persisted exactly")
    Assert-True ($null -eq (Add-LifeItem -Domain $dom -Fields @{ title = 'dup' } -Id $id)) ("Add-LifeItem [$dom]: duplicate id rejects")
    Assert-True ($null -eq (Add-LifeItem -Domain $dom -Fields @{ title = 'wrong' } -Id 'G-Xnope')) ("Add-LifeItem [$dom]: wrong-prefix id rejects")
    $r2 = Add-LifeItem -Domain $dom -Fields @{ title = ("L-$dom") }
    Assert-True ($r2 -and $r2.id -match ('^' + [regex]::Escape($prefix) + '-\d+$')) ("Add-LifeItem [$dom]: no-id caller unchanged")
}

# =====================================================================
Write-TestSection 'Approve-Memory -Id contract'
# =====================================================================
$m = Approve-Memory -Category 'Preferences' -Value 'likes tea' -Id 'MEM-Xbeef9900'
Assert-True ($m -and $m.id -eq 'MEM-Xbeef9900') 'supplied memory id persisted exactly'
Assert-True ($null -eq (Approve-Memory -Category 'Preferences' -Value 'dup' -Id 'MEM-Xbeef9900')) 'duplicate memory id rejects'
Assert-True ($null -eq (Approve-Memory -Category 'Preferences' -Value 'wrong' -Id 'G-Xnope')) 'wrong-prefix memory id rejects'
$m2 = Approve-Memory -Category 'Preferences' -Value 'no id'
Assert-True ($m2 -and $m2.id -match '^MEM-\d+$') 'no-id memory caller unchanged (MEM-NNN)'

# =====================================================================
Write-TestSection 'Get-InboxCreateId: deterministic, unique, owner-format, non-numeric'
# =====================================================================
Assert-True ((Get-InboxCreateId -Type 'goal' -Seed 'S1') -eq (Get-InboxCreateId -Type 'goal' -Seed 'S1')) 'same seed -> same id (stable across calls/restart)'
Assert-True ((Get-InboxCreateId -Type 'goal' -Seed 'S1') -ne (Get-InboxCreateId -Type 'goal' -Seed 'S2')) 'different seed -> different id (unique)'
Assert-True ((Get-InboxCreateId -Type 'goal' -Seed 'S1') -match '^G-X[0-9a-f]{8}$') 'id is <PREFIX>-X<8hex> (never <PREFIX>-<digits>, so it cannot collide with a sequential id)'
foreach ($pair in @(@('memory', 'MEM'), @('project', 'PRJ'), @('non-negotiable', 'NN'), @('family', 'FAM'), @('health', 'HL'), @('financial', 'FN'), @('agency', 'AG'), @('learning', 'LR'))) {
    Assert-True ((Get-InboxCreateId -Type $pair[0] -Seed 'S') -match ('^' + $pair[1] + '-X')) ("type '$($pair[0])' maps to prefix '$($pair[1])'")
}
Assert-True ((Get-InboxCreateId -Type 'unknown-type' -Seed 'S') -eq '') 'an unknown type yields no create id (empty)'

Complete-TestFile 'owner-create-ids'
