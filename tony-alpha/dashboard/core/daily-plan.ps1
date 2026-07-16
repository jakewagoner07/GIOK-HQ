# =====================================================================
# daily-plan.ps1  -  Tony's Daily Executive Plan (Epic 14)
# ---------------------------------------------------------------------
# A READ-ONLY executive projection over the single Executive Context. It creates
# no second store and never acts: any write Tony recommends becomes a pending
# Executive Inbox proposal that only Jake's approval can commit.
#
# This file holds the provider-neutral Daily Plan MODEL, the compact groundable
# projection of the Executive Context (Get-DailyPlanSources), the deterministic
# local composer (New-DailyPlanLocal - the permanent floor), and the mapper that
# turns an approved write-recommendation into an Inbox proposal. It writes nothing.
#
# briefing.compose is the reasoning task; the Executive Reasoning Layer routes,
# validates, and attributes. See Blueprint/Daily_Executive_Plan.md.
# =====================================================================

$ErrorActionPreference = 'Stop'

$script:DailyPlanVersion = '1.0'
# The sourceType taxonomy every plan item must ground to.
$script:DailyPlanSourceTypes = @('goal', 'action', 'calendar', 'email', 'life:family', 'life:health',
    'life:financial', 'life:learning', 'nonNegotiable', 'priority', 'timeline', 'inbox')
# The list-shaped plan sections (clarifications + workload are handled separately).
$script:DailyPlanSections = @('topOutcomes', 'protect', 'followUps', 'canWait', 'recommendations')
# The only actions a recommendation may propose. Each is a PROPOSAL - never performed here.
$script:DailyPlanActionTypes = @('create-action', 'schedule-followup', 'prepare-message', 'move-to-inbox',
    'protect-calendar', 'defer-item')
# Which proposed actions map to which Executive Inbox proposal type.
$script:DailyPlanActionInboxType = @{
    'create-action'    = 'task'
    'schedule-followup' = 'task'
    'prepare-message'  = 'communication'
    'move-to-inbox'    = 'task'
    'protect-calendar' = 'calendar'
    'defer-item'       = 'task'
}
# Caps: a plan larger than this is malfunctioning (reject whole, never truncate).
$script:DailyPlanMaxItems = 40
$script:DailyPlanMaxItemChars = 300
$script:DailyPlanWorkloadLevels = @('light', 'balanced', 'heavy', 'overloaded')

# ---- model builders ---------------------------------------------------
function New-DailyPlanItem {
    param(
        [Parameter(Mandatory)][string]$Text,
        [Parameter(Mandatory)][string]$SourceType,
        [Parameter(Mandatory)][string]$SourceId,
        [string]$Reason = '',
        [int]$Priority = 5,
        [double]$Confidence = 0.8,
        [bool]$RequiresApproval = $false,
        $ProposedAction = $null
    )
    return [pscustomobject]@{
        text             = $Text
        sourceType       = $SourceType
        sourceId         = $SourceId
        reason           = $Reason
        priority         = $Priority
        confidence       = [math]::Round([math]::Max(0.0, [math]::Min(1.0, $Confidence)), 2)
        requiresApproval = $RequiresApproval
        proposedAction   = $ProposedAction
    }
}

function New-EmptyDailyPlan {
    param([datetime]$Now = (Get-Date), [string]$Engine = 'local', [string]$RequestId = '', [string]$ContextVersion = '')
    return [pscustomobject]@{
        meta            = [pscustomobject]@{
            generatedAt         = $Now.ToString('yyyy-MM-dd HH:mm:ss')
            engine              = $Engine
            sourceContextVersion = $ContextVersion
            requestId           = $RequestId
        }
        topOutcomes     = @()
        protect         = @()
        followUps       = @()
        canWait         = @()
        recommendations = @()
        clarifications  = @()
        workload        = [pscustomobject]@{ level = 'balanced'; reason = '' }
    }
}

