# =====================================================================
# reasoning-consent.ps1  -  Consent for external reasoning (Epic 13)
# ---------------------------------------------------------------------
# Before any onboarding answer can leave the machine, the user must say yes.
# This module holds that decision. It is deliberately tiny and deliberately
# NOT persistent by default: consent is granted for ONE extraction attempt,
# then cleared. The Claude driver's isAvailable() reads Test-ExtractionConsent,
# so a declined (or unasked) attempt makes the driver an ineligible candidate -
# the kernel never invokes it, and the answers are never even handed to it.
#
# Persistence is opt-in and EXPLICIT ONLY. A user may ask to remember the
# choice; only then does a flag land in the existing gitignored Claude config.
# Nothing here is ever remembered silently - the default is ask-every-time.
#
# No secrets, no network, no onboarding content. This module logs nothing.
# =====================================================================

$ErrorActionPreference = 'Stop'

# The per-attempt decision. $null = not asked this attempt; a bool = the answer.
# Script-scoped: it lives on whatever runspace runs the extraction. The
# orchestration sets it right before Invoke-Reasoning and clears it right after,
# on the same runspace the driver's isAvailable() is probed on.
$script:ExtractionConsentGranted = $null

# Grant or deny consent for the CURRENT extraction attempt.
function Set-ExtractionConsent {
    param([Parameter(Mandatory)][bool]$Granted)
    $script:ExtractionConsentGranted = $Granted
}

# Clear the per-attempt decision. Call after every attempt so the next one must
# ask again (unless the user explicitly chose to remember - see below).
function Clear-ExtractionConsent {
    $script:ExtractionConsentGranted = $null
}

# Has the user consented for THIS attempt? Unasked ($null) counts as NO -
# the whole point is that silence never sends data.
function Test-ExtractionConsent {
    return ($script:ExtractionConsentGranted -eq $true)
}

# Was consent asked this attempt at all? (For honest UI/diagnostics only.)
function Test-ExtractionConsentAsked {
    return ($null -ne $script:ExtractionConsentGranted)
}

# ---- executive-reasoning consent (Epic 14: distinct from onboarding) ---
# Daily planning is NOT onboarding. Onboarding's extraction consent does NOT grant
# permission to send daily Executive Context data (goals, calendar info,
# communication metadata, Life OS priorities, action items) to Claude. This is its
# own per-attempt decision, with its own remember flag - so consent is task-scoped.
$script:ExecutiveReasoningConsentGranted = $null
function Set-ExecutiveReasoningConsent {
    param([Parameter(Mandatory)][bool]$Granted)
    $script:ExecutiveReasoningConsentGranted = $Granted
}
function Clear-ExecutiveReasoningConsent {
    $script:ExecutiveReasoningConsentGranted = $null
}
function Test-ExecutiveReasoningConsent {
    return ($script:ExecutiveReasoningConsentGranted -eq $true)
}
function Test-ExecutiveReasoningConsentAsked {
    return ($null -ne $script:ExecutiveReasoningConsentGranted)
}

# The task -> consent router. A reasoning task may only send data to a provider when
# the consent SCOPED TO THAT TASK is granted. Onboarding (understanding.extract) reads
# extraction consent; daily planning (briefing.compose) reads executive-reasoning
# consent. A task with no consent scope defined returns NO (silence never sends data).
function Test-TaskConsent {
    param([Parameter(Mandatory)][string]$TaskId)
    switch ($TaskId) {
        'understanding.extract' { return (Test-ExtractionConsent) }
        'briefing.compose' { return (Test-ExecutiveReasoningConsent) }
        default { return $false }
    }
}

