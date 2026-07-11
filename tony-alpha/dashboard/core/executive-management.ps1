# =====================================================================
# executive-management.ps1  -  Tony as EXECUTIVE MANAGER
# ---------------------------------------------------------------------
# D20 gave Tony a Workforce he could delegate to. This layer promotes Tony
# from a delegator into a MANAGER: he does not simply call every relevant
# specialist - he decides who works, who begins first, who verifies, who is
# skipped, when the evidence is enough, and when uncertainty needs another
# opinion. Then he presents ONE recommendation.
#
# This is a PURE module built ON TOP of the Workforce Engine (D20). It does
# NOT redesign it: it reuses Get-RelevantSpecialists, Invoke-Specialist,
# Test-ReportAcceptable, and Merge-SpecialistReports (which keeps the Decision
# Framework as final authority). It stores nothing, holds no global state,
# takes no actions, and adds no provider calls of its own.
#
# Management principles implemented here:
#   * Rule of Progressive Delegation - the fewest specialists necessary to
#     confidently answer the question (narrow questions stop at the first
#     confident report; broad "what happened" questions consult breadth).
#   * Executive Awareness Principle - nothing meaningful is dropped; skips and
#     conflicts are recorded and surfaced, never hidden.
#   * Trust Through Evidence - confidence is earned from evidence, not authority
#     (deterministic trust scoring; NO invented history).
#   * Least Necessary Work - unavailable specialists are never woken; a shared
#     Executive Context is reused so no specialist re-calls a provider; a report
#     is never computed twice in one run (in-run ledger).
#   * Human Attention Is Precious - one recommendation, with transparency.
# =====================================================================

$ErrorActionPreference = 'Stop'

# --- breadth of the question (deterministic) -------------------------
# Broad "brief me on everything" asks need coverage from all relevant
# specialists (breadth IS the answer). Narrow asks want the fewest.
function Test-BroadQuestion {
    param([string]$Task)
    if ([string]::IsNullOrWhiteSpace($Task)) { return $false }
    return [bool]($Task -match '(?i)\b(what happened|catch me up|caught up|overnight|since (yesterday|last night)|brief me|rundown|run.?down|debrief|where do (we|things) stand|everything|full picture|complete picture|status|summar(y|ize) (my|everything)|bring me up to speed)\b')
}

# --- Trust model (deterministic; no persistence, no invented history) -
# Every specialist exposes: current confidence, historical reliability,
# evidence quality, last successful review, known limitations. Because GIOK
# stores NO history, historical reliability is an explicit DETERMINISTIC
# BASELINE (from availability), never a fabricated track record.
function Get-SpecialistTrust {
    param([Parameter(Mandatory)] $Specialist, $Report = $null, [datetime]$Now = (Get-Date))
    $avail = $true; $availDetail = ''
    if ($Specialist.status) { try { $st = & $Specialist.status; $avail = [bool]$st.available; $availDetail = [string]$st.detail } catch { $avail = $false; $availDetail = 'status error' } }

    $historical = if ($avail) { 0.7 } else { 0.3 }   # deterministic baseline, NOT history
    $currentConfidence = if ($Report) { [double]$Report.confidence } else { $null }

    $evidenceQuality = 0.0
    if ($Report) {
        $ev = @($Report.evidence)
        $cnt = $ev.Count
        $withId = @($ev | Where-Object { $_.sourceId }).Count
        if ($cnt -gt 0) {
            $breadth = [math]::Min(1.0, $cnt / 3.0)
            $provenance = 0.5 + 0.5 * ($withId / [double]$cnt)
            $evidenceQuality = [math]::Round($breadth * $provenance, 2)
        }
        if ($Report.status -ne 'ok') { $evidenceQuality = [math]::Round($evidenceQuality * 0.5, 2) }
    }

    $lastSuccessful = if ($Report -and $Report.status -eq 'ok') { $Now } else { $null }

    $limitations = @()
    if (-not $avail) { $limitations += 'tool not present / not connected' }
    if ($Report -and ($Report.status -in @('no-data', 'unavailable'))) { $limitations += ('no data (' + $Report.status + ')') }
    $limitations += 'read-only; analyzes existing sources; never acts'

    $confForScore = if ($null -ne $currentConfidence) { $currentConfidence } else { $historical }
    $trustScore = [math]::Round((0.5 * $confForScore) + (0.3 * $evidenceQuality) + (0.2 * $historical), 2)

    return [pscustomobject]@{
        specialist            = $Specialist.name
        available             = $avail
        availabilityDetail    = $availDetail
        currentConfidence     = $currentConfidence
        historicalReliability = $historical
        historicalBasis       = 'deterministic-baseline (no review history is stored)'
        evidenceQuality       = $evidenceQuality
        lastSuccessfulReview  = $lastSuccessful
        knownLimitations      = @($limitations)
        trustScore            = $trustScore
    }
}

# Rank relevant specialists: available first, then by name (stable/deterministic).
# "Who begins first" = the first entry.
function Get-ManagedRanking {
    param($Specialists, [datetime]$Now = (Get-Date))
    return @($Specialists | Sort-Object -Property `
            @{ Expression = { if ((Get-SpecialistTrust -Specialist $_ -Now $Now).available) { 0 } else { 1 } } }, `
            @{ Expression = { [string]$_.name } })
}

