# =====================================================================
# tony-conversation.ps1  —  Tony conversation history (local, persistent)
# ---------------------------------------------------------------------
# "Talk with Tony" is a real conversation, not a search box. This layer
# owns the conversation LOG: the running back-and-forth between Jake and
# Tony. It persists to conversation.json so closing the window never
# erases history - the conversation is always there when you come back.
#
# Local only. No cloud, no APIs. Pure data logic; the UI renders it and
# Tony Brain reads recent turns for context. Mutators return the item;
# the caller Saves (matches the Capture pattern).
# =====================================================================

$ErrorActionPreference = 'Stop'

# conversation.json is PRIVATE chat history - gitignored, created lazily.
function Get-ConversationPath { return (Join-Path $PSScriptRoot '..\..\conversation.json') }

function Get-ConversationLog {
    $p = Get-ConversationPath
    if (Test-Path $p) {
        try { return (Get-Content -Path $p -Raw -Encoding UTF8 | ConvertFrom-Json) } catch { }
    }
    return [pscustomobject]@{ meta = [pscustomobject]@{ version = '1.0.0'; updated = $null }; messages = @() }
}

function Save-ConversationLog {
    param([Parameter(Mandatory)] $Data)
    if (-not $Data.meta) { $Data | Add-Member -NotePropertyName meta -NotePropertyValue ([pscustomobject]@{ version = '1.0.0'; updated = $null }) -Force }
    $Data.meta.updated = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    ($Data | ConvertTo-Json -Depth 8) | Set-Content -Path (Get-ConversationPath) -Encoding UTF8
}

function Get-NextConversationId {
    param([Parameter(Mandatory)] $Data)
    $max = 0
    foreach ($m in @($Data.messages)) { if ($m.id -match '^M-(\d+)$') { $n = [int]$Matches[1]; if ($n -gt $max) { $max = $n } } }
    return ('M-{0:0000}' -f ($max + 1))
}

# Append one turn. Role is 'user' or 'tony'. Returns the new message.
function Add-ConversationMessage {
    param([Parameter(Mandatory)] $Data, [Parameter(Mandatory)][ValidateSet('user', 'tony')][string]$Role, [Parameter(Mandatory)][string]$Text, [string]$Provider = '')
    $item = [pscustomobject]@{
        id        = Get-NextConversationId -Data $Data
        role      = $Role
        text      = $Text.Trim()
        provider  = $Provider          # which provider answered (tony turns only); never a model name
        timestamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    }
    $Data.messages = @($Data.messages) + $item
    return $item
}

# The last N turns, oldest-first, as {role,text} - what Tony Brain needs
# to "know the recent conversation" without loading the whole history.
function Get-RecentConversation {
    param([int]$Count = 8)
    $data = Get-ConversationLog
    $msgs = @($data.messages)
    if ($msgs.Count -gt $Count) { $msgs = $msgs[($msgs.Count - $Count)..($msgs.Count - 1)] }
    return @($msgs | ForEach-Object { [pscustomobject]@{ role = $_.role; text = $_.text } })
}

function Clear-ConversationLog {
    $data = [pscustomobject]@{ meta = [pscustomobject]@{ version = '1.0.0'; updated = $null }; messages = @() }
    Save-ConversationLog -Data $data
    return $data
}

# Tony's opening line - a Chief-of-Staff greeting, not a prompt. Aware of
# the time of day, where Jake is (workspace/project), and his top
# priority right now. Deterministic; no AI. The UI shows this as chrome
# above the persisted history (it is not stored as a message).
function Get-TonyConversationGreeting {
    param([string]$Name = 'Jake', [string]$CurrentWorkspace = '', [string]$CurrentProject = '', [datetime]$Now = (Get-Date))
    $h = $Now.Hour
    $part = if ($h -lt 12) { 'morning' } elseif ($h -lt 17) { 'afternoon' } else { 'evening' }
    $firstName = (([string]$Name).Trim() -split '\s+')[0]
    if (-not $firstName) { $firstName = 'there' }

    $where = ''
    if ($CurrentProject) { $where = " You're working on $CurrentProject." }
    elseif ($CurrentWorkspace -and $CurrentWorkspace -notin @('Home', 'unknown', 'Morning Experience')) { $where = " You're in $CurrentWorkspace." }

    $priority = ''
    if (Get-Command Get-ActionItemsData -ErrorAction SilentlyContinue) {
        try {
            $open = @((Get-ActionItemsData).items | Where-Object { -not $_.done -and -not $_.archived })
            if ($open.Count -gt 0) { $priority = " Right now your top priority looks like ""$($open[0].title)"" ($($open.Count) open on your list)." }
        } catch { }
    }

    return "Good $part, $firstName. I'm Tony - your Chief of Staff.$where$priority What's on your mind?"
}
