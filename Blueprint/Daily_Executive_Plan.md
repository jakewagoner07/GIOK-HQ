# Tony's Daily Executive Plan - Epic 14

*Tony reads the day you already have - goals, calendar, follow-ups, commitments, Life OS - and turns it
into a calm, realistic plan: the three outcomes that matter, what to protect, what needs a reply, what
can wait, and whether the day is overloaded. It is a **read-only executive projection** over the single
Executive Context. It creates no second store, and it never acts - any action Tony recommends becomes a
pending Executive Inbox proposal that only Jake's approval can write.*

## The permanent decision (record this)

> **The Daily Plan is a read-only executive projection. Any write becomes a pending Executive Inbox
> proposal. No provider may write directly.**

The plan is held in memory for the session or regenerated from Executive Context. Nothing about a plan
is authoritative; the sources it references are the truth, and they keep their single owners.

## The one architecture, reused

```
Get-TonyExecutiveContext (assembled once, references sources, writes nothing)
  -> Get-DailyPlanSources        : project the context into a compact, groundable "sources" list
  -> Executive Reasoning Layer   : task = briefing.compose (an EXISTING ABI task, now migrated)
       -> Claude driver          : configured + consented + available  (bounded, kernel-enforced)
       -> deterministic floor    : New-DailyPlanLocal  (the permanent composer)
  -> kernel validator            : facts only - every item grounds to a supplied source
  -> Daily Plan model            : topOutcomes / protect / followUps / canWait / recommendations / ...
  -> Home card + Daily Plan view : compact summary; full plan; write-recs -> Add-InboxProposal on approve
```

No new reasoning task id - `briefing.compose` already exists in the ABI and this is exactly what it was
declared for ("compose the executive briefing from Executive Context"). No new provider path - the same
Epic 13 Claude driver gains `briefing.compose` support. The Reasoning Layer remains the only router,
validator, fallback, timeout, and attribution authority.

## Why a compact `planSources` projection (not the raw context)

The reasoning task's input is **not** the whole Executive Context. `Get-DailyPlanSources` projects it into
a bounded, self-contained list every plan item must ground to, and that list is *also* what a Claude call
would carry. Three reasons: the raw context has deep/back-referenced fields (`base`) that isolation
cloning should not have to serialize; grounding must be a closed check against an explicit source set; and
what may leave the machine for Claude should be a deliberate projection, not "everything Tony knows".

`planSources` shape (provider-neutral, JSON-clonable):
```
{
  time:    { date, dayOfWeek, hour, partOfDay, isWeekend }
  sources: [ { sourceType, sourceId, text, when?, amount?, dueDate?, daysAway?, domain?, tier?, why? }, ... ]
  signals: { calendarToday, timeSensitiveCount, conflicts, meetingHeavy, doTodayCount, longestFreeMinutes, inboxPending }
  contextVersion
}
```
`sourceType` is one of: `goal`, `action`, `calendar`, `email`, `life:family`, `life:health`,
`life:financial`, `life:learning`, `nonNegotiable`, `priority`, `timeline`, `inbox`. Every entry keeps a
real `sourceId` from its owner (goal id, action id, calendar event id, message id, `FAM-001`, ...), so the
plan is traceable to the single source of truth and nothing is copied into a new store.

## The Daily Plan model (provider-neutral)

```
{
  meta:        { generatedAt, engine, sourceContextVersion, requestId }
  topOutcomes:     []   # 1-3 items - the outcomes that matter most today
  protect:         []   # commitments / appointments / non-negotiables to keep
  followUps:       []   # communication / follow-up needing attention
  canWait:         []   # important-but-not-today, said plainly
  recommendations: []   # 0-N; each is a RECOMMENDATION, requiresApproval when it would write
  clarifications:  []   # what Tony should ask before assuming
  workload:        { level, reason }   # light | balanced | heavy | overloaded, with an evidence reason
}
```
Each item preserves traceability:
```
{ text, sourceType, sourceId, reason, priority, confidence?, requiresApproval, proposedAction? }
```
- `sourceType` + `sourceId` MUST refer to an entry in the supplied `planSources.sources`.
- `requiresApproval = true` on anything that would write; `proposedAction` describes the write (never
  performs it): `create-action | schedule-followup | prepare-message | move-to-inbox | protect-calendar |
  defer-item`.
