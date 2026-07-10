# =====================================================================
# tony-brain.ps1  —  Tony's internal brain (ARCHITECTURE ONLY)
# ---------------------------------------------------------------------
# This is the reasoning core that a future AI plugs into. It contains
# five engines:
#
#   1. Memory Engine       - gathers one unified context from GIOK's data
#   2. Conversation Engine - Tony's persona / tone
#   3. Reasoning Engine    - decides what Tony should do
#   4. Action Engine       - placeholder actions Tony can take
#   5. AI Provider Interface - the ONLY layer that knows which model runs
#
# HARD RULE: Tony never knows which AI model is being used. The brain
# speaks only to the provider abstraction; the provider layer alone
# knows the model. Today no providers are implemented - a local stub
# stands in. No cloud, no APIs, no external AI. Architecture only.
# =====================================================================

$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------
# 1. MEMORY ENGINE
#    Reads every relevant GIOK source and returns ONE unified context
#    object. It references data via each module's accessors (single
#    source of truth) - it never duplicates or caches a second copy.
# ---------------------------------------------------------------------
function Get-TonyContext {
    param([datetime]$Now = (Get-Date))

    $has = { param($n) [bool](Get-Command $n -ErrorAction SilentlyContinue) }

    # Identity (vision, goals, mission, values, overview)
    $identity = if (& $has 'Get-IdentityOverview') {
        [pscustomobject]@{
            overview = (Get-IdentityOverview)
            vision   = if (& $has 'Get-IdentityVision')  { Get-IdentityVision }  else { $null }
            goals    = if (& $has 'Get-IdentityGoals')   { Get-IdentityGoals }   else { $null }
            mission  = if (& $has 'Get-IdentityMission') { Get-IdentityMission } else { $null }
            values   = if (& $has 'Get-IdentityValues')  { Get-IdentityValues }  else { $null }
        }
    } else { $null }

    # Action items
    $actions = if (& $has 'Get-ActionItemsData') {
        $items = @((Get-ActionItemsData).items)
        [pscustomobject]@{ open = @($items | Where-Object { -not $_.archived -and -not $_.done }); total = $items.Count }
    } else { $null }

    # End of Day Audits (recent)
    $audits = if (& $has 'Get-AuditHistory') { @(Get-AuditHistory | Select-Object -First 5) } else { @() }

    # Morning Briefing model
    $briefing = if (& $has 'Get-MorningBrief') { Get-MorningBrief -Now $Now } else { $null }

    # Registry / AI Workforce
    $registry = if (& $has 'Get-Registry') { $r = Get-Registry; [pscustomobject]@{ version = $r.meta.version; agentCount = @($r.agents).Count; verified = [bool]$r.meta.verified_against_scheduler } } else { $null }

    # Capture
    $capture = if (& $has 'Get-CaptureStats') { Get-CaptureStats } else { $null }

    return [pscustomobject]@{
        generatedAt = $Now
        identity    = $identity
        actions     = $actions
        audits      = $audits
        briefing    = $briefing
        registry    = $registry
        capture     = $capture
        # note: this is a READ-ONLY view assembled from the sources; not a second copy of the data
        source      = 'unified-context'
    }
}

