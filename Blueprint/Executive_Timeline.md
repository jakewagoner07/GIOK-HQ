# The Executive Timeline

## Tony understands time

*Project Diamond, Sprint D19. Tony learns to notice change over time - what is new, what is aging,
what is overdue, what has been ignored, and what deadline is approaching - without creating noise.*

Implementation: `tony-alpha/dashboard/core/executive-timeline.ps1` -> `Get-ExecutiveTimeline`, folded
into the Executive Briefing (`Get-BriefingTimeline`) as a short **"Over time"** section.

## What it notices

- **New** - items that landed on the list in the last day.
- **Aging** - open action items that have lingered a few days (3-13 days).
- **Overdue** - open action items two weeks or more old.
- **Ignored / waiting** - genuine unread mail (Primary category, from real people) that has been
  waiting more than two days.
- **Expiring** - a calendar invitation whose RSVP window is closing (today / tomorrow / in N days).
- **Stale routine** - how long since the last End-of-Day audit.

Each becomes a calm sentence, e.g. "Three emails have been waiting more than two days.", "A calendar
invitation expires tomorrow.", "It's been 4 days since your last End-of-Day audit."

## The timeline model (derive, never store)

`Get-ExecutiveTimeline -Context $exec -Now [-WaitingEmails]` is **pure and deterministic** and holds
**no state**. Every signal is computed from **existing timestamps** in the single Executive Context
and the sources it references:

| Signal | Derived from (existing timestamp) |
|---|---|
| new / aging / overdue | Action Items `created` (age in days) |
| invitation expiring | Calendar event `start` + `responseStatus = needsAction` (RSVP by start) |
| waiting (ignored) | aging **unread** Gmail (`Get-EmailWaiting`, read-only) - received date |
| stale routine | the last End-of-Day Audit's date |

It returns the buckets plus a **calm, capped** set of notes (at most four, most consequential first)
and a `hasAny` flag - when there is nothing worth noticing, it returns nothing (no noise).

## How "no duplicate storage" is guaranteed

The engine **creates no database and writes nothing**. It reads:
- `Get-ActionItemsData` (the existing `action_items.json` - the one owner of tasks),
- the Calendar signal already in the Executive Context,
- aging unread mail via a **read-only** Gmail query (`Get-EmailWaiting` - `is:unread in:inbox
  category:primary older_than:2d`), derived from Gmail's own timestamps, nothing stored,
- the End-of-Day Audit's stored date.

There is no timeline store, no snapshot table, no per-item history file. Two calls differ only
because the clock moved - exactly like the Executive Context it extends. Single Source of Truth is
preserved; the Decision Framework and Executive Context are untouched.

## Honesty: what it will NOT fabricate

Some notions in the brief require data GIOK does not store, and Tony does **not** invent them:

- **"Repeatedly postponed N times"** needs a per-item **postpone counter** - no such field exists, so
  it is reported under `unavailable`, never guessed. (A small future field on Action Items would
  unlock it honestly.)
- **"You haven't spoken with this client in N days"** needs **sent-mail history** (and a wider
  window than today's inbox); not derivable from what GIOK reads today, so it is also `unavailable`.

This is Project Diamond: honesty over a convincing-but-false number.

## Avoiding noise

A real inbox has a backlog. Rather than an alarming exact count of every old unread message, the
timeline uses the **Primary** category and excludes automated senders (no-reply / notifications), and
when the backlog is large it says so calmly ("More than a dozen emails have been unread for several
days - your inbox has a backlog worth a pass.") instead of a scary number. Notes are capped at four,
ordered by consequence (overdue > waiting > expiring > aging > stale routine > new), and the section
is omitted entirely when nothing is worth surfacing.

## Integration (natural, calm)

`Get-BriefingTimeline` fetches aging unread mail **only when Gmail is connected** (read-only) and asks
the engine for its notes; the Executive Briefing renders them as a quiet **"Over time"** section
between the observation and Today's Focus. It is a few lines in the letter - never a dashboard, never
a feed, no automatic actions.

## Constraints honored

Derives everything from the existing Executive Context and existing timestamps; no new database, no
duplicate storage, no snapshot history; Single Source of Truth, Executive Context, and Decision
Framework preserved; honest about what it cannot derive; calm, capped, and omitted when empty;
integrated naturally into the Executive Briefing.

## Related
- [Executive_Context_Engine.md](Executive_Context_Engine.md) - the single context the timeline reads.
- [Executive_Briefing.md](Executive_Briefing.md) - where the "Over time" notes appear.
- [Tony_Decision_Framework.md](Tony_Decision_Framework.md) - untouched; still the judgment authority.
- [Gmail_Provider.md](Gmail_Provider.md) - supplies aging unread mail read-only (Get-EmailWaiting).
