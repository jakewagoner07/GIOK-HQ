# =====================================================================
# command-bar.ps1  —  "Ask Tony" local command parsing (business logic)
# ---------------------------------------------------------------------
# NO UI, NO external AI. Parses a typed command into an intent the UI
# can act on. This is the local command foundation; a real assistant
# can plug in later behind the same Invoke-TonyCommand contract.
#
# Returns a [pscustomobject] with:
#   type = 'navigate' | 'addtask' | 'unknown' | 'none'
#   target  (for navigate)   e.g. 'Agents'
#   title   (for addtask)
#   message (for unknown)
# =====================================================================

$ErrorActionPreference = 'Stop'

function Get-TonyCommandTargets {
    # spoken name -> view name
    return [ordered]@{
        'agents'          = 'Agents'
        'issues'          = 'Issues'
        'action items'    = 'Action Items'
        'actions'         = 'Action Items'
        'tasks'           = 'Action Items'
        'weekly review'   = 'Weekly Review'
        'weekly'          = 'Weekly Review'
        'roadmap'         = 'Roadmap'
        'home'            = 'Home'
        'dashboard'       = 'Home'
        'agency'          = 'Agency'
        'appointments'    = 'Appointments'
        'calendar'        = 'Appointments'
        'recommendations' = 'Recommendations'
        'settings'        = 'Settings'
    }
}

function Invoke-TonyCommand {
    param([string]$Text)
    $t = if ($null -eq $Text) { '' } else { $Text.Trim() }
    if ($t -eq '') { return [pscustomobject]@{ type = 'none' } }
    $lower = $t.ToLower()
    $map = Get-TonyCommandTargets

    # add task: <text>   (also "new task:", "add:")
    if ($lower -match '^(add task|new task|add|create task)\s*:\s*(.+)$') {
        $title = $t.Substring($t.IndexOf(':') + 1).Trim()
        if ($title) { return [pscustomobject]@{ type = 'addtask'; title = $title } }
    }

    # open / go to / show <target>
    if ($lower -match '^(open|go to|goto|show|view)\s+(.+)$') {
        $name = $Matches[2].Trim()
        if ($map.Contains($name)) { return [pscustomobject]@{ type = 'navigate'; target = $map[$name] } }
        foreach ($k in $map.Keys) { if ($k -like "$name*" -or $name -like "$k*") { return [pscustomobject]@{ type = 'navigate'; target = $map[$k] } } }
        return [pscustomobject]@{ type = 'unknown'; message = ("Tony doesn't know how to open '{0}' yet." -f $name) }
    }

    # bare view name, e.g. "agents"
    if ($map.Contains($lower)) { return [pscustomobject]@{ type = 'navigate'; target = $map[$lower] } }

    return [pscustomobject]@{ type = 'unknown'; message = "Try 'open agents', 'open issues', or 'add task: <something>'." }
}