# ---------------------------------------------------------------------
# 2. CONVERSATION ENGINE
#    Tony's persona and tone. This is what the provider is told to sound
#    like. Friendly, professional, an executive Chief of Staff. Never
#    robotic.
# ---------------------------------------------------------------------
function Get-TonyPersona {
    return [pscustomobject]@{
        name = 'Tony'
        role = "Jake's AI Chief of Staff"
        tone = @('Friendly', 'Professional', 'Warm', 'Executive', 'Concise', 'Encouraging')
        rules = @(
            'Broadly capable, but purposefully grounded: as capable as any top-tier general assistant on any topic, yet always anchored to helping Jake build his life and business. Not a narrow productivity bot.',
            'Answer first. Ground second: answer the question Jake actually asked - fully - then reconnect to his goals, mission, plans, or next action only when it is natural. Do not over-redirect. Do not lecture.',
            'Helpful first: always answer the question Jake actually asked. Never make him feel he asked the wrong one.',
            "Serve Jake's whole life - business, family, health, learning, relationships, growth - not just GIOK.",
            'Answer normal questions (weather, sports, news, history, travel, math, general knowledge) naturally and fully; use connected providers when available.',
            'Recommend a clear next step, not a menu. One warm follow-up when useful - never an interrogation.',
            'Weigh Family before Financial; if a recommendation conflicts, explain why. People matter more than money.',
            'Coach, never judge. Be honest about what you do not know; never fabricate.'
        )
        # system-prompt-style summary a future provider would receive
        systemPrompt = "You are Tony, Jake's executive AI Chief of Staff, here for his whole life - business, family, health, learning, relationships, and growth. You are broadly capable, but purposefully grounded: as capable as any top-tier general assistant on any topic, yet always anchored to helping Jake build his life and business. Answer first, ground second: answer the question he actually asked - fully - then reconnect to his goals, mission, plans, or next action only when natural; do not over-redirect or lecture, and never make him feel he asked the wrong one. Answer normal questions naturally and use connected providers when available. Weigh Family before Financial and explain any conflict. Warm, concise, executive. Coach, don't judge. People matter more than money."
    }
}

# Light tone-shaping of a raw provider response - keeps Tony's voice consistent.
# Text flows through as native UTF-8: the provider decodes Claude's response as
# UTF-8 (Invoke-ClaudeApi) and JSON storage round-trips Unicode losslessly, so
# em dashes and smart quotes render natively in the Windows app. No ASCII
# rewriting - that was masking the old Latin-1 decode bug, which is now fixed at
# the source, so no cleanup pass is needed here.
function Format-TonyVoice {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return "I'm here, Jake. What would you like to do?" }
    return $Text.Trim()
}

# ---------------------------------------------------------------------
# 3. REASONING ENGINE
#    Decides what Tony SHOULD do. Local heuristics only (no AI). Returns
#    a decision object; the orchestrator acts on it.
#    Decision types: answer | ask | recommend | create-action | navigate | none
# ---------------------------------------------------------------------
function Get-TonyDecision {
    param([string]$UserInput, $Context)
    $t = if ($null -eq $UserInput) { '' } else { $UserInput.Trim() }
    if ($t -eq '') { return [pscustomobject]@{ type = 'none'; rationale = 'No input.' } }
    $lower = $t.ToLower()

    # create an action item
    if ($lower -match '^(add task|new task|create task|add)\s*:\s*(.+)$') {
        return [pscustomobject]@{ type = 'create-action'; title = ($t.Substring($t.IndexOf(':') + 1).Trim()); rationale = 'Explicit task request.' }
    }
    # capture a note
    if ($lower -match '^(capture|note)\s*:\s*(.+)$') {
        return [pscustomobject]@{ type = 'save-note'; text = ($t.Substring($t.IndexOf(':') + 1).Trim()); rationale = 'Explicit capture request.' }
    }
    # navigate
    if ($lower -match '^(open|go to|goto|show|view)\s+(.+)$') {
        $name = $Matches[2].Trim()
        $target = $name
        if (Get-Command Get-TonyCommandTargets -ErrorAction SilentlyContinue) {
            $map = Get-TonyCommandTargets
            if ($map.Contains($name)) { $target = $map[$name] }
        }
        return [pscustomobject]@{ type = 'navigate'; target = $target; rationale = 'Explicit navigation request.' }
    }
    # recommend
    if ($lower -match 'recommend|what should i|help me|advice|priorit') {
        return [pscustomobject]@{ type = 'recommend'; rationale = 'User is asking for guidance.' }
    }
    # a question -> answer
    if ($t.EndsWith('?')) { return [pscustomobject]@{ type = 'answer'; rationale = 'Direct question.' } }
    # ambiguous, short -> ask a clarifying question
    if (($t -split '\s+').Count -le 2) { return [pscustomobject]@{ type = 'ask'; rationale = 'Too little to act on; clarify.' } }
    # default -> answer
    return [pscustomobject]@{ type = 'answer'; rationale = 'General statement.' }
}

