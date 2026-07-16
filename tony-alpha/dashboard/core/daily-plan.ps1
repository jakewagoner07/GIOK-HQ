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

    # clarifications the day genuinely raises (from the context assessment) - questions
    # Tony should ask, and real goal/boundary conflicts. Not fabricated.
    $clar = @()
    if ((& $prop $Context 'assessment')) {
        $as = $Context.assessment
        if ($as.PSObject.Properties.Name -contains 'shouldClarify' -and $as.shouldClarify -and ($as.shouldClarify.PSObject.Properties.Name -contains 'questions')) {
            foreach ($q in @($as.shouldClarify.questions)) { if ($q) { $clar += [string]$q } }
        }
        if ($as.PSObject.Properties.Name -contains 'conflict' -and $as.conflict -and ($as.conflict.PSObject.Properties.Name -contains 'items')) {
            foreach ($c in @($as.conflict.items)) { if ($c) { $clar += ("Conflict to resolve: " + [string]$c) } }
        }
    }

    return [pscustomobject]@{
        time           = $time
        sources        = @($sources)
        clarifications = @($clar)
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

# ---- overload detection (conservative, evidence-only) ------------------
# Levels from REAL evidence: calendar density, time-sensitive count, conflicts,
# do-today count, and available focus time. It counts what is there; it NEVER
# diagnoses stress, burnout, or any medical condition.
function Get-DailyPlanWorkload {
    param($Signals)
    $cal = [int]$Signals.calendarToday
    $ts = [int]$Signals.timeSensitiveCount
    $conf = [int]$Signals.conflicts
    $doToday = [int]$Signals.doTodayCount
    $free = [int]$Signals.longestFreeMinutes
    $heavy = [bool]$Signals.meetingHeavy

    $level = 'balanced'
    if (($cal -ge 6) -or ($ts -ge 4) -or ($doToday -ge 6) -or ($conf -ge 1 -and $cal -ge 4)) { $level = 'overloaded' }
    elseif (($cal -ge 4) -or ($ts -ge 2) -or ($doToday -ge 4) -or $heavy) { $level = 'heavy' }
    elseif (($cal -le 1) -and ($ts -eq 0) -and ($doToday -le 2)) { $level = 'light' }

    # state ONLY the evidence that is actually present
    $ev = @()
    if ($cal -gt 0) { $ev += ("{0} scheduled commitment{1}" -f $cal, $(if ($cal -eq 1) { '' } else { 's' })) }
    if ($ts -gt 0) { $ev += ("{0} time-sensitive follow-up{1}" -f $ts, $(if ($ts -eq 1) { '' } else { 's' })) }
    if ($conf -gt 0) { $ev += ("{0} calendar conflict{1}" -f $conf, $(if ($conf -eq 1) { '' } else { 's' })) }
    if ($doToday -gt 0 -and $level -in @('heavy', 'overloaded')) { $ev += ("{0} do-today priorit{1}" -f $doToday, $(if ($doToday -eq 1) { 'y' } else { 'ies' })) }
    $reason = if ($ev.Count -eq 0) { "A calm day - nothing time-sensitive on the calendar." }
    else { ("Today looks {0} based on {1}." -f $level, (Join-DailyPlanNatural $ev)) }
    if ($level -eq 'light' -and $ev.Count -gt 0) { $reason = ("A light day - just {0}." -f (Join-DailyPlanNatural $ev)) }
    return [pscustomobject]@{ level = $level; reason = $reason }
}

# Natural list: "A", "A and B", "A, B and C".
function Join-DailyPlanNatural {
    param($Items)
    $t = @(@($Items) | Where-Object { $_ })
    if ($t.Count -eq 0) { return '' }
    if ($t.Count -eq 1) { return $t[0] }
    if ($t.Count -eq 2) { return ('{0} and {1}' -f $t[0], $t[1]) }
    return ('{0} and {1}' -f (($t[0..($t.Count - 2)]) -join ', '), $t[-1])
}

# ---- the deterministic local composer (the permanent floor) ------------
# Turns planSources into a calm, grounded Daily Plan. Reuses the ranking already in
# planSources (priority entries carry Family +40 etc.), never fabricates a missing
# deadline or importance, and keeps it small. Every item grounds to a real source.
function New-DailyPlanLocal {
    param($PlanSources, [datetime]$Now = (Get-Date), [string]$RequestId = '')
    if (-not $PlanSources) { return $null }
    $plan = New-EmptyDailyPlan -Now $Now -Engine 'local' -RequestId $RequestId -ContextVersion ([string]$PlanSources.contextVersion)
    $srcs = @($PlanSources.sources)
    $used = @{}   # sourceId -> $true, so an item is not placed twice
    $take = { param($s, $p, $reason, [bool]$approve, $action)
        $used[[string]$s.sourceId] = $true
        return (New-DailyPlanItem -Text ([string]$s.text) -SourceType ([string]$s.sourceType) -SourceId ([string]$s.sourceId) `
                -Reason $reason -Priority $p -Confidence 0.85 -RequiresApproval $approve -ProposedAction $action)
    }

    # ---- PROTECT: non-negotiables + today's calendar + family today ----
    $protect = @()
    foreach ($s in @($srcs | Where-Object { $_.sourceType -eq 'nonNegotiable' })) { $protect += (& $take $s 1 'A non-negotiable you asked me to protect.' $false $null) }
    foreach ($s in @($srcs | Where-Object { $_.sourceType -eq 'life:family' -and ($_.PSObject.Properties.Name -contains 'daysAway') -and [int]$_.daysAway -le 0 })) { $protect += (& $take $s 1 'A family commitment today - this comes first.' $false $null) }
    foreach ($s in @($srcs | Where-Object { $_.sourceType -eq 'calendar' })) { $protect += (& $take $s 2 'On your calendar today.' $false $null) }
    $plan.protect = @($protect | Select-Object -First 6)

    # ---- TOP OUTCOMES: the top ranked priorities (or goals), grounded ----
    $ranked = @($srcs | Where-Object { $_.sourceType -eq 'priority' } | Sort-Object @{ Expression = { [int]$_.rank } }, @{ Expression = { [string]$_.text } })
    $top = @()
    foreach ($s in $ranked) {
        if ($top.Count -ge 3) { break }
        $why = if ($s.PSObject.Properties.Name -contains 'why' -and $s.why) { [string]$s.why } else { 'Ranked among today''s most important work.' }
        $top += (& $take $s 1 $why $false $null)
    }
    if ($top.Count -eq 0) {
        # no ranking available - fall back to active goals' next steps
        foreach ($s in @($srcs | Where-Object { $_.sourceType -eq 'goal' })) {
            if ($top.Count -ge 3) { break }
            $why = if ($s.PSObject.Properties.Name -contains 'nextStep' -and $s.nextStep) { ("Next step: " + [string]$s.nextStep) } else { 'An active goal worth moving today.' }
            $top += (& $take $s 2 $why $false $null)
        }
    }
    $plan.topOutcomes = @($top)

    # ---- FOLLOW-UPS: email attention + timeline overdue/aging ----
    $follow = @()
    foreach ($s in @($srcs | Where-Object { $_.sourceType -eq 'email' -and -not $used[[string]$_.sourceId] })) { $follow += (& $take $s 3 'A message that needs your attention.' $false $null) }
    foreach ($s in @($srcs | Where-Object { $_.sourceType -eq 'timeline' -and -not $used[[string]$_.sourceId] })) {
        $r = if ($s.PSObject.Properties.Name -contains 'bucket' -and $s.bucket -eq 'overdue') { 'Overdue - worth closing out.' } else { 'Aging - a nudge keeps it from slipping.' }
        $follow += (& $take $s 3 $r $false $null)
    }
    $plan.followUps = @($follow | Select-Object -First 6)

    # ---- CAN WAIT: everything grounded but not yet placed, stated plainly ----
    $wait = @()
    foreach ($s in @($srcs | Where-Object { -not $used[[string]$_.sourceId] -and $_.sourceType -ne 'priority' })) {
        $wait += (New-DailyPlanItem -Text ([string]$s.text) -SourceType ([string]$s.sourceType) -SourceId ([string]$s.sourceId) -Reason 'Important, but it does not have to be today.' -Priority 6 -Confidence 0.8)
    }
    $plan.canWait = @($wait | Select-Object -First 8)

    # ---- RECOMMENDATIONS: at most two, source-grounded, each requiresApproval ----
    $recs = @()
    $urgentMail = @($srcs | Where-Object { $_.sourceType -eq 'email' } | Select-Object -First 1)
    if ($urgentMail.Count -gt 0) {
        $s = $urgentMail[0]
        $recs += (New-DailyPlanItem -Text 'Prepare a reply to the message that needs attention' -SourceType ([string]$s.sourceType) -SourceId ([string]$s.sourceId) `
                -Reason 'A timely reply keeps the relationship moving; nothing is sent until you approve it.' -Priority 3 -Confidence 0.7 -RequiresApproval $true `
                -ProposedAction (New-DailyPlanAction -Type 'prepare-message' -Title 'Prepare a reply' -Detail 'Draft only - review before sending.'))
    }
    $goalStep = @($srcs | Where-Object { $_.sourceType -eq 'goal' -and ($_.PSObject.Properties.Name -contains 'nextStep') -and $_.nextStep } | Select-Object -First 1)
    if ($goalStep.Count -gt 0 -and $recs.Count -lt 2) {
        $s = $goalStep[0]
        $recs += (New-DailyPlanItem -Text ('Add an action item: ' + [string]$s.nextStep) -SourceType ([string]$s.sourceType) -SourceId ([string]$s.sourceId) `
                -Reason 'Turning the next step into a tracked action keeps the goal moving.' -Priority 4 -Confidence 0.7 -RequiresApproval $true `
                -ProposedAction (New-DailyPlanAction -Type 'create-action' -Title ([string]$s.nextStep) -Detail 'Proposed for your Executive Inbox.'))
    }
    $plan.recommendations = @($recs)

    # ---- CLARIFICATIONS + WORKLOAD ----
    $plan.clarifications = @(@($PlanSources.clarifications) | Where-Object { $_ } | Select-Object -First 4 | ForEach-Object { [string]$_ })
    $plan.workload = Get-DailyPlanWorkload -Signals $PlanSources.signals
    return $plan
}

# ---- the briefing.compose validator (facts by machine) -----------------
# Registered here (daily-plan loads after reasoning-layer). This REPLACES the
# fail-closed 'task not migrated' stub for briefing.compose. Epic 13A philosophy:
# the machine validates facts; the human validates meaning on the review screen.
if (Get-Command Register-ReasoningValidator -ErrorAction SilentlyContinue) {
    Register-ReasoningValidator -TaskId 'briefing.compose' -Validator {
        param($Output, $Request)
        if (-not $Output) { return [pscustomobject]@{ valid = $false; reason = 'no plan' } }
        $ps = $Request.input
        if (-not $ps -or -not ($ps.PSObject.Properties.Name -contains 'sources')) { return [pscustomobject]@{ valid = $false; reason = 'cannot verify grounding: no plan sources on the request' } }
        # shape: meta + the five list sections + clarifications + workload
        if ($Output.PSObject.Properties.Name -notcontains 'meta') { return [pscustomobject]@{ valid = $false; reason = 'missing meta' } }
        foreach ($sec in $script:DailyPlanSections) {
            if ($Output.PSObject.Properties.Name -notcontains $sec) { return [pscustomobject]@{ valid = $false; reason = ("missing section: {0}" -f $sec) } }
        }
        if ($Output.PSObject.Properties.Name -notcontains 'workload' -or -not $Output.workload) { return [pscustomobject]@{ valid = $false; reason = 'missing workload' } }
        if ($script:DailyPlanWorkloadLevels -notcontains [string]$Output.workload.level) { return [pscustomobject]@{ valid = $false; reason = ("invalid workload level: {0}" -f $Output.workload.level) } }
        # allowed sections only: no unexpected list-shaped top-level keys
        $allowed = @('meta', 'clarifications', 'workload') + $script:DailyPlanSections
        foreach ($pn in $Output.PSObject.Properties.Name) {
            if ($allowed -notcontains $pn) { return [pscustomobject]@{ valid = $false; reason = ("unexpected section: {0}" -f $pn) } }
        }
        # every item in every section grounds to a supplied source; caps; approval;
        # no fabricated action; no auto-action claim.
        $total = 0
        $claimRx = '(?i)\b(i (have |''ve )?(created|added|scheduled|sent|moved|updated|saved|booked|completed|done|deleted|removed)|done:|已完成)\b'
        foreach ($sec in $script:DailyPlanSections) {
            foreach ($it in @($Output.$sec)) {
                if (-not $it) { continue }
                $total++
                $text = [string]$it.text
                if ([string]::IsNullOrWhiteSpace($text)) { return [pscustomobject]@{ valid = $false; reason = ("item with no text in {0}" -f $sec) } }
                if ($text.Length -gt $script:DailyPlanMaxItemChars) { return [pscustomobject]@{ valid = $false; reason = ("item too long in {0}" -f $sec) } }
                $st = [string]$it.sourceType; $sid = [string]$it.sourceId
                if ($script:DailyPlanSourceTypes -notcontains $st) { return [pscustomobject]@{ valid = $false; reason = ("unsupported sourceType: {0}" -f $st) } }
                if (-not (Find-DailyPlanSource -PlanSources $ps -SourceType $st -SourceId $sid)) { return [pscustomobject]@{ valid = $false; reason = ("item cites a source not in the context: {0}:{1}" -f $st, $sid) } }
                # no provider may claim an action already happened
                if ($text -match $claimRx -or ([string]$it.reason) -match $claimRx) { return [pscustomobject]@{ valid = $false; reason = ("claims an action occurred: {0}" -f $text) } }
                # a proposed action is a WRITE - it must require approval and be an allowed type
                if ($it.PSObject.Properties.Name -contains 'proposedAction' -and $it.proposedAction) {
                    if (-not [bool]$it.requiresApproval) { return [pscustomobject]@{ valid = $false; reason = ("a proposedAction must set requiresApproval=true: {0}" -f $text) } }
                    if ($script:DailyPlanActionTypes -notcontains [string]$it.proposedAction.type) { return [pscustomobject]@{ valid = $false; reason = ("fabricated action type: {0}" -f $it.proposedAction.type) } }
                }
                # requiresApproval=true with NO proposedAction is a claim of a write with
                # nothing to propose - reject as malformed.
                if ([bool]$it.requiresApproval -and -not ($it.PSObject.Properties.Name -contains 'proposedAction' -and $it.proposedAction)) { return [pscustomobject]@{ valid = $false; reason = ("requiresApproval with no proposedAction: {0}" -f $text) } }
            }
        }
        if ($total -gt $script:DailyPlanMaxItems) { return [pscustomobject]@{ valid = $false; reason = ("plan too large: {0} items (cap {1})" -f $total, $script:DailyPlanMaxItems) } }
        return [pscustomobject]@{ valid = $true; reason = '' }
    }
}

# ---- the public entry: build sources + route through the kernel ---------
# The single call the UI/Home card uses. Projects the Executive Context once, routes
# briefing.compose through the Executive Reasoning Layer (Claude when configured +
# consented + available; the deterministic floor otherwise), and returns the Daily
# Plan model with truthful engine provenance. Never a dependency the UI can die on:
# if the layer is absent it composes locally.
function Get-DailyPlan {
    param($Context, [datetime]$Now = (Get-Date), [int]$MaxMs = 30000)
    $ps = Get-DailyPlanSources -Context $Context -Now $Now
    if (Get-Command Invoke-ReasoningTask -ErrorAction SilentlyContinue) {
        try {
            $r = Invoke-ReasoningTask -TaskId 'briefing.compose' -Payload $ps -MaxMs $MaxMs
            if ($r -and $r.ok -and $r.output) {
                if ($r.output.PSObject.Properties.Name -contains 'meta' -and $r.output.meta) { $r.output.meta.engine = [string]$r.engine }
                return $r.output
            }
        }
        catch { }
    }
    return (New-DailyPlanLocal -PlanSources $ps -Now $Now)
}

# ---- recommendation -> pending Inbox proposal (approval only) -----------
# Called by the UI when the user APPROVES a recommendation. Never writes domain
# data - it only creates a pending Executive Inbox proposal (dedup-checked), and
# the existing Approve-InboxItem -> owning module does the real write later.
function Submit-DailyPlanRecommendation {
    param($Recommendation)
    if (-not $Recommendation -or -not $Recommendation.proposedAction) { return [pscustomobject]@{ ok = $false; message = 'Not an actionable recommendation.' } }
    if (-not (Get-Command Add-InboxProposal -ErrorAction SilentlyContinue)) { return [pscustomobject]@{ ok = $false; message = 'Inbox not available.' } }
    $act = $Recommendation.proposedAction
    $type = [string]$act.inboxType; if (-not $type) { $type = 'task' }
    $title = [string]$act.title; if (-not $title) { $title = [string]$Recommendation.text }
    # dedup against pending proposals by the same key
    if (Get-Command Get-InboxProposalKeys -ErrorAction SilentlyContinue) {
        try {
            $keys = @(Get-InboxProposalKeys)
            $k = if (Get-Command Get-ProposalKey -ErrorAction SilentlyContinue) { Get-ProposalKey -Type $type -Title $title -SourceId ([string]$Recommendation.sourceId) } else { '' }
            if ($k -and $keys -contains $k) { return [pscustomobject]@{ ok = $true; message = 'Already in your Executive Inbox.'; deduped = $true } }
        }
        catch { }
    }
    $p = Add-InboxProposal -DiscoveredBy 'Tony' -Type $type -Title $title -Description ([string]$act.detail) `
        -Source 'daily-plan' -SourceId ([string]$Recommendation.sourceId) -Confidence ([double]$Recommendation.confidence)
    if ($p) { return [pscustomobject]@{ ok = $true; message = 'Added to your Executive Inbox for approval.'; id = $p.id } }
    return [pscustomobject]@{ ok = $false; message = 'Could not create the proposal.' }
}
