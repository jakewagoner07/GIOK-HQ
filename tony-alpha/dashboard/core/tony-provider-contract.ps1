# =====================================================================
# tony-provider-contract.ps1  —  The AI Provider Contract (ARCHITECTURE)
# ---------------------------------------------------------------------
#   Tony -> Tony Brain -> AI Provider Contract -> Provider -> Model
#
# This file defines the PERMANENT language Tony uses to talk to ANY
# future AI provider. It is model-agnostic: the same request/response
# shape works for Claude, OpenAI, Gemini, a local LLM, or anything else.
#
# It contains ONLY: the request builder, the response builder, validators,
# and JSON serializers. No API calls, no network, no cloud, no AI.
#
# The request is a TRANSIENT message assembled from GIOK's single source
# of truth for one provider call - it is never a persistent second copy.
# =====================================================================

$ErrorActionPreference = 'Stop'

# Bump the minor for additive fields; bump the major only for breaking changes.
# 1.1 adds the optional 'guidance' field (Tony's judgment-layer evaluation).
$script:TonyContractVersion = '1.1'
function Get-TonyContractVersion { return $script:TonyContractVersion }
function Get-TonyContractMajor { param([string]$V = $script:TonyContractVersion) return ($V -split '\.')[0] }

# ---- REQUEST -------------------------------------------------------
# One request object. Fields mirror what any model needs to reason well.
function New-TonyRequest {
    param(
        [string]$UserQuestion,
        $Context,                 # unified context reference (from the Memory Engine)
        $Identity,
        $Goals,
        [string]$Mission,
        [string]$CurrentWorkspace,
        $OpenTasks,
        $TodaysPriorities,
        $ConversationHistory,
        $TonyPersona,
        [string]$ReasoningHint,
        $RequestedAction,
        $Guidance,                # v1.1: Tony's judgment-layer evaluation (guidance for the provider)
        [datetime]$Timestamp = (Get-Date)
    )
    return [pscustomobject]@{
        contractVersion     = $script:TonyContractVersion
        timestamp           = $Timestamp.ToString('yyyy-MM-dd HH:mm:ss')
        userQuestion        = $UserQuestion
        context             = $Context
        identity            = $Identity
        goals               = @($Goals)
        mission             = $Mission
        currentWorkspace    = $CurrentWorkspace
        openTasks           = @($OpenTasks)
        todaysPriorities    = @($TodaysPriorities)
        conversationHistory = @($ConversationHistory)
        tonyPersona         = $TonyPersona
        reasoningHint       = $ReasoningHint
        requestedAction     = $RequestedAction
        guidance            = $Guidance
    }
}

# ---- RESPONSE ------------------------------------------------------
# One response object. Every provider returns exactly this shape.
function New-TonyResponse {
    param(
        [string]$Answer,
        $SuggestedActions,
        $SuggestedTasks,
        [string]$SuggestedNavigation,
        [double]$Confidence = 0.5,
        [bool]$NeedsClarification = $false,
        [string]$ReasoningSummary,
        [string]$ProviderName
    )
    return [pscustomobject]@{
        contractVersion     = $script:TonyContractVersion
        answer              = $Answer
        suggestedActions    = @($SuggestedActions)
        suggestedTasks      = @($SuggestedTasks)
        suggestedNavigation = $SuggestedNavigation
        confidence          = [math]::Max(0.0, [math]::Min(1.0, $Confidence))
        needsClarification  = $NeedsClarification
        reasoningSummary    = $ReasoningSummary
        providerName        = $ProviderName
    }
}

# ---- VALIDATION ----------------------------------------------------
function Test-TonyRequest {
    param($Request)
    $errors = @(); $warnings = @()
    if ($null -eq $Request) { return [pscustomobject]@{ valid = $false; errors = @('Request is null.'); warnings = @() } }

    # version compatibility (same major)
    if (-not $Request.contractVersion) { $errors += 'Missing contractVersion.' }
    elseif ((Get-TonyContractMajor $Request.contractVersion) -ne (Get-TonyContractMajor)) {
        $errors += ("Incompatible contract version {0} (need major {1}.x)." -f $Request.contractVersion, (Get-TonyContractMajor))
    }

    # empty request: nothing to act on
    $hasQuestion = -not [string]::IsNullOrWhiteSpace($Request.userQuestion)
    $hasAction = ($null -ne $Request.requestedAction)
    if (-not $hasQuestion -and -not $hasAction) { $errors += 'Empty request: no userQuestion and no requestedAction.' }

    # missing context (allowed, but warn - a model reasons better with it)
    if ($null -eq $Request.context -and $null -eq $Request.identity) { $warnings += 'No context or identity supplied.' }
    if (-not $Request.tonyPersona) { $warnings += 'No Tony persona supplied.' }

    return [pscustomobject]@{ valid = ($errors.Count -eq 0); errors = $errors; warnings = $warnings }
}

function Test-TonyResponse {
    param($Response)
    $errors = @(); $warnings = @()
    if ($null -eq $Response) { return [pscustomobject]@{ valid = $false; errors = @('Response is null.'); warnings = @() } }

    if (-not $Response.contractVersion) { $errors += 'Missing contractVersion.' }
    elseif ((Get-TonyContractMajor $Response.contractVersion) -ne (Get-TonyContractMajor)) {
        $errors += ("Incompatible contract version {0}." -f $Response.contractVersion)
    }
    if (-not $Response.providerName) { $errors += 'Missing providerName.' }
    if ([string]::IsNullOrWhiteSpace($Response.answer) -and -not $Response.needsClarification) {
        $errors += 'Response has no answer and does not request clarification.'
    }
    return [pscustomobject]@{ valid = ($errors.Count -eq 0); errors = $errors; warnings = $warnings }
}

# ---- SERIALIZERS (JSON only - no network) --------------------------
function ConvertTo-TonyRequestJson  { param($Request)  return ($Request  | ConvertTo-Json -Depth 12) }
function ConvertFrom-TonyRequestJson  { param([string]$Json) return ($Json | ConvertFrom-Json) }
function ConvertTo-TonyResponseJson { param($Response) return ($Response | ConvertTo-Json -Depth 12) }
function ConvertFrom-TonyResponseJson { param([string]$Json) return ($Json | ConvertFrom-Json) }

# ---- PROVIDER CATALOG (architecture / future Settings; no UI change) --
# The provider *selection* Settings will eventually offer. Documented here
# so the contract knows the vocabulary; none are implemented.
function Get-TonyProviderCatalog {
    return @(
        [pscustomobject]@{ id = 'auto';    name = 'Auto';             status = 'default (picks best available)' }
        [pscustomobject]@{ id = 'claude';  name = 'Claude';           status = 'future' }
        [pscustomobject]@{ id = 'openai';  name = 'OpenAI';           status = 'future' }
        [pscustomobject]@{ id = 'gemini';  name = 'Gemini';           status = 'future' }
        [pscustomobject]@{ id = 'local';   name = 'Local AI';         status = 'future' }
        [pscustomobject]@{ id = 'custom';  name = 'Future Providers'; status = 'future (plug-in)' }
    )
}
