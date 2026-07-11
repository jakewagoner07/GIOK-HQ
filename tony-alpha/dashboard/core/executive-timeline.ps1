# =====================================================================
# executive-timeline.ps1  —  Tony understands TIME
# ---------------------------------------------------------------------
# Teaches Tony to notice change over time without creating noise: what is
# new, what is aging, what is overdue, what has been ignored (waiting), and
# what deadline is approaching. It answers "how long has this been true?"
#
# It DERIVES everything from EXISTING timestamps in the single Executive
# Context and the existing sources it references - Action Items (`created`),
# Calendar (`start` + RSVP `responseStatus`), aging unread Gmail (received
# date), and the End-of-Day Audit (its date). It creates NO database, NO
# duplicate storage, and holds NO state - two calls differ only because time
# moved. Pure, deterministic, testable.
#
# Honesty (Project Diamond): some notions require data GIOK does not store
# and are NOT fabricated - "repeatedly postponed N times" needs a postpone
# counter (no such field), and "last spoke N days ago" needs sent-mail
# history. Those are reported as `unavailable`, never invented.
# =====================================================================

$ErrorActionPreference = 'Stop'

function Get-TimeAgeDays {
    param([datetime]$From, [datetime]$Now)
    return [int][math]::Floor(($Now - $From).TotalDays)
}
function Get-TimeAgoText {
    param([int]$Days)
    if ($Days -le 0) { return 'today' }
    if ($Days -eq 1) { return 'yesterday' }
    return ("{0} days ago" -f $Days)
}

