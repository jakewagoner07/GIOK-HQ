# =====================================================================
# first-conversation.ps1  —  Tony's First Conversation (engine)
# ---------------------------------------------------------------------
# GIOK starts with a conversation, not configuration. Tony asks ONE
# question at a time, listens, responds naturally, and moves forward.
# The answers are distilled INTO Identity (never duplicated) so the user
# feels understood before they ever see the dashboard.
#
# This is a REUSABLE engine: the conversation steps, state, and the
# swappable RESPONSE GENERATOR (Get-TonyResponse) are all here. A future
# AI replaces ONLY Get-TonyResponse - nothing else changes. No hardcoded
# answers, no AI, no cloud, no APIs.
#
# State (progress + working answers): first_conversation.json.
# Distilled meaning: identity/*.json (owned by Identity).
# =====================================================================

$ErrorActionPreference = 'Stop'

# The conversation: welcome + 17 questions. Each step maps (later) into Identity.
function Get-ConversationSteps {
    return @(
        [pscustomobject]@{ id = 'welcome';      type = 'welcome';  tony = "Hi Jake, I'm Tony - your Chief of Staff. Before we build anything, I want to understand you. This isn't setup; it's a conversation. One question at a time, no wrong answers. Take all the time you need." }
        [pscustomobject]@{ id = 'q_who';        type = 'question'; tony = "Let's start simply. Who are you?" }
        [pscustomobject]@{ id = 'q_become';     type = 'question'; tony = "What kind of person do you hope to become?" }
        [pscustomobject]@{ id = 'q_matters';    type = 'question'; tony = "What matters most in your life?" }
        [pscustomobject]@{ id = 'q_success';    type = 'question'; tony = "What does success look like to you?" }
        [pscustomobject]@{ id = 'q_goals';      type = 'question'; tony = "What are your biggest goals right now?" }
        [pscustomobject]@{ id = 'q_challenges'; type = 'question'; tony = "What challenges are you facing?" }
        [pscustomobject]@{ id = 'q_family';     type = 'question'; tony = "Tell me about your family." }
        [pscustomobject]@{ id = 'q_work';       type = 'question'; tony = "Tell me about your work." }
        [pscustomobject]@{ id = 'q_improve';    type = 'question'; tony = "What are you trying to improve?" }
        [pscustomobject]@{ id = 'q_financial';  type = 'question'; tony = "How do you define financial freedom?" }
        [pscustomobject]@{ id = 'q_health';     type = 'question'; tony = "What does good health mean to you?" }
        [pscustomobject]@{ id = 'q_perfect';    type = 'question'; tony = "If everything went perfectly this year, what would your life look like?" }
        [pscustomobject]@{ id = 'q_fiveyears';  type = 'question'; tony = "Where would you like to be in five years?" }
        [pscustomobject]@{ id = 'q_85';         type = 'question'; tony = "When you're 85 and looking back on your life... what will have mattered?" }
        [pscustomobject]@{ id = 'q_proud';      type = 'question'; tony = "What do you hope you'll be proud of?" }
        [pscustomobject]@{ id = 'q_promises';   type = 'question'; tony = "What promises do you want to keep to yourself?" }
        [pscustomobject]@{ id = 'q_anything';   type = 'question'; tony = "Last one. Anything else Tony should know?" }
    )
}

# ---- state (progress + working answers) ----
function Get-FirstConversationPath { return (Join-Path $PSScriptRoot '..\..\first_conversation.json') }

function Get-ConversationState {
    $p = Get-FirstConversationPath
    if (Test-Path $p) {
        try { return (Get-Content -Path $p -Raw -Encoding UTF8 | ConvertFrom-Json) } catch { }
    }
    return [pscustomobject]@{ meta = [pscustomobject]@{ version = '1.0.0' }; completed = $false; currentStep = 0; startedAt = $null; completedAt = $null; answers = [pscustomobject]@{} }
}

function Save-ConversationState { param([Parameter(Mandatory)] $State) ($State | ConvertTo-Json -Depth 8) | Set-Content -Path (Get-FirstConversationPath) -Encoding UTF8 }

function Get-ConversationAnswer {
    param($State, [string]$Id)
    if ($State.answers -and ($State.answers.PSObject.Properties.Name -contains $Id)) { return [string]$State.answers.$Id }
    return ''
}