# Is the accepted evidence enough to stop? Every scope seen so far must be
# covered by a report at/above the confidence floor, with no unresolved conflict.
function Test-EvidenceSufficient {
    param($Accepted, [double]$ConfidenceFloor = 0.6)
    $acc = @($Accepted | Where-Object { $_ })
    if ($acc.Count -eq 0) { return $false }
    if (@(Get-WorkforceConflicts -Accepted $acc).Count -gt 0) { return $false }
    return [bool](@($acc | Where-Object { $_.confidence -ge $ConfidenceFloor }).Count -gt 0)
}

# Conflicts = two accepted reports on the SAME scope with opposing assessments.
function Get-WorkforceConflicts {
    param($Accepted)
    $acc = @($Accepted | Where-Object { $_ })
    $out = @()
    for ($i = 0; $i -lt $acc.Count; $i++) {
        for ($j = $i + 1; $j -lt $acc.Count; $j++) {
            $a = $acc[$i]; $b = $acc[$j]
            if ($a.scope -and ($a.scope -eq $b.scope) -and ($a.assessment -ne $b.assessment) -and ($a.assessment -in @('needs-attention', 'clear')) -and ($b.assessment -in @('needs-attention', 'clear'))) {
                $out += [pscustomobject]@{ scope = $a.scope; between = @($a.specialist, $b.specialist); a = $a.assessment; b = $b.assessment; aConfidence = $a.confidence; bConfidence = $b.confidence }
            }
        }
    }
    return @($out)
}

# Explain a disagreement and lean toward the better-evidenced side, but ALWAYS
# surface it - Tony never hides uncertainty.
function Resolve-WorkforceConflict {
    param($Conflicts, $Accepted)
    $items = @()
    foreach ($c in @($Conflicts)) {
        $lean = if ($c.aConfidence -gt $c.bConfidence) { $c.between[0] } elseif ($c.bConfidence -gt $c.aConfidence) { $c.between[1] } else { 'neither (evenly matched)' }
        $items += [pscustomobject]@{
            scope         = $c.scope
            between       = @($c.between)
            explanation   = ('{0} says "{1}" while {2} says "{3}" about {4}.' -f $c.between[0], $c.a, $c.between[1], $c.b, $c.scope)
            leaning       = $lean
            surfaceToJake = $true
        }
    }
    return [pscustomobject]@{ hasConflict = [bool](@($items).Count -gt 0); items = @($items) }
}