- Empty sections are **omitted** in the UI - Tony never pads the day.

## Local floor - the permanent deterministic composer

`New-DailyPlanLocal -PlanSources` must be useful with no Claude, offline, and forever. It reuses the
existing ranking - `Get-ExecutivePriorities` already scores **Family +40** over everything else, so
Family-before-Financial is inherited, not re-invented. Ranking rules, in order:

1. Family / personal commitments with a date or time (today or imminent).
2. Calendar obligations today.
3. Time-sensitive client / communication follow-ups.
4. Explicit deadlines (dated goals, dated financial obligations).
5. Active-goal next steps.
6. Important but non-urgent work.
7. Everything else -> `canWait`.

It respects Family before Financial, People before money, the Decision Framework's alignment (already in
the priority score), user non-negotiables (protected), and workload capacity. It **never fabricates a
missing deadline or importance** - an undated item is ranked as undated, not invented into urgency.

Composition:
- `topOutcomes` <- the top 1-3 ranked outcomes (act-now / do-today), each grounded to its source.
- `protect` <- non-negotiables + today's calendar commitments + family commitments today.
- `followUps` <- email attention items + timeline `waiting`/`overdue` follow-ups.
- `canWait` <- keep-visible / low-tier items, stated plainly.
- `recommendations` <- at most a couple of high-value, source-grounded suggestions, each
  `requiresApproval` with a `proposedAction`.
- `clarifications` <- the context's `assessment.shouldClarify` questions + genuine conflicts.

## Overload detection (conservative, evidence-only)

`workload.level` in `{ light, balanced, heavy, overloaded }` from **real** evidence only:
calendar event count today, count of time-sensitive items (act-now + overdue + waiting >2 days + invites
expiring), calendar conflicts, number of "do today" priorities, and available focus time
(`longestFreeBlock`). `workload.reason` states the evidence:

> "Today looks overloaded based on six scheduled commitments and four time-sensitive follow-ups."

It **never** diagnoses stress, burnout, ADHD, depression, or any medical condition. It counts what is
there; it does not interpret a person.

## Claude support for briefing.compose

The Epic 13 Claude driver gains `briefing.compose`. Same architecture: bounded background runspace,
kernel-enforced `maxMs` by abandonment, stale-result discard by requestId, truthful attribution stamped
by the kernel, calm degradation on 401/403/429/500/529/network/timeout/malformed to the floor. Claude
returns the Daily Plan model as strict JSON; the parser and the same fact validator police it. Claude is
used **only** when configured, available, and consent for **executive reasoning** permits the data to
leave the machine.

## Consent - task-scoped, not inherited from onboarding

Daily planning is not onboarding. Onboarding's `understanding.extract` consent does **not** grant
executive-reasoning consent. Before Executive Context data may go to Claude for a plan, Tony discloses
that the plan may include goals, calendar information, communication metadata, Life OS priorities, and
action items, and offers **Use Claude for this plan / Keep processing local / Remember my choice**.
Executive-reasoning consent is its own flag (per-attempt unless explicitly remembered), stored - like
onboarding's - in the existing gitignored Claude config. No second secrets store. Declined or absent ->
local. Diagnostics carry only safe metadata (provider, task, request id, status, duration, safe error
class, item counts, workload level) - never calendar titles, email subjects, names, goals, Life OS
content, prompts, responses, or credentials.

## Validation - facts by machine, meaning by the human

A task-specific `briefing.compose` validator (Epic 13A philosophy):
- valid model shape; **allowed sections only**;
- every item's `sourceType` + `sourceId` refers to a supplied `planSources` entry (no invented goals,
  appointments, deadlines, names, amounts, or commitments);