# A proposed action: describes a write WITHOUT performing it. requiresApproval is
# always true on the owning item; the action becomes an Inbox proposal on approve.
function New-DailyPlanAction {
    param([Parameter(Mandatory)][string]$Type, [string]$Title = '', [string]$Detail = '', [string]$InboxType = '')
    if ($script:DailyPlanActionTypes -notcontains $Type) { return $null }
    if (-not $InboxType) { $InboxType = $script:DailyPlanActionInboxType[$Type] }
    return [pscustomobject]@{ type = $Type; title = $Title; detail = $Detail; inboxType = $InboxType }
}

# ---- source projection -------------------------------------------------
# A short deterministic id for a derived entry (a ranked priority) that has no
# natural id of its own. Deterministic (no randomness), so the same input yields
# the same id and grounding is stable.
function Get-DailyPlanStableId {
    param([string]$Prefix, [string]$Text)
    $md5 = [System.Security.Cryptography.MD5]::Create()
    $bytes = $md5.ComputeHash([System.Text.Encoding]::UTF8.GetBytes([string]$Text))
    $hex = ([System.BitConverter]::ToString($bytes) -replace '-', '').Substring(0, 8)
    return ("{0}-{1}" -f $Prefix, $hex)
}

function New-PlanSource {
    param([string]$SourceType, [string]$SourceId, [string]$Text, $Extra = $null)
    $o = [ordered]@{ sourceType = $SourceType; sourceId = $SourceId; text = [string]$Text }
    if ($Extra) { foreach ($k in $Extra.Keys) { $o[$k] = $Extra[$k] } }
    return [pscustomobject]$o
}