# ---------------------------------------------------------------------
# 4. ACTION ENGINE
#    Placeholder actions. The brain DESCRIBES the action; it does not
#    perform side effects here (the UI/caller executes them later).
# ---------------------------------------------------------------------
function New-TonyAction { param([string]$Type, $Params, [string]$Status = 'placeholder') return [pscustomobject]@{ action = $Type; params = $Params; status = $Status } }

function Invoke-TonyOpenWorkspace { param([string]$Name)   return (New-TonyAction -Type 'open-workspace' -Params ([pscustomobject]@{ name = $Name })) }
function Invoke-TonyCreateTask    { param([string]$Title)  return (New-TonyAction -Type 'create-task'    -Params ([pscustomobject]@{ title = $Title })) }
function Invoke-TonySaveNote      { param([string]$Text)   return (New-TonyAction -Type 'save-note'      -Params ([pscustomobject]@{ text = $Text })) }
function Invoke-TonyNavigateTo    { param([string]$Target) return (New-TonyAction -Type 'navigate'       -Params ([pscustomobject]@{ target = $Target })) }
function Invoke-TonyFutureIntegration { param([string]$Name) return (New-TonyAction -Type 'future-integration' -Params ([pscustomobject]@{ name = $Name }) -Status 'not-implemented') }

# ---------------------------------------------------------------------
# 5. AI PROVIDER INTERFACE
#    The ONLY layer that knows which model runs. A provider is an object
#    with: name, description, and an .invoke scriptblock taking a request
#    and returning text. Future providers (Claude, OpenAI, Gemini, Local
#    LLM) register here. None are implemented today - a local stub stands
#    in so the brain works without any AI.
# ---------------------------------------------------------------------
$script:TonyProviders = @{}
$script:TonyActiveProvider = 'auto'   # 'auto' picks a configured real provider, else the local stub