- **text-fact grounding (Epic 14A)**: every hard fact in an item's `text` *and* `reason` - numbers,
  currency, percentages, times, digit-form dates, and mid-sentence proper nouns - must appear in that
  cited source's own content. A valid `sourceId` can no longer conceal fabricated free text ("Call Robert
  Kessler about the $80,000 wire at 3pm" citing a goal that only says "Grow the agency" now rejects). This
  reuses the proven Epic 13A gates (`Get-UEGroundingNumbers` / `Get-UEUngroundedProperNoun`); the source
  content is read from the single `planSources` projection (`Get-DailyPlanSourceContent`) - no second store.
  Paraphrase, tone, and semantic compression are deliberately untouched: facts by machine, meaning by human;
- no fabricated `proposedAction`; the action type is from the allowed set;
- **no provider may claim an automatic action occurred**, in first *or* third person - "Meeting scheduled",
  "Email sent", "Booked your flight" reject alongside "I scheduled..."; advisory/future wording
  ("Consider scheduling...", "nothing is sent until you approve") passes. A plan can only *recommend*;
- anything that would write is `requiresApproval = true`;
- reasonable item and total-size caps;
- **one unsafe item rejects the whole result** and the kernel falls to the local floor.

**Documented residuals (inherited from Epic 13A, backstopped by mandatory review-before-write):** the
deterministic gate does not catch sentence-initial proper nouns, lowercase names, all-uppercase
organizations (exempted as acronyms), or numbers/dates written entirely as words. These pass the machine
gate and are removed by the human at the review screen - the machine provides deterministic fact checks
where they are reliable and never claims perfect named-entity recognition.

The plan is shown beside its real sources; Jake approves meaning and any action. The machine guarantees
the plan invents no facts and writes nothing.

## Approval and actions

Tony recommends; Tony never executes. Every write-producing recommendation becomes a **pending** proposal
via the existing `Add-InboxProposal` (dedup-checked against `Get-InboxProposalKeys`), and only
`Approve-InboxItem` -> the owning module writes it. No direct Calendar, Email, CRM, Goal, Identity, or
Life OS write ever originates in the Daily Plan.

## Home integration

A customizable **Daily Executive Plan** Home card (in the catalog, sizeable, optional, off by default) -
a compact summary (top outcomes count + one line) that opens the full **Daily Plan** view. It reuses the
Home layout preferences and the async host-swap pattern (`$script:HomeBriefHost` precedent) so it never
blocks the UI, reuses Executive Context and the shared provider cache (**no duplicate Gmail/Yahoo/
Calendar/CRM fetch**), and shows the local plan quickly while any Claude enrichment is pending. It does
**not** replace Tony's Executive Briefing; both can coexist. The full plan opens via the card or Tony
conversation - no new sidebar tab.

## Performance

Reuse Executive Context, the shared provider cache, the background reasoning worker, stale-result
protection, timeout-by-abandonment, and clean worker teardown. Do not re-fetch any provider the context
already carries. The local plan renders fast; Claude output never partially merges into it.

## Files

- **new** `core/daily-plan.ps1` - the model, `Get-DailyPlanSources`, `New-DailyPlanLocal`, overload
  assessment, and the recommendation->proposal mapper.
- `core/reasoning-local.ps1` - register the `briefing.compose` validator + floor delegate; remove it from
  the fail-closed list.
- `core/reasoning-claude.ps1` - support `briefing.compose` (prompt + parse + fact gate); task-scoped
  availability.
- `core/reasoning-consent.ps1` - executive-reasoning consent (distinct from extraction consent).
- `core/async-run.ps1` - an off-thread Daily Plan worker (mirrors the briefing worker).
- `core/home-layout.ps1` - the `dailyPlan` catalog entry.
- `ui/tony-ui.ps1` - the Home card, the Daily Plan view, the consent screen, the approve-recommendation
  flow.
- `tony-alpha/dashboard/tests/reasoning/` - permanent Daily-Plan tests + the four test-hygiene fixes.
- Docs: this file; Executive_Reasoning_Layer; Executive_Context_Engine; Executive_Briefing; Project
  Status; Product Roadmap; CTO Handoff.

## Commit stages
1. Blueprint and Daily Plan model.
2. Deterministic local composer + validator.
3. Claude briefing.compose driver support.
4. Home and interaction integration.
5. Permanent tests, live verification, and documentation.
