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
            'Lead with the human thing, then the essential thing.',
            'Recommend a clear next step, not a menu.',
            'Never robotic, never overwhelming, never fifty questions at once.',
            'Coach, never judge. People matter more than money.',
            'Be honest about what you do not know; never fabricate.'
        )
        # system-prompt-style summary a future provider would receive
        systemPrompt = "You are Tony, Jake's executive AI Chief of Staff. Be warm, professional, and concise. Coach, don't judge. Lead with what matters to people, recommend one clear next step, and never pretend to know something you don't. People matter more than money."
    }
}

# Light tone-shaping of a raw provider response (placeholder - keeps Tony's voice consistent).
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
$script:TonyActiveProvider = 'local-stub'

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
function Set-TonyActiveProvider { param([string]$Name) if ($script:TonyProviders.ContainsKey($Name)) { $script:TonyActiveProvider = $Name } }

# The brain calls THIS. It does not know or name any model - it only asks
# the active provider to respond to a request.
function Invoke-TonyProvider {
    param([Parameter(Mandatory)] $Request)
    $p = $script:TonyProviders[$script:TonyActiveProvider]
    if (-not $p) { return 'No AI provider is connected.' }
    return (& $p.invoke $Request)
}

# Default provider: a local stub. It implements the contract but uses no
# AI - it returns an honest, deterministic placeholder. Replacing this
# with a real provider is the ONLY change needed to give Tony a model.
Register-TonyProvider -Provider ([pscustomobject]@{
        name        = 'local-stub'
        description = 'Local placeholder. No AI. Returns a deterministic response so the brain is testable.'
        invoke      = {
            param($Request)
            $intent = if ($Request.intent) { $Request.intent.type } else { 'answer' }
            switch ($intent) {
                'recommend'     { 'Here is where I would recommend your best next step (an AI provider will generate this).' }
                'ask'           { "Tell me a little more and I'll help." }
                'create-action' { "I'll capture that as an action item for you." }
                'save-note'     { "Got it - I'll save that to your Inbox." }
                'navigate'      { "Opening that for you." }
                'none'          { "I'm here, Jake. What would you like to do?" }
                default         { 'I hear you. (An AI provider will generate Tony''s full reply here.)' }
            }
        }
    })

# ---------------------------------------------------------------------
# ORCHESTRATOR
#    Ties the engines together: remember -> reason -> (provider) respond
#    in Tony's voice -> describe any actions. This is the single entry
#    point a future UI/AI wires into.
# ---------------------------------------------------------------------
function Invoke-TonyBrain {
    param([string]$UserInput, [datetime]$Now = (Get-Date))
    $context = Get-TonyContext -Now $Now
    $decision = Get-TonyDecision -UserInput $UserInput -Context $context
    $request = [pscustomobject]@{ persona = (Get-TonyPersona); context = $context; input = $UserInput; intent = $decision }

    $raw = Invoke-TonyProvider -Request $request   # provider layer only - model is hidden from the brain
    $message = Format-TonyVoice -Text $raw

    $actions = @()
    switch ($decision.type) {
        'navigate'      { $actions += (Invoke-TonyNavigateTo -Target $decision.target) }
        'create-action' { $actions += (Invoke-TonyCreateTask -Title $decision.title) }
        'save-note'     { $actions += (Invoke-TonySaveNote -Text $decision.text) }
    }

    return [pscustomobject]@{
        input    = $UserInput
        decision = $decision
        message  = $message
        actions  = @($actions)
        provider = $script:TonyActiveProvider   # which provider answered (not which model)
    }
}
