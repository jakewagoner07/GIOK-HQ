# =====================================================================
# reasoning-claude.ps1  -  The Claude understanding driver (Epic 13)
# ---------------------------------------------------------------------
# The first real external reasoning driver. It serves EXACTLY ONE task -
# understanding.extract - by asking Claude to organize the seven onboarding
# answers into the existing Understanding Model. It plugs into the Epic 12
# kernel as a driver; the kernel routes to it, validates its output, and stamps
# provenance. This file never writes a store and never sets its own attribution.
#
# Availability = Claude configured AND consent granted for THIS attempt. An
# unavailable driver is not a candidate, so when consent is declined (or never
# asked) the kernel never invokes it and the answers never leave the machine.
#
# Reuses the existing gitignored Claude config and HTTP primitive (Get-ClaudeConfig,
# Invoke-ClaudeApi). No second secrets store. Logs no prompts, answers, responses,
# identity data, or credentials.
#
# STAGE 1 (this commit): the driver contract + availability gate. The prompt,
# strict-JSON parser, tighter grounding and bounded work land in stages 2-3.
# Until then invoke returns an honest not-implemented result, and the driver is
# dormant anyway (no consent path is wired yet, so isAvailable is false).
# =====================================================================

$ErrorActionPreference = 'Stop'

$script:ClaudeUnderstandingId = 'claude-understanding'

# ---- test seams (offline, no network) ---------------------------------
# The permanent regression suite must exercise this driver with MOCKED responses
# and MOCKED configuration - no key, no HTTP. These two overrides are the only
# way the mocks get in; production leaves them $null and the real functions run.
$script:ClaudeUnderstandingConfiguredOverride = $null   # $true/$false to force configured state in tests
$script:ClaudeUnderstandingCallOverride = $null          # scriptblock(state) -> raw text, or throw, to mock Claude

function Set-ClaudeUnderstandingConfiguredOverride { param($Value) $script:ClaudeUnderstandingConfiguredOverride = $Value }
function Set-ClaudeUnderstandingCallOverride { param([scriptblock]$ScriptBlock) $script:ClaudeUnderstandingCallOverride = $ScriptBlock }
function Clear-ClaudeUnderstandingOverrides { $script:ClaudeUnderstandingConfiguredOverride = $null; $script:ClaudeUnderstandingCallOverride = $null }

# ---- availability -----------------------------------------------------
# Is Claude usable at all? Reuses the provider's own configured check. A test may
# force this via the override. If the provider file is not loaded, we are honestly
# not configured (returns false), never throwing.
function Test-ClaudeUnderstandingConfigured {
    if ($null -ne $script:ClaudeUnderstandingConfiguredOverride) { return [bool]$script:ClaudeUnderstandingConfiguredOverride }
    if (-not (Get-Command Test-ClaudeConfigured -ErrorAction SilentlyContinue)) { return $false }
    try { return [bool](Test-ClaudeConfigured) } catch { return $false }
}

# The kernel's isAvailable() probe. Both conditions are required, and consent is
# checked LAST so that an unconfigured setup never even inspects consent.
function Test-ClaudeUnderstandingAvailable {
    if (-not (Test-ClaudeUnderstandingConfigured)) { return $false }
    if (-not (Get-Command Test-ExtractionConsent -ErrorAction SilentlyContinue)) { return $false }
    try { return [bool](Test-ExtractionConsent) } catch { return $false }
}

# ---- the driver object ------------------------------------------------
# Shape matches the Epic 12 provider contract. 'bounded' opts this driver into
# kernel deadline enforcement (wired in stage 3). Attribution is NOT set here -
# the kernel stamps engine/providerName; a driver cannot forge provenance.
$script:ClaudeUnderstandingProvider = [pscustomobject]@{
    name        = $script:ClaudeUnderstandingId
    description = 'Organizes onboarding answers into the Understanding Model via Claude. Configured + consented only. Bounded; local floor on any failure.'
    isFloor     = $false
    priority    = 10                                   # preferred over the floor (1000) when available
    bounded     = $true                                # kernel enforces maxMs by abandonment (stage 3)
    supports    = { param($TaskId) return ($TaskId -eq 'understanding.extract') }   # ONE task, only
    isAvailable = { return (Test-ClaudeUnderstandingAvailable) }
    invoke      = {
        param($Request)
        # Filled in stage 2 (prompt + strict-JSON parse + map to model) and
        # stage 3 (bounded work + tighter grounding). Until then, honest.
        if (Get-Command New-ReasoningResult -ErrorAction SilentlyContinue) {
            return (New-ReasoningResult -TaskId $Request.taskId -Ok $false -Output $null -Confidence 0.0 `
                    -Engine 'claude-understanding' -ProviderName 'claude-understanding' -ReasonCode 'provider-error')
        }
        return $null
    }
}

# Register into the Epic 12 registry (only if the kernel is present).
if (Get-Command Register-ReasoningProvider -ErrorAction SilentlyContinue) {
    Register-ReasoningProvider -Provider $script:ClaudeUnderstandingProvider
}
