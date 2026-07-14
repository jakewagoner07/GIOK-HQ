# =====================================================================
# first-conversation.ps1  —  Tony's First Conversation (engine)
# ---------------------------------------------------------------------
# GIOK starts with a conversation, not configuration. Tony asks ONE
# question at a time, listens, responds naturally, and moves forward.
#
# The answers are NOT written into Identity here. They feed the Understanding
# Engine (core/understanding-engine.ps1), which organises them into a temporary,
# reviewable model. Jake reviews it ("Here's what I understood"), edits anything
# wrong, and only his approval commits it to Identity - atomically. See
# Blueprint/Tony_Understanding_Engine.md.
#
# This is a REUSABLE engine: the conversation steps, state, and the
# swappable RESPONSE GENERATOR (Get-TonyResponse) are all here. A future
# AI replaces ONLY Get-TonyResponse - nothing else changes. No hardcoded
# answers, no cloud, no APIs on this path.
#
# State (progress + working answers, plus the pending understanding):
#   first_conversation.json  - also keeps the ORIGINAL responses, always.
# Approved meaning: identity/*.json (owned by Identity).
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

# (Get-ComposedReflection was removed in Epic 10. It pasted each RAW answer into
# one prose reflection; the Understanding Engine now composes the executive summary
# from the structured, reviewed model instead - see New-UEExecutiveSummary.)

# ---- completion: a TWO-STEP, consent-gated flow (Epic 10) ----
# This USED to copy raw answers straight into Identity the moment the interview
# ended - no understanding, no review, and no atomicity (each write was try/caught
# separately, so a failure midway left Identity half-written). Now the interview
# only produces a temporary Understanding Model, which Jake reviews and approves.
# Nothing reaches Identity until Approve-ConversationUnderstanding.
# See Blueprint/Tony_Understanding_Engine.md.

# Step 1 - end of the interview. Builds/refreshes the Understanding Model and
# writes NOTHING to Identity. The raw answers stay in the conversation state.
function Complete-Conversation {
    if (-not (Get-Command Initialize-UnderstandingModel -ErrorAction SilentlyContinue)) { return $false }
    try { $m = Initialize-UnderstandingModel; return ($null -ne $m) } catch { return $false }
}

# Step 2 - ONLY after Jake approves the review. Writes Identity atomically (all or
# nothing) and marks the conversation complete only if that write fully succeeded.
# If it fails, Identity is untouched and the conversation stays open to retry.
function Approve-ConversationUnderstanding {
    if (-not (Get-Command Approve-UnderstandingModel -ErrorAction SilentlyContinue)) { return $false }
    $ok = $false
    try { $ok = Approve-UnderstandingModel } catch { $ok = $false }
    if (-not $ok) { return $false }
    $s = Get-ConversationState
    $s.completed = $true; $s.completedAt = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    if ($s.PSObject.Properties.Name -contains 'understanding' -and $s.understanding) {
        $s.understanding.meta.approvedAt = $s.completedAt
    }
    return (Save-ConversationState $s)
}