function Set-ConversationAnswer {
    param([string]$StepId, [string]$Text)
    $s = Get-ConversationState
    if (-not $s.startedAt) { $s.startedAt = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss') }
    if (-not $s.answers) { $s | Add-Member -NotePropertyName answers -NotePropertyValue ([pscustomobject]@{}) -Force }
    $s.answers | Add-Member -NotePropertyName $StepId -NotePropertyValue $Text -Force
    Save-ConversationState $s
}

function Set-ConversationStep {
    param([int]$Index)
    $s = Get-ConversationState
    $s.currentStep = [math]::Max(0, $Index)
    Save-ConversationState $s
}

function Reset-Conversation {
    Save-ConversationState ([pscustomobject]@{ meta = [pscustomobject]@{ version = '1.0.0' }; completed = $false; currentStep = 0; startedAt = $null; completedAt = $null; answers = [pscustomobject]@{} })
}

# =====================  RESPONSE GENERATOR (swap this for AI later)  =====================
# Given the step index and the user's answer, return Tony's natural acknowledgment.
# It NEVER fabricates the user's answer - it responds to the fact that they answered.
function Get-TonyResponse {
    param([int]$Index, [string]$Answer)
    if ([string]::IsNullOrWhiteSpace($Answer)) { return '' }
    $acks = @(
        'Thank you for sharing that.',
        "That's clear - I've got it.",
        'I appreciate you being honest about that.',
        'Good. That helps me understand you.',
        'Noted - that matters.',
        "Thank you; that's important.",
        'I hear you.',
        "That's a strong answer.",
        'Understood. Thank you.'
    )
    return $acks[$Index % $acks.Count]
}

# Tony's closing message (also swappable later).
function Get-ConversationClosing {
    return "Thank you.`nI know enough to begin helping.`nLet's build your operating system."
}

# A reflection composed FROM the user's own answers (not hardcoded, not AI).
function Get-ComposedReflection {
    param($State)
    $who = Get-ConversationAnswer $State 'q_who'
    $become = Get-ConversationAnswer $State 'q_become'
    $matters = Get-ConversationAnswer $State 'q_matters'
    $parts = @()
    if ($who) { $parts += ("You told me: {0}" -f $who.TrimEnd('.')) + '.' }
    if ($become) { $parts += ("You're working to become {0}" -f $become.TrimEnd('.')) + '.' }
    if ($matters) { $parts += ("What matters most to you: {0}" -f $matters.TrimEnd('.')) + '.' }
    $parts += "I'll keep that at the center of everything we build together."
    return ($parts -join ' ')
}

# ---- completion: distill answers INTO Identity, then mark complete ----
function Complete-Conversation {
    $s = Get-ConversationState

    $vision = Get-ConversationAnswer $s 'q_become'
    if (-not $vision) { $vision = Get-ConversationAnswer $s 'q_perfect' }
    if (-not $vision) { $vision = Get-ConversationAnswer $s 'q_fiveyears' }
    if ($vision -and (Get-Command Set-IdentityVision -ErrorAction SilentlyContinue)) { Set-IdentityVision -Statement $vision }

    $mission = Get-ConversationAnswer $s 'q_success'
    if ($mission -and (Get-Command Set-IdentityMission -ErrorAction SilentlyContinue)) { Set-IdentityMission -Statement $mission }

    $values = Get-ConversationAnswer $s 'q_matters'
    if ($values -and (Get-Command Set-IdentityValuesFromText -ErrorAction SilentlyContinue)) { Set-IdentityValuesFromText -Text $values }

    $goals = Get-ConversationAnswer $s 'q_goals'
    if ($goals -and (Get-Command Set-IdentityGoalsFromText -ErrorAction SilentlyContinue)) { Set-IdentityGoalsFromText -Text $goals }

    $improve = Get-ConversationAnswer $s 'q_improve'
    if ($improve -and (Get-Command Set-IdentityAnnualThemeFromText -ErrorAction SilentlyContinue)) { Set-IdentityAnnualThemeFromText -Text $improve }

    $legacy = Get-ConversationAnswer $s 'q_85'
    if (-not $legacy) { $legacy = Get-ConversationAnswer $s 'q_proud' }
    if ($legacy -and (Get-Command Set-IdentityLegacy -ErrorAction SilentlyContinue)) { Set-IdentityLegacy -Statement $legacy }

    if (Get-Command Set-IdentityOverviewReflection -ErrorAction SilentlyContinue) { Set-IdentityOverviewReflection -Text (Get-ComposedReflection -State $s) }

    $s.completed = $true; $s.completedAt = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    Save-ConversationState $s
}
