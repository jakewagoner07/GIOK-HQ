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

# The conversation: welcome + 7 essential questions. Short, calm, and enough for
# Tony to be useful immediately. Deeper discovery moves into future normal
# conversations - not the first run. Each question maps (below) into Identity.
function Get-ConversationSteps {
    return @(
        [pscustomobject]@{ id = 'welcome';       type = 'welcome';  tony = "Hi Jake, I'm Tony - your Chief of Staff. Before we build anything, I want to understand you. This isn't setup; it's a short conversation. One question at a time, no wrong answers. Take all the time you need." }
        [pscustomobject]@{ id = 'q_name';        type = 'question'; tony = "Let's start simply. What should I call you?" }
        [pscustomobject]@{ id = 'q_areas';       type = 'question'; tony = "What are the three most important areas of your life right now?" }
        [pscustomobject]@{ id = 'q_goal';        type = 'question'; tony = "What is your biggest goal for the next 6-12 months?" }
        [pscustomobject]@{ id = 'q_challenge';   type = 'question'; tony = "What is the biggest challenge currently getting in your way?" }
        [pscustomobject]@{ id = 'q_protect';     type = 'question'; tony = "What commitments or non-negotiables should I protect for you?" }
        [pscustomobject]@{ id = 'q_week';        type = 'question'; tony = "What does a successful week look like for you?" }
        [pscustomobject]@{ id = 'q_boundaries';  type = 'question'; tony = "Last one. What should I never assume or do without asking you first?" }
    )
}

# Number of actual questions (welcome is not counted) - drives "Question N of 7".
function Get-ConversationQuestionCount { return @(Get-ConversationSteps | Where-Object { $_.type -eq 'question' }).Count }

# ---- state (progress + working answers) ----
# Persistence is deliberately defensive: onboarding must NEVER crash on a
# contended file, and a transient read failure must NEVER look like a fresh
# start (which would silently restart the interview). Saves are atomic with a
# rolling .bak; loads retry and fall back to .bak; nothing here throws to the UI.
function Get-FirstConversationPath { return (Join-Path $PSScriptRoot '..\..\first_conversation.json') }

function New-BlankConversationState {
    return [pscustomobject]@{ meta = [pscustomobject]@{ version = '1.1.0' }; completed = $false; currentStep = 0; startedAt = $null; completedAt = $null; answers = [pscustomobject]@{} }
}

# Read + parse one path with a few retries (rides out a brief external lock).
function Read-ConversationFile {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return $null }
    for ($i = 0; $i -lt 3; $i++) {
        try { return (Get-Content -Path $Path -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json) }
        catch { Start-Sleep -Milliseconds 80 }
    }
    return $null
}

# Load state safely. Only returns a blank state when there is genuinely NO prior
# file - a transient read error falls back to the .bak, never a silent restart.
# currentStep is clamped to a valid range so a corrupt index can't wedge the view.
function Get-ConversationState {
    $p = Get-FirstConversationPath
    $s = Read-ConversationFile -Path $p
    if (-not $s) { $s = Read-ConversationFile -Path ($p + '.bak') }
    if (-not $s) {
        # No readable primary AND no backup. If a file physically exists we could
        # not parse, do NOT reset a real conversation to blank - surface a safe,
        # not-completed state pinned at step 0 without wiping anything on disk.
        if (Test-Path $p) { $b = New-BlankConversationState; $b | Add-Member -NotePropertyName loadError -NotePropertyValue $true -Force; return $b }
        return (New-BlankConversationState)
    }
    if (-not ($s.PSObject.Properties.Name -contains 'answers') -or -not $s.answers) { $s | Add-Member -NotePropertyName answers -NotePropertyValue ([pscustomobject]@{}) -Force }
    if (-not ($s.PSObject.Properties.Name -contains 'completed')) { $s | Add-Member -NotePropertyName completed -NotePropertyValue $false -Force }
    $maxStep = @(Get-ConversationSteps).Count
    $cur = 0; try { $cur = [int]$s.currentStep } catch { $cur = 0 }
    $s.currentStep = [math]::Min([math]::Max(0, $cur), $maxStep)
    return $s
}