# ---- explicit, opt-in persistence (never silent) ----------------------
# The remembered choice lives in the EXISTING gitignored Claude config, so we do
# not create a second store. It is written ONLY when the user explicitly asks to
# remember, and only if that config file already exists (env-var-only users stay
# ask-every-time, which is honest, not a bug). We preserve every existing key -
# the API key and model are never touched.
function Get-ClaudeConfigPath {
    # The provider's own resolution order (providers/ then dashboard-level).
    $candidates = @(
        (Join-Path $PSScriptRoot '..\providers\claude.config.json'),
        (Join-Path $PSScriptRoot '..\claude.config.json')
    )
    foreach ($c in $candidates) { if (Test-Path $c) { return (Resolve-Path $c).Path } }
    return $null
}

# Read the remembered choice, if any. Returns 'claude', 'local', or $null
# (not remembered). Never throws.
function Get-RememberedExtractionConsent {
    $p = Get-ClaudeConfigPath
    if (-not $p) { return $null }
    try {
        $cfg = Get-Content -Path $p -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($cfg.PSObject.Properties.Name -notcontains 'rememberExtractionConsent') { return $null }
        if (-not [bool]$cfg.rememberExtractionConsent) { return $null }
        $choice = [string]$cfg.extractionConsentChoice
        if ($choice -eq 'claude' -or $choice -eq 'local') { return $choice }
        return $null
    }
    catch { return $null }
}

# Persist (or clear) the remembered choice. EXPLICIT user action only - never
# call this from a default path. $Choice is 'claude' or 'local'; $Remember=$false
# forgets. Returns $true on a successful write, $false if there is no config file
# to write into (env-only) or the write failed. Preserves all other keys; logs
# nothing.
function Set-RememberedExtractionConsent {
    param(
        [Parameter(Mandatory)][bool]$Remember,
        [ValidateSet('claude', 'local')][string]$Choice = 'local'
    )
    $p = Get-ClaudeConfigPath
    if (-not $p) { return $false }
    try {
        $cfg = Get-Content -Path $p -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($Remember) {
            $cfg | Add-Member -NotePropertyName 'rememberExtractionConsent' -NotePropertyValue $true -Force
            $cfg | Add-Member -NotePropertyName 'extractionConsentChoice' -NotePropertyValue $Choice -Force
        }
        else {
            $cfg | Add-Member -NotePropertyName 'rememberExtractionConsent' -NotePropertyValue $false -Force
        }
        ($cfg | ConvertTo-Json -Depth 12) | Set-Content -Path $p -Encoding UTF8
        return $true
    }
    catch { return $false }
}

# Remembered EXECUTIVE-REASONING choice (Epic 14) - a SEPARATE remember flag from
# onboarding, in the same existing config (no second store). Explicit opt-in only.
function Get-RememberedExecutiveConsent {
    $p = Get-ClaudeConfigPath
    if (-not $p) { return $null }
    try {
        $cfg = Get-Content -Path $p -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($cfg.PSObject.Properties.Name -notcontains 'rememberExecutiveConsent') { return $null }
        if (-not [bool]$cfg.rememberExecutiveConsent) { return $null }
        $choice = [string]$cfg.executiveConsentChoice
        if ($choice -eq 'claude' -or $choice -eq 'local') { return $choice }
        return $null
    }
    catch { return $null }
}
function Set-RememberedExecutiveConsent {
    param(
        [Parameter(Mandatory)][bool]$Remember,
        [ValidateSet('claude', 'local')][string]$Choice = 'local'
    )
    $p = Get-ClaudeConfigPath
    if (-not $p) { return $false }
    try {
        $cfg = Get-Content -Path $p -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($Remember) {
            $cfg | Add-Member -NotePropertyName 'rememberExecutiveConsent' -NotePropertyValue $true -Force
            $cfg | Add-Member -NotePropertyName 'executiveConsentChoice' -NotePropertyValue $Choice -Force
        }
        else {
            $cfg | Add-Member -NotePropertyName 'rememberExecutiveConsent' -NotePropertyValue $false -Force
        }
        ($cfg | ConvertTo-Json -Depth 12) | Set-Content -Path $p -Encoding UTF8
        return $true
    }
    catch { return $false }
}