# =====================================================================
# THE management call: Tony delegates INTELLIGENTLY and merges into ONE
# recommendation. Returns a SUPERSET of Merge-SpecialistReports (so every
# existing consumer keeps working) plus the management record.
# =====================================================================
function Invoke-ExecutiveManager {
    param(
        [string]$Task,
        $Context = $null,
        [datetime]$Now = (Get-Date),
        [int]$MaxSpecialists = 6,
        [string[]]$Only = @(),
        [double]$ConfidenceFloor = 0.6,
        [double]$VerifyThreshold = 0.5
    )
    if (-not (Get-Command Get-Specialists -ErrorAction SilentlyContinue)) {
        return [pscustomobject]@{ source = 'executive-management'; managed = $true; task = $Task; error = 'Workforce Engine not loaded.'; specialistsUsed = @(); reports = @(); confidence = 0.0; conflicts = @(); needsVerification = $false; showRawToJake = $false; summary = 'The Workforce is not available.'; generatedAt = $Now }
    }

    $relevant = if (@($Only).Count -gt 0) { @($Only | ForEach-Object { Get-Specialist $_ } | Where-Object { $_ }) } else { @(Get-RelevantSpecialists -Task $Task) }
    $ranked = @(Get-ManagedRanking -Specialists $relevant -Now $Now)
    $broad = Test-BroadQuestion -Task $Task

    $considered = @($ranked | ForEach-Object { $_.name })
    $beginsWith = if (@($ranked).Count -gt 0) { $ranked[0].name } else { $null }

    $req = [pscustomobject]@{ task = $Task; context = $Context; now = $Now }
    $ledger = @{}          # name -> report (in-run only; no specialist analyzed twice)
    $reuseCount = 0

    $used = @(); $skipped = @(); $trustProfiles = @(); $verifications = @()
    $acceptedList = @()

    foreach ($s in $ranked) {
        $pre = Get-SpecialistTrust -Specialist $s -Now $Now
        if (-not $pre.available) {
            $skipped += [pscustomobject]@{ specialist = $s.name; reason = 'unavailable / not connected - not woken (least necessary work)' }
            $trustProfiles += $pre
            continue
        }
        if ($used.Count -ge $MaxSpecialists) {
            $skipped += [pscustomobject]@{ specialist = $s.name; reason = ('specialist cap reached ({0})' -f $MaxSpecialists) }
            continue
        }
        # Progressive delegation: on a NARROW question, once we already have a
        # confident, conflict-free answer, do not wake more specialists.
        if (-not $broad -and (Test-EvidenceSufficient -Accepted $acceptedList -ConfidenceFloor $ConfidenceFloor)) {
            $skipped += [pscustomobject]@{ specialist = $s.name; reason = 'question already answered confidently by fewer specialists (progressive delegation)' }
            continue
        }

        # evidence reuse: a specialist is never analyzed twice in one run
        if ($ledger.ContainsKey($s.name)) { $report = $ledger[$s.name]; $reuseCount++ }
        else { $report = Invoke-Specialist -Name $s.name -Request $req; $ledger[$s.name] = $report }
        $used += $s.name
        $trust = Get-SpecialistTrust -Specialist $s -Report $report -Now $Now
        $trustProfiles += $trust

        if (Test-ReportAcceptable $report) {
            $acceptedList += $report
            # Low-confidence escalation: a weak-but-usable report earns a second
            # opinion. The loop naturally continues to the next ranked specialist
            # (recorded as a verification below if it corroborates the same scope).
            if ($trust.trustScore -lt $VerifyThreshold) {
                $verifications += [pscustomobject]@{ trigger = $s.name; scope = $report.scope; reason = ('low trust ({0}) - seeking corroboration' -f $trust.trustScore); verifier = $null; outcome = 'pending' }
            }
        }
    }

    # Record specialists that were confidently skipped on a narrow question but
    # never even reached the loop tail (already captured above). Now resolve
    # verification outcomes: did a later same-scope report corroborate or conflict?
    foreach ($v in $verifications) {
        $sameScope = @($acceptedList | Where-Object { $_.scope -eq $v.scope -and $_.specialist -ne $v.trigger })
        if (@($sameScope).Count -gt 0) {
            $trg = @($acceptedList | Where-Object { $_.specialist -eq $v.trigger } | Select-Object -First 1)
            $agree = [bool](@($sameScope | Where-Object { $_.assessment -eq $trg.assessment }).Count -gt 0)
            $v.verifier = @($sameScope | ForEach-Object { $_.specialist }) -join ', '
            $v.outcome = if ($agree) { 'corroborated' } else { 'disagreed (conflict surfaced)' }
        }
        else {
            $v.outcome = 'no same-scope verifier available - flagged as a lead, not a certainty'
        }
    }

    # Conflict detection + arbitration (surfaced, never hidden).
    $conflicts = @(Get-WorkforceConflicts -Accepted $acceptedList)
    $arbitration = Resolve-WorkforceConflict -Conflicts $conflicts -Accepted $acceptedList

    # Final synthesis via the Workforce Engine's merge (Decision Framework keeps
    # FINAL authority inside it). We build ON TOP - we do not replace it.
    $decision = Merge-SpecialistReports -Reports $acceptedList -Task $Task -Context $Context

    # Management-level reasoning (one honest sentence).
    $mgmtReasoning =
    if (@($used).Count -eq 0) { 'No relevant specialist was available to consult.' }
    elseif ($conflicts.Count -gt 0) { ('Consulted {0} specialist(s); they disagreed on {1}, which I am surfacing for you.' -f @($used).Count, ((@($conflicts | ForEach-Object { $_.scope }) | Select-Object -Unique) -join ', ')) }
    elseif ($broad) { ('Broad question: consulted all {0} available specialist(s) for full coverage.' -f @($used).Count) }
    else { ('Answered with the fewest specialists needed: consulted {0}, skipped {1}.' -f @($used).Count, @($skipped).Count) }

    # Augment the merge result with the management record (superset - backward
    # compatible with every existing consumer of the workforce object).
    $out = $decision
    $add = {
        param($name, $value)
        if ($out.PSObject.Properties.Name -contains $name) { $out.$name = $value } else { $out | Add-Member -NotePropertyName $name -NotePropertyValue $value -Force }
    }
    & $add 'source' 'executive-management'
    & $add 'managed' $true
    & $add 'broadQuestion' $broad
    & $add 'plan' ([pscustomobject]@{ considered = @($considered); beginsWith = $beginsWith; broad = $broad })
    & $add 'specialistsConsidered' @($considered)
    & $add 'specialistsSkipped' @($skipped)
    & $add 'verifications' @($verifications)
    & $add 'trust' @($trustProfiles)
    & $add 'arbitration' $arbitration
    & $add 'reuseCount' $reuseCount
    & $add 'managementReasoning' $mgmtReasoning
    # keep needsVerification honest: also true when a low-trust report had no verifier
    if (@($verifications | Where-Object { $_.outcome -like 'no same-scope*' }).Count -gt 0) { & $add 'needsVerification' $true }
    if ($arbitration.hasConflict) { & $add 'showRawToJake' $true }
    return $out
}

# Convenience: trust snapshot for all specialists relevant to a task, WITHOUT
# invoking any analyze (pure planning view). Useful for diagnostics/tests.
function Get-WorkforceTrustSnapshot {
    param([string]$Task, [datetime]$Now = (Get-Date))
    $relevant = @(Get-RelevantSpecialists -Task $Task)
    return @(Get-ManagedRanking -Specialists $relevant -Now $Now | ForEach-Object { Get-SpecialistTrust -Specialist $_ -Now $Now })
}