# Atomic save with rolling .bak and retry. Returns $true on success, $false on
# failure - callers surface a calm message instead of letting an exception crash
# the interview. Never throws.
function Save-ConversationState {
    param([Parameter(Mandatory)] $State)
    $target = Get-FirstConversationPath
    $tmp = $target + '.tmp'
    $bak = $target + '.bak'
    $json = $State | ConvertTo-Json -Depth 8
    for ($i = 0; $i -lt 3; $i++) {
        try {
            Set-Content -Path $tmp -Value $json -Encoding UTF8 -ErrorAction Stop
            if (Test-Path $target) {
                # atomic replace, keeping the prior good file as backup
                [System.IO.File]::Replace($tmp, $target, $bak)
            } else {
                [System.IO.File]::Move($tmp, $target)
            }
            return $true
        }
        catch {
            Start-Sleep -Milliseconds 100
            if (Test-Path $tmp) { try { Remove-Item $tmp -Force -ErrorAction SilentlyContinue } catch { } }
        }
    }
    return $false
}

function Get-ConversationAnswer {
    param($State, [string]$Id)
    if ($State.answers -and ($State.answers.PSObject.Properties.Name -contains $Id)) { return [string]$State.answers.$Id }
    return ''
}

# Save one answer. Returns $true/$false so the UI can react to a failed save.
function Set-ConversationAnswer {
    param([string]$StepId, [string]$Text)
    $s = Get-ConversationState
    if (-not $s.startedAt) { $s.startedAt = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss') }
    if (-not $s.answers) { $s | Add-Member -NotePropertyName answers -NotePropertyValue ([pscustomobject]@{}) -Force }
    $s.answers | Add-Member -NotePropertyName $StepId -NotePropertyValue $Text -Force
    return (Save-ConversationState $s)
}

# Move to a step (clamped). Returns $true/$false.
function Set-ConversationStep {
    param([int]$Index)
    $s = Get-ConversationState
    $maxStep = @(Get-ConversationSteps).Count
    $s.currentStep = [math]::Min([math]::Max(0, $Index), $maxStep)
    return (Save-ConversationState $s)
}

function Reset-Conversation {
    return (Save-ConversationState (New-BlankConversationState))
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
# Carries the answers that don't map to a dedicated Identity field (name,
# challenge, protect, boundaries) so Tony has them immediately - without
# fabricating structured records.
function Get-ComposedReflection {
    param($State)
    $name = Get-ConversationAnswer $State 'q_name'
    $areas = Get-ConversationAnswer $State 'q_areas'
    $goal = Get-ConversationAnswer $State 'q_goal'
    $challenge = Get-ConversationAnswer $State 'q_challenge'
    $protect = Get-ConversationAnswer $State 'q_protect'
    $boundaries = Get-ConversationAnswer $State 'q_boundaries'
    $parts = @()
    if ($name) { $parts += ("You asked me to call you {0}" -f $name.TrimEnd('.')) + '.' }
    if ($areas) { $parts += ("What matters most to you right now: {0}" -f $areas.TrimEnd('.')) + '.' }
    if ($goal) { $parts += ("Your biggest goal for the next 6-12 months: {0}" -f $goal.TrimEnd('.')) + '.' }
    if ($challenge) { $parts += ("The main challenge in your way: {0}" -f $challenge.TrimEnd('.')) + '.' }
    if ($protect) { $parts += ("Commitments you want me to protect: {0}" -f $protect.TrimEnd('.')) + '.' }
    if ($boundaries) { $parts += ("You asked me never to assume or act on {0} without checking with you first" -f $boundaries.TrimEnd('.')) + '.' }
    $parts += "I'll keep these at the center of everything we build together."
    return ($parts -join ' ')
}

# ---- completion: distill answers INTO Identity, then mark complete ----
# Conservative distillation over the 7 essential answers, reusing ONLY existing
# Identity setters (never fabricating). Deeper fields (vision, legacy, annual
# theme) are left for future normal conversations. Each write is wrapped so a
# single contended file cannot crash completion; the raw answers always remain
# in the conversation state file regardless.
function Complete-Conversation {
    $s = Get-ConversationState

    $areas = Get-ConversationAnswer $s 'q_areas'
    if ($areas -and (Get-Command Set-IdentityValuesFromText -ErrorAction SilentlyContinue)) { try { Set-IdentityValuesFromText -Text $areas } catch { } }

    $goal = Get-ConversationAnswer $s 'q_goal'
    if ($goal -and (Get-Command Set-IdentityGoalsFromText -ErrorAction SilentlyContinue)) { try { Set-IdentityGoalsFromText -Text $goal } catch { } }

    $week = Get-ConversationAnswer $s 'q_week'
    if ($week -and (Get-Command Set-IdentityMission -ErrorAction SilentlyContinue)) { try { Set-IdentityMission -Statement $week } catch { } }

    if (Get-Command Set-IdentityOverviewReflection -ErrorAction SilentlyContinue) { try { Set-IdentityOverviewReflection -Text (Get-ComposedReflection -State $s) } catch { } }

    $s.completed = $true; $s.completedAt = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    return (Save-ConversationState $s)
}