# THE engine. Reads existing timestamps and returns a calm, capped set of
# time notes plus the underlying buckets. WaitingEmails is the read-only
# aging-unread result from the Gmail provider (Get-EmailWaiting); when absent,
# email-age notes are simply omitted (honest - not guessed).
function Get-ExecutiveTimeline {
    param($Context, [datetime]$Now = (Get-Date), $WaitingEmails = $null)

    # ---- Action Items: new / aging / overdue (from `created`) ----
    $new = @(); $aging = @(); $overdue = @()
    if (Get-Command Get-ActionItemsData -ErrorAction SilentlyContinue) {
        try {
            foreach ($ai in @((Get-ActionItemsData).items | Where-Object { -not $_.done -and -not $_.archived -and $_.created })) {
                $age = Get-TimeAgeDays -From ([datetime]$ai.created) -Now $Now
                $rec = [pscustomobject]@{ title = [string]$ai.title; ageDays = $age; source = 'action-items'; sourceId = [string]$ai.id }
                if ($age -le 1) { $new += $rec }
                elseif ($age -ge 14) { $overdue += $rec }
                elseif ($age -ge 3) { $aging += $rec }
            }
        } catch { }
    }
    $aging = @($aging | Sort-Object ageDays -Descending)
    $overdue = @($overdue | Sort-Object ageDays -Descending)

    # ---- Calendar: invitations whose RSVP window is closing ----
    $invitesExpiring = @()
    try {
        $cal = $Context.calendar
        if ($cal -and $cal.ok) {
            foreach ($ev in @($cal.events | Where-Object { $_.responseStatus -eq 'needsAction' -and -not $_.allDay -and $_.start -gt $Now })) {
                $daysUntil = Get-TimeAgeDays -From $Now -Now $ev.start
                if ($daysUntil -le 3) {
                    $when = if ($ev.start.Date -eq $Now.Date) { 'today' } elseif ($ev.start.Date -eq $Now.Date.AddDays(1)) { 'tomorrow' } else { ('in {0} days' -f $daysUntil) }
                    $invitesExpiring += [pscustomobject]@{ title = [string]$ev.title; when = $when; start = $ev.start; source = 'calendar'; sourceId = [string]$ev.id }
                }
            }
        }
    } catch { }
    $invitesExpiring = @($invitesExpiring | Sort-Object start)

    # ---- Gmail: mail that has been WAITING (aging, unread) ----
    $waiting = if ($WaitingEmails) { $WaitingEmails } else { [pscustomobject]@{ count = 0; items = @() } }
    $waitingOver2 = @($waiting.items | Where-Object { $_.ageDays -ge 2 })
    $waitingCount = if ($waiting.count -ge @($waiting.items).Count) { [int]$waiting.count } else { @($waiting.items).Count }

    # ---- Routine: how long since the last End-of-Day Audit (from its date) ----
    $staleRoutine = $null
    try {
        $auditDateStr = $null
        $la = $Context.latestAudit
        if ($la -and ($la.PSObject.Properties.Name -contains 'date') -and $la.date) { $auditDateStr = [string]$la.date }
        elseif (Get-Command Get-AuditData -ErrorAction SilentlyContinue) {
            $keys = @((Get-AuditData).audits.PSObject.Properties.Name)
            if ($keys.Count -gt 0) { $auditDateStr = @($keys | Sort-Object -Descending)[0] }
        }
        if ($auditDateStr) {
            $days = Get-TimeAgeDays -From ([datetime]$auditDateStr) -Now $Now
            if ($days -ge 3) { $staleRoutine = [pscustomobject]@{ days = $days; what = 'End-of-Day audit' } }
        }
    } catch { }

    # ---- compose the calm, capped notes (max 4; most consequential first) ----
    $notes = @()
    if ($overdue.Count -gt 0) {
        $s = if ($overdue.Count -eq 1) { 'item has' } else { 'items have' }
        $notes += [pscustomobject]@{ kind = 'overdue'; text = ('{0} action {1} been open two weeks or more.' -f $overdue.Count, $s) }
    }
    if ($waitingCount -gt 0) {
        if ($waitingCount -le 10) {
            $s = if ($waitingCount -eq 1) { 'email has' } else { 'emails have' }
            $notes += [pscustomobject]@{ kind = 'waiting'; text = ('{0} {1} been waiting more than two days.' -f $waitingCount, $s) }
        } else {
            $notes += [pscustomobject]@{ kind = 'waiting'; text = ('More than a dozen emails have been unread for several days - your inbox has a backlog worth a pass.') }
        }
    }
    foreach ($iv in @($invitesExpiring | Select-Object -First 1)) {
        $notes += [pscustomobject]@{ kind = 'invite-expiry'; text = ('A calendar invitation ("{0}") expires {1}.' -f $iv.title, $iv.when) }
    }
    if ($overdue.Count -eq 0 -and $aging.Count -gt 0) {
        $a = $aging[0]
        $notes += [pscustomobject]@{ kind = 'aging'; text = ('"{0}" has been on your list {1} days.' -f $a.title, $a.ageDays) }
    }
    if ($staleRoutine) {
        $notes += [pscustomobject]@{ kind = 'stale-routine'; text = ("It's been {0} days since your last {1}." -f $staleRoutine.days, $staleRoutine.what) }
    }
    if ($notes.Count -eq 0 -and $new.Count -gt 0) {
        $s = if ($new.Count -eq 1) { 'item' } else { 'items' }
        $notes += [pscustomobject]@{ kind = 'new'; text = ('{0} new {1} landed on your list in the last day.' -f $new.Count, $s) }
    }
    $notes = @($notes | Select-Object -First 4)

    return [pscustomobject]@{
        source          = 'executive-timeline'
        generatedAt     = $Now
        new             = @($new)
        aging           = @($aging)
        overdue         = @($overdue)
        waiting         = [pscustomobject]@{ count = $waitingCount; overTwoDays = $waitingOver2.Count; items = @($waiting.items) }
        invitesExpiring = @($invitesExpiring)
        staleRoutine    = $staleRoutine
        notes           = @($notes)
        hasAny          = (@($notes).Count -gt 0)
        counts          = [pscustomobject]@{ new = $new.Count; aging = $aging.Count; overdue = $overdue.Count; waiting = $waitingCount; invitesExpiring = $invitesExpiring.Count }
        # NOT fabricated - these need data GIOK does not store:
        unavailable     = @('repeatedly-postponed (needs a per-item postpone counter)', 'last-contact-days (needs sent-mail history)')
    }
}