# ---- diagnostics ----------------------------------------------------
# A local, append-only log of Tony's reasoning/provider activity so we can
# see what happened (which provider answered, how long it took, why a call
# failed). NEVER logs the API key or the user's message text - only provider
# name, outcome, timing, and error class. Local file; gitignored.
function Get-TonyDiagPath { return (Join-Path $PSScriptRoot '..\..\logs\tony-diagnostics.log') }
function Write-TonyDiag {
    param([string]$Level = 'info', [string]$Source = 'tony', [string]$Message = '')
    try {
        $dir = Split-Path (Get-TonyDiagPath) -Parent
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        $line = '{0}  [{1}]  {2}: {3}' -f (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'), $Level.ToUpper(), $Source, $Message
        Add-Content -Path (Get-TonyDiagPath) -Value $line -Encoding UTF8
    } catch { }
}
function Get-TonyDiagTail {
    param([int]$Count = 20)
    $p = Get-TonyDiagPath
    if (-not (Test-Path $p)) { return @() }
    try { return @(Get-Content -Path $p -Tail $Count -Encoding UTF8) } catch { return @() }
}

function Get-TonyProviderContract {
    # The shape every provider must implement.
    return [pscustomobject]@{
        name        = '<string> unique id, e.g. "claude", "openai", "gemini", "local-llm"'
        description = '<string> human-readable'
        invoke      = '<scriptblock> param($Request) -> returns [string] response text'
        note        = 'The provider alone knows the model/keys/endpoint. The brain never sees them.'
    }
}

function Register-TonyProvider {
    param([Parameter(Mandatory)] $Provider)
    if (-not $Provider.name -or -not $Provider.invoke) { throw 'Provider must have a name and an invoke scriptblock.' }
    $script:TonyProviders[$Provider.name] = $Provider
}

function Get-TonyProviders { return @($script:TonyProviders.Values) }
function Set-TonyActiveProvider { param([string]$Name) if ($Name -eq 'auto' -or $script:TonyProviders.ContainsKey($Name)) { $script:TonyActiveProvider = $Name } }

# Resolve which provider actually answers. 'auto' prefers the first
# registered real (non-stub) provider that reports it is configured. If no
# real provider is configured, it STILL routes to the first real provider so
# that provider can answer HONESTLY about not being connected - Tony never
# shows a fake placeholder answer. The local stub is used only when no real
# provider is registered at all (e.g. brain-only unit tests). The brain
# never names a model.
function Resolve-TonyProvider {
    if ($script:TonyActiveProvider -ne 'auto') { return $script:TonyActiveProvider }
    $reals = @($script:TonyProviders.Values | Where-Object { $_.name -ne 'local-stub' })
    foreach ($p in $reals) {
        $ok = $true
        if (($p.PSObject.Properties.Name -contains 'isConfigured') -and $p.isConfigured) { try { $ok = [bool](& $p.isConfigured) } catch { $ok = $false } }
        if ($ok) { return $p.name }
    }
    if ($reals.Count -gt 0) { return $reals[0].name }   # honest "not connected" beats a placeholder
    return 'local-stub'
}

# The brain calls THIS. It does not know or name any model - it only asks
# the resolved provider to respond to a request.
function Invoke-TonyProvider {
    param([Parameter(Mandatory)] $Request)
    $name = Resolve-TonyProvider
    $p = $script:TonyProviders[$name]
    if (-not $p) { Write-TonyDiag -Level 'error' -Source 'provider' -Message 'No provider resolved.'; return (New-TonyResponse -Answer 'No AI provider is connected.' -ProviderName 'none' -Confidence 0.0) }
    Write-TonyDiag -Source 'provider' -Message ("Resolved provider '{0}' (active='{1}')." -f $name, $script:TonyActiveProvider)
    return (& $p.invoke $Request)
}

# Default provider: a local stub. It implements the contract but uses no
# AI - it returns an honest, deterministic placeholder. Replacing this
# with a real provider is the ONLY change needed to give Tony a model.
Register-TonyProvider -Provider ([pscustomobject]@{
        name        = 'local-stub'
        description = 'Local placeholder. No AI. Consumes a contract Request and returns a contract Response so the brain is testable.'
        invoke      = {
            param($Request)
            # consumes the AI Provider Contract request
            $intent = $Request.reasoningHint
            $req = $Request.requestedAction
            $answer = switch ($intent) {
                'recommend'     { 'Here is where I would recommend your best next step (an AI provider will generate this).' }
                'ask'           { "Tell me a little more and I'll help." }
                'create-action' { "I'll capture that as an action item for you." }
                'save-note'     { "Got it - I'll save that to your Inbox." }
                'navigate'      { "Opening that for you." }
                'none'          { "I'm here, Jake. What would you like to do?" }
                default         { 'I hear you. (An AI provider will generate Tony''s full reply here.)' }
            }
            $nav = if ($intent -eq 'navigate' -and $req) { $req.target } else { $null }
            $tasks = if ($intent -eq 'create-action' -and $req) { @($req.title) } else { @() }
            # returns a contract Response
            New-TonyResponse -Answer $answer -ProviderName 'local-stub' -Confidence 0.4 -NeedsClarification ($intent -eq 'ask') -ReasoningSummary ("Local stub handled intent '{0}' (no AI)." -f $intent) -SuggestedNavigation $nav -SuggestedTasks $tasks
        }
    })

# ---------------------------------------------------------------------
# ORCHESTRATOR
#    Ties the engines together: remember -> reason -> (provider) respond
#    in Tony's voice -> describe any actions. This is the single entry
#    point a future UI/AI wires into.
# ---------------------------------------------------------------------
function Invoke-TonyBrain {
    param([string]$UserInput, [string]$CurrentWorkspace = 'unknown', [datetime]$Now = (Get-Date), $History = @())

    # EXECUTIVE CONTEXT: Tony's single source of situational awareness, assembled
    # once (time, priorities, briefing, audit, goals, identity, observations, and
    # the Decision Framework judgment). Before every response Tony "gets it."
    $exec = if (Get-Command Get-TonyExecutiveContext -ErrorAction SilentlyContinue) {
        Get-TonyExecutiveContext -CurrentWorkspace $CurrentWorkspace -CurrentQuestion $UserInput -Now $Now -History $History
    } else { $null }

    # reuse the referenced base context for the reasoning engine (no re-assembly)
    $context = if ($exec -and $exec.base) { $exec.base } else { Get-TonyContext -Now $Now }
    $decision = Get-TonyDecision -UserInput $UserInput -Context $context

    if ($exec) {
        $identity = $exec.identity; $goals = @($exec.goals); $mission = $exec.mission
        $openTasks = @($exec.openTasks); $priorities = @($exec.priorities)
        $guidance = $exec.guidance                       # Decision Framework output (retains final authority below)
    } else {
        # fallback (brain-only, no executive engine): assemble the essentials directly
        $identity   = if ($context.identity) { $context.identity.overview } else { $null }
        $goals      = if ($context.identity -and $context.identity.goals)   { @($context.identity.goals.goals) } else { @() }
        $mission    = if ($context.identity -and $context.identity.mission) { $context.identity.mission.statement } else { '' }
        $openTasks  = if ($context.actions)  { @($context.actions.open | ForEach-Object { $_.title }) } else { @() }
        $priorities = if ($context.briefing) { @($context.briefing.topPriorities | ForEach-Object { $_.title }) } else { @() }
        $guidance   = $null
        if (Get-Command Evaluate-TonyDecision -ErrorAction SilentlyContinue) {
            $values = if ($context.identity -and $context.identity.values) { @($context.identity.values.values) } else { @() }
            $vision = if ($context.identity -and $context.identity.vision) { $context.identity.vision } else { $null }
            $annualTheme = if (Get-Command Get-IdentityAnnualTheme -ErrorAction SilentlyContinue) { Get-IdentityAnnualTheme } else { $null }
            $nonNeg = if (Get-Command Get-NonNegotiableDefs -ErrorAction SilentlyContinue) { Get-NonNegotiableDefs } else { @() }
            $guidance = Evaluate-TonyDecision -Identity $identity -Vision $vision -Goals $goals -Mission $mission -CoreValues $values `
                -AnnualTheme $annualTheme -NonNegotiables $nonNeg -Family $null -Health $null -Financial $null `
                -CurrentWorkspace $CurrentWorkspace -CurrentQuestion $UserInput -OpenTasks $openTasks -RecentAudits $context.audits
        }
    }

    # The provider receives a CONCISE executive summary instead of reconstructing
    # context from raw fields (Single Source of Truth: the summary is the context).
    $execSummary = if ($exec) { $exec.executiveSummary } else { '' }
    $ctxForProvider = [pscustomobject]@{
        source = 'executive-context'
        generatedAt = $Now
        executiveSummary = $execSummary
        partOfDay = if ($exec) { $exec.time.partOfDay } else { '' }
        workspace = $CurrentWorkspace
        openTaskCount = @($openTasks).Count
    }

    $request = New-TonyRequest -UserQuestion $UserInput -Context $ctxForProvider -Identity $identity -Goals $goals -Mission $mission `
        -CurrentWorkspace $CurrentWorkspace -OpenTasks $openTasks -TodaysPriorities $priorities -ConversationHistory @($History) `
        -TonyPersona (Get-TonyPersona) -ReasoningHint $decision.type -RequestedAction $decision -Guidance $guidance -Timestamp $Now

    $reqCheck = Test-TonyRequest -Request $request
    if (-not $reqCheck.valid) {
        return [pscustomobject]@{ input = $UserInput; decision = $decision; request = $request; message = "I couldn't process that."; actions = @(); provider = $null; error = ($reqCheck.errors -join ' ') }
    }

    # provider returns a CONTRACT RESPONSE; the brain never sees the model
    $response = Invoke-TonyProvider -Request $request
    $respCheck = Test-TonyResponse -Response $response

    $message = Format-TonyVoice -Text $response.answer
    $actions = @()
    if ($response.suggestedNavigation) { $actions += (Invoke-TonyNavigateTo -Target $response.suggestedNavigation) }
    foreach ($t in @($response.suggestedTasks)) { if ($t) { $actions += (Invoke-TonyCreateTask -Title $t) } }
    $actions += @($response.suggestedActions)

    return [pscustomobject]@{
        input            = $UserInput
        decision         = $decision
        executiveContext = $exec                 # Tony's situational awareness (single source; not stored)
        guidance         = $guidance             # Tony's judgment-layer evaluation (used before responding)
        request          = $request
        response         = $response
        responseValid    = $respCheck.valid
        message          = $message
        actions          = @($actions)
        provider         = $response.providerName # which provider answered (never which model)
    }
}
