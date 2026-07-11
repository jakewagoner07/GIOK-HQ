# The Executive Priority Engine

## "What should Jake focus on today?" - without losing anything

*Project Diamond, Sprint D18. The engine that turns Tony's situational awareness into a ranked plan -
and guarantees that nothing legitimate is ever silently forgotten.*

Implementation: `tony-alpha/dashboard/core/executive-priority.ps1` -> `Get-ExecutivePriorities`,
folded into the Executive Briefing (`Get-BriefingPriorityPlan`) as "Act first / Also today / Still
visible", rendered by `New-ExecutiveBriefingCard`.

## The hard product rule

**Everything meaningful is acknowledged. Not everything is treated as equally urgent.** The engine
never drops a legitimate task, commitment, email, event, reminder, or follow-up. It only sets aside
obvious noise - and even that is counted.

## Four levels

1. **Act Now** - drop-what-you-can: people waiting on you, a family-time conflict, an imminent
   appointment to prepare for, a hard deadline with consequence.
2. **Do Today** - important, not drop-everything: carrier/underwriting updates, a near-complete goal,
   the day's stated priorities, blocked work.
3. **Keep Visible** - legitimate but low-urgency: smaller follow-ups, non-urgent reminders, standing
   commitments (from memory), goals, gentle observations. **Never discarded** - always surfaced as a
   calm count so it can't be forgotten.
4. **Low-Value Noise** - obvious promotions/newsletters/spam and duplicates. Suppressed from the
   letter but **counted and accessible** (they are set aside, not deleted).

## Architecture (no new storage, no task database)

```
Get-ExecutivePriorities  (core/executive-priority.ps1)   -- pure, deterministic, stores NOTHING
  reads the single Executive Context (which already references every source)
   1. Get-PriorityCandidates  - collect REAL items, each preserving source + source id
   2. Merge-PriorityCandidates - dedupe the same commitment across sources
   3. Get-PriorityRanking      - judge each with the Decision Framework (FINAL AUTHORITY) + signals
   4. bucket into Act Now / Do Today / Keep Visible / Low-Value Noise (no-loss invariant checked)
        |
Get-BriefingPriorityPlan (core/executive-briefing.ps1)   -- shapes the calm letter sections
        |
New-ExecutiveBriefingCard (ui/tony-ui.ps1)               -- ACT FIRST / ALSO TODAY / STILL VISIBLE
```

It creates no context object, writes nothing, and adds no store. It reads the **one** Executive
Context (Calendar, Gmail, Action Items, approved Memory, observations, goals, current priorities, and
the Decision Framework judgment) and composes a plan on demand - Single Source of Truth throughout.

## The sources it ranks

- **Gmail** - the attention items already triaged by Email Intelligence (needs-reply, carrier,
  urgent, important-contact, invitations). Promotions/newsletters are already separated as noise.
- **Calendar** - **schedule is not a to-do list.** Events live in "Today's Schedule"; the engine
  surfaces at most ONE actionable calendar item (prep for the next real, multi-person appointment)
  plus **meaningful conflicts** (family time, or two real appointments). Intentional time-block
  overlaps are not treated as conflicts.
- **Action Items** - open items (real `AI-###` ids); a two-week-open item counts as overdue.
- **Current priorities** - the day's stated plan (from the Morning Briefing); at least "Do today".
- **Goals** - active goals kept visible; a near-complete one (>=70%) becomes "Do today".
- **Approved Memory** - standing commitments Jake asked Tony to remember (kept visible).
- **Observations** - gentle guidance kept visible (never elevated to "act now").

## The Decision Framework keeps final authority

Every candidate is judged by `Evaluate-TonyDecision` (Family Impact weighted above Financial;
Relationship weighted for People-before-Money) which returns an alignment score, conflicts, and a
priority. That judgment shapes the tier - the framework can promote or demote, and a low-priority
item with no urgency settles into Keep Visible. **People Matter More Than Money** and **Family Before
Financial** are honored: a family-time conflict is Act Now; a client waiting on you is Act Now; a
business item that would crowd out family is never allowed to bury the family item.

## No-loss guarantee

Every rankable candidate lands in exactly one of the three visible tiers (Act Now, Do Today, Keep
Visible). The engine computes a **no-loss invariant** (`legitimate == merged candidate count`) and
returns it. Keep Visible is always surfaced as a sentence ("N smaller follow-ups and M non-urgent
reminders are captured and won't be forgotten."), so low-priority items remain accessible. Only items
that match the noise tests (promotions/newsletters, exact duplicates) are set aside - and their count
is still shown.

## Deduplication

The same commitment often appears in several sources - an Action Item "Call the Millers", a Calendar
"Millers renewal call", and an email "Re: Millers renewal". The engine merges them by **distinctive
words** (a name/topic, not a generic verb like "call" or "review"), keeps one representative, and
records **every** (source, source id) it came from. Purely-generic or number-differentiated titles
("Prospect 1..8 callback", "Review carrier update" vs "Review sprint update") stay separate - no-loss
beats a wrong merge.

## Avoiding a busier day

On a meeting-heavy day the engine keeps "Act first" to **two** items (three otherwise); the overflow
drops to "Also today" - never lost - and the letter says so ("It's a full day - I kept 'Act first'
short so today doesn't get busier."). At most three Act-Now, five Also-Today shown; the rest are
acknowledged in Still Visible. The briefing stays a calm letter, not a dashboard.

## Explaining the top

The plan carries a one-line reason ("Chosen because they involve a family-time conflict and someone
waiting on you.") so Jake sees *why* the Act-First items earned the top.

## Integration (no new dashboard)

The plan replaces the old "Today's Top Three" section inside the existing Executive Briefing card -
ACT FIRST (numbered, each with a short why + the overall reason), ALSO TODAY (bullets), STILL VISIBLE
(one calm sentence), and a quiet "set aside" note for noise. If the engine is unavailable it falls
back to the original Top Three. No new screen, no automatic actions.

## Constraints honored

Uses the existing Executive Context and Decision Framework (final authority); no duplicate storage; no
separate task database; every ranked item preserves its source + source id; dedupe across sources;
nothing legitimate discarded; low-priority items remain in Keep Visible; only obvious noise
suppressed (and counted); Family Before Financial and People Matter More Than Money respected;
packed days kept calm; no automatic actions; no new dashboard; integrated into the existing briefing.

## Related
- [Executive_Context_Engine.md](Executive_Context_Engine.md) - the single context this engine reads.
- [Executive_Briefing.md](Executive_Briefing.md) - where the plan appears.
- [Tony_Decision_Framework.md](Tony_Decision_Framework.md) - the judgment that keeps final authority.
- [Multi_Account_Google.md](Multi_Account_Google.md) - the merged Calendar/Gmail signals it ranks.