# Project the single Executive Context into a compact, self-contained, groundable
# list. This is the ONLY input the reasoning task carries - the raw context (with
# its deep back-references) is never serialized, and what could leave for Claude is
# a deliberate projection, not everything Tony knows. Reads by reference; writes
# nothing. Calendar/email are consumed as-is from the context (NEVER re-fetched).
function Get-DailyPlanSources {
    param($Context, [datetime]$Now = (Get-Date))
    $sources = @()
    $prop = { param($o, $n) return ($o -and ($o.PSObject.Properties.Name -contains $n) -and $null -ne $o.$n) }

    # time
    $t = if (& $prop $Context 'time') { $Context.time } else { $null }
    $time = [pscustomobject]@{
        date      = if ($t) { [string]$t.date } else { $Now.ToString('yyyy-MM-dd') }
        dayOfWeek = if ($t) { [string]$t.dayOfWeek } else { $Now.DayOfWeek.ToString() }
        hour      = if ($t) { [int]$t.hour } else { $Now.Hour }
        partOfDay = if ($t) { [string]$t.partOfDay } else { '' }
        isWeekend = if ($t) { [bool]$t.isWeekend } else { $false }
    }

    # goals (active) - grounded by goal id
    if (& $prop $Context 'activeGoals') {
        foreach ($g in @($Context.activeGoals)) {
            if (-not $g) { continue }
            $gid = [string]$g.id; if (-not $gid) { continue }
            $ns = if ($g.PSObject.Properties.Name -contains 'nextStep') { [string]$g.nextStep } else { '' }
            $sources += (New-PlanSource -SourceType 'goal' -SourceId $gid -Text ([string]$g.title) `
                    -Extra @{ nextStep = $ns; domain = [string]$g.domain; targetDate = [string]$g.targetDate })
        }
    }

    # action items - grounded by action id (local store, not a live provider)
    if (Get-Command Get-ActionItemsData -ErrorAction SilentlyContinue) {
        try {
            $ai = Get-ActionItemsData
            foreach ($a in @($ai.items)) {
                if (-not $a -or [bool]$a.done -or [bool]$a.archived) { continue }
                $aid = [string]$a.id; if (-not $aid) { continue }
                $sources += (New-PlanSource -SourceType 'action' -SourceId $aid -Text ([string]$a.title))
            }
        }
        catch { }
    }

    # calendar (pass-through from context; never fetched here)
    $cal = if (& $prop $Context 'calendar') { $Context.calendar } else { $null }
    if ($cal -and ($cal.PSObject.Properties.Name -contains 'events')) {
        foreach ($e in @($cal.events)) {
            if (-not $e) { continue }
            $eid = [string]$e.id; if (-not $eid) { $eid = Get-DailyPlanStableId -Prefix 'CAL' -Text ([string]$e.title + [string]$e.start) }
            $sources += (New-PlanSource -SourceType 'calendar' -SourceId $eid -Text ([string]$e.title) `
                    -Extra @{ when = [string]$e.start; responseStatus = [string]$e.responseStatus })
        }
    }

    # email attention items (pass-through; metadata only, disclosed under consent)
    $em = if (& $prop $Context 'email') { $Context.email } else { $null }
    if ($em -and ($em.PSObject.Properties.Name -contains 'summary') -and $em.summary -and ($em.summary.PSObject.Properties.Name -contains 'attentionItems')) {
        foreach ($m in @($em.summary.attentionItems)) {
            if (-not $m) { continue }
            $mid = [string]$m.messageId; if (-not $mid) { continue }
            $txt = [string]$m.why; if (-not $txt) { $txt = [string]$m.subject }
            $sources += (New-PlanSource -SourceType 'email' -SourceId $mid -Text $txt `
                    -Extra @{ category = [string]$m.category; from = [string]$m.from })
        }
    }

    # Life OS digest - family / health / financial / learning
    $ld = if (& $prop $Context 'lifeDigest') { $Context.lifeDigest } else { $null }
    if ($ld) {
        foreach ($f in @($ld.family.upcoming)) {
            if (-not $f) { continue }
            $sources += (New-PlanSource -SourceType 'life:family' -SourceId ([string]$f.id) -Text ([string]$f.title) `
                    -Extra @{ when = [string]$f.date; daysAway = [int]$f.daysAway })
        }
        foreach ($dom in @('health', 'financial', 'learning')) {
            $node = $ld.$dom
            if (-not $node) { continue }
            foreach ($it in (@($node.items) + @($node.goals))) {
                if (-not $it) { continue }
                $iid = [string]$it.id; if (-not $iid) { continue }
                $ex = @{}
                if ($it.PSObject.Properties.Name -contains 'amount') { $ex['amount'] = [string]$it.amount }
                if ($it.PSObject.Properties.Name -contains 'dueDate') { $ex['dueDate'] = [string]$it.dueDate }
                if ($it.PSObject.Properties.Name -contains 'daysAway') { $ex['daysAway'] = [int]$it.daysAway }
                if ($it.PSObject.Properties.Name -contains 'nextStep') { $ex['nextStep'] = [string]$it.nextStep }
                $sources += (New-PlanSource -SourceType ("life:$dom") -SourceId $iid -Text ([string]$it.title) -Extra $ex)
            }
        }
    }

    # non-negotiables (definitions to protect)
    if (& $prop $Context 'nonNegotiables') {
        foreach ($n in @($Context.nonNegotiables)) {
            if (-not $n) { continue }
            $nid = [string]$n.id; if (-not $nid) { continue }
            $sources += (New-PlanSource -SourceType 'nonNegotiable' -SourceId $nid -Text ([string]$n.title))
        }
    }

    # the priority ranking (derived from the above; every entry is real context data)
    $doTodayCount = 0
    if (Get-Command Get-ExecutivePriorities -ErrorAction SilentlyContinue) {
        try {
            $pri = Get-ExecutivePriorities -Context $Context -Now $Now
            $doTodayCount = @($pri.doToday).Count + @($pri.actNow).Count
            foreach ($tier in @(@{ n = 'actNow'; p = 1 }, @{ n = 'doToday'; p = 3 }, @{ n = 'keepVisible'; p = 6 })) {
                foreach ($p in @($pri.($tier.n))) {
                    if (-not $p -or -not $p.title) { continue }
                    $pid = Get-DailyPlanStableId -Prefix 'PRI' -Text ([string]$p.title)
                    $sources += (New-PlanSource -SourceType 'priority' -SourceId $pid -Text ([string]$p.title) `
                            -Extra @{ why = [string]$p.why; tier = [string]$p.tier; rank = $tier.p })
                }
            }
        }
        catch { }
    }

    # the timeline (follow-ups aging/overdue/waiting) - each carries its own sourceId
    $timeSensitive = 0
    if (Get-Command Get-ExecutiveTimeline -ErrorAction SilentlyContinue) {
        try {
            $tl = Get-ExecutiveTimeline -Context $Context -Now $Now
            $timeSensitive = @($tl.overdue).Count + @($tl.waiting.overTwoDays) + @($tl.invitesExpiring).Count
            foreach ($bucket in @('overdue', 'aging')) {
                foreach ($it in @($tl.$bucket)) {
                    if (-not $it -or -not $it.title) { continue }
                    $tid = [string]$it.sourceId; if (-not $tid) { $tid = Get-DailyPlanStableId -Prefix 'TL' -Text ([string]$it.title) }
                    $sources += (New-PlanSource -SourceType 'timeline' -SourceId $tid -Text ([string]$it.title) `
                            -Extra @{ bucket = $bucket; ageDays = [int]$it.ageDays })
                }
            }
        }
        catch { }
    }

    # signals for overload assessment (real evidence only)
    $calToday = 0
    if ($cal) {
        if ($cal.PSObject.Properties.Name -contains 'todayCount') { $calToday = [int]$cal.todayCount }
        elseif ($cal.PSObject.Properties.Name -contains 'events') { $calToday = @($cal.events).Count }
    }
    $conflicts = if ($cal -and ($cal.PSObject.Properties.Name -contains 'conflicts')) { @($cal.conflicts).Count } else { 0 }
    $meetingHeavy = $false
    if ($cal -and ($cal.PSObject.Properties.Name -contains 'insights') -and $cal.insights -and ($cal.insights.PSObject.Properties.Name -contains 'today')) {
        if ($cal.insights.today.PSObject.Properties.Name -contains 'meetingHeavy') { $meetingHeavy = [bool]$cal.insights.today.meetingHeavy }
    }
    $longestFree = 0
    if ($cal -and ($cal.PSObject.Properties.Name -contains 'insights') -and $cal.insights -and ($cal.insights.PSObject.Properties.Name -contains 'today') -and ($cal.insights.today.PSObject.Properties.Name -contains 'longestFreeBlock') -and $cal.insights.today.longestFreeBlock) {
        $longestFree = [int]$cal.insights.today.longestFreeBlock.minutes
    }
    $inboxPending = if ((& $prop $Context 'inbox') -and ($Context.inbox.PSObject.Properties.Name -contains 'pending')) { [int]$Context.inbox.pending } else { 0 }

    $cv = if (& $prop $Context 'generatedAt') { [string]$Context.generatedAt } else { $Now.ToString('yyyy-MM-dd HH:mm:ss') }

    return [pscustomobject]@{
        time           = $time
        sources        = @($sources)
        signals        = [pscustomobject]@{
            calendarToday      = $calToday
            timeSensitiveCount = $timeSensitive
            conflicts          = $conflicts
            meetingHeavy       = $meetingHeavy
            doTodayCount       = $doTodayCount
            longestFreeMinutes = $longestFree
            inboxPending       = $inboxPending
        }
        contextVersion = $cv
    }
}

# Membership lookup: is (SourceType, SourceId) a real supplied source? Used by the
# validator (grounding) and the composer. Returns the source entry or $null.
function Find-DailyPlanSource {
    param($PlanSources, [string]$SourceType, [string]$SourceId)
    if (-not $PlanSources -or -not $PlanSources.sources) { return $null }
    foreach ($s in @($PlanSources.sources)) {
        if ([string]$s.sourceType -eq $SourceType -and [string]$s.sourceId -eq $SourceId) { return $s }
    }
    return $null
}
