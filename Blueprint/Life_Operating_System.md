# Daily Driver — The Life Operating System

**Milestone.** Turn the dimmed / sample / incomplete life-and-business workspaces into fully usable
parts of GIOK. Jake enters and manages his own information; **Tony consumes it through the existing
Executive Context — never from UI controls.** No new providers, agents, or integrations. Everything
read-only for Tony (he proposes; he never acts), and every rule of Single Source of Truth is kept.

This is the design contract. It is settled here first; code follows it.

---

## The one rule that governs everything: one data type, one owner, one home

The audit found the storage is already per-domain and clean *except* for three ambiguities (goals in
three places, non-negotiables split, and five domains with no store). This milestone resolves them and
adds the missing stores **without ever creating a second store for a type that already has one.**

### Data-Ownership Map

| Data type | Authoritative owner | Storage location | Notes |
|---|---|---|---|
| **goal** (incl. family/health/financial/agency/learning goals) | `core/identity.ps1` (schema enriched) | `tony-alpha/identity/goals.json` — the **one** goal store | A "learning goal" is a **goal with `domain = learning`**, not a separate store. Enriched schema (below); existing `G-00x` ids preserved. |
| **action item** | `core/action-items.ps1` | `tony-alpha/action_items.json` | Unchanged. |
| **non-negotiable** (definition: cadence, purpose, protection, active) | `core/life-os.ps1` (**new**) | `tony-alpha/life_os.json` → `nonNegotiables[]` | The workspace owns the **definitions**. The End-of-Day Audit keeps its **daily adherence checklist** (a different data type: "did I do it today", not "what is it"). |
| **family commitment / important date / concern** | `core/life-os.ps1` | `life_os.json` → `family[]` | Family *goals* live in the goal store (`domain=family`). |
| **health routine / workout / recovery / next action** | `core/life-os.ps1` | `life_os.json` → `health[]` | Health *goals* live in the goal store (`domain=health`). |
| **financial obligation / target / review** | `core/life-os.ps1` | `life_os.json` → `financial[]` | Financial *goals* live in the goal store (`domain=financial`). Values are user-entered; never fabricated. |
| **agency production target / strategic priority / next step** | `core/life-os.ps1` | `life_os.json` → `agency[]` | Agency *goals* live in the goal store (`domain=agency`). Values user-entered. |
| **learning item** (resource, progress, next step) | `core/life-os.ps1` | `life_os.json` → `learning[]` | Learning *goals* live in the goal store (`domain=learning`); learning items are the resources/courses tracked toward them. |
| **home project** (outcome, status, next action, target date) | `core/life-os.ps1` | `life_os.json` → `projects[]` | **Fills the reserved `project` field** in the Executive Context. The one project store. |
| **approved memory** | `core/memory-manager.ps1` | `tony-alpha/tony_memory.json` | Unchanged. **Still the only permanent-memory writer.** |

**Why one `life_os.json` with named collections (not six new files):** each of the seven new record
types is exactly one named collection in one file owned by one module (`life-os.ps1`) — that is Single
Source of Truth. One file means one atomic save and one `meta.updated` stamp. Goals stay in their
existing store; memory and action items stay in theirs.

### Conflicts found and how they are resolved

1. **Goals in three places.**
   - *Canonical:* `identity/goals.json` — **the** goal store (enriched here).
   - *Parallel Memory `Goals` category:* left as-is. Memory holds *remembered facts* ("Jake wants to
     retire by 55"), not tracked goals with progress/status. The Priority Engine already de-dupes goal
     vs. memory candidates by text overlap, so no double-count. Documented as distinct: **the goal store
     is authoritative for goals; a `Goals` memory is context, not a tracked goal.**
   - *Dead `Convert-Capture -To 'goal'` route:* **fixed** — it now actually creates a goal via the goal
     store's `Add-Goal` (previously it wrote nothing — a real data-loss bug). This *reuses* the one goal
     store; it does not create a second.

2. **Non-Negotiables split.** The **definitions** (what my bright lines are, their cadence and
   protection) are owned by the new Non-Negotiables workspace (`life_os.json → nonNegotiables`). The
   **daily adherence** ticks stay in the End-of-Day Audit (`end_of_day_audit.json`) — a different data
   type (a per-day boolean, not a definition). They are complementary, not duplicate. The Decision
   Framework / Priority Engine read the **definitions** to know what to protect.

3. **Five domains with no store + projects greenfield.** Created fresh in `life_os.json`; nothing to
   migrate. Projects fill the already-reserved Executive Context `project` slot.

---

## Enriched Goal schema (migration, not a new store)

`goals.json` records gain fields; existing records are back-filled with sensible defaults on load
(`Normalize-Goal`), so nothing breaks. Legacy `target` (a year string) is preserved alongside a real
`targetDate`.

```
id        "G-001"          (unchanged; new ids continue G-{max+1:000})
title     string
domain    personal | family | health | financial | agency | learning   (default 'personal')
reason    string           (why it matters — powers the briefing's "why")
targetDate "yyyy-MM-dd" | "" (real date; legacy 'target' year kept for back-compat)
progress  int 0-100
status    active | paused | done | archived     (default derived: progress>=100 -> done else active)
nextStep  string
notes     string
created / updated  timestamps
```

## `life_os.json` record shapes (owned by `life-os.ps1`)

Every record carries `id`, `active` (bool), `created`, `updated`. Generic CRUD
(`Add-LifeItem`/`Update-LifeItem`/`Set-LifeItemActive`/`Remove-LifeItem`/`Get-LifeItems`) is driven by a
domain registry so adding a domain is configuration, not new code.

```
nonNegotiables  { id 'NN-001', title, cadence, purpose, protection, active }
family          { id 'FAM-001', kind(commitment|important-date|concern|priority), title, detail, date"" , active }
health          { id 'HL-001', kind(routine|workout|recovery|next-action), title, detail, cadence, active }
financial       { id 'FN-001', kind(obligation|target|review), title, amount"" , detail, dueDate"" , active }
agency          { id 'AG-001', kind(production-target|strategic-priority|next-step), title, detail, metric"" , active }
learning        { id 'LR-001', title, resource, progress 0-100, nextStep, active }
projects        { id 'PRJ-001', title, outcome, status(active|paused|done), nextAction, targetDate"" , active }
```

---

## Architecture (unchanged seams, extended)

```
UI workspace (ui/tony-ui.ps1)  — pure presentation + input; NO business logic
    | calls core owners' Add/Update/Set/Remove and re-renders
    v
Owners (core/): identity.ps1 (goals) · life-os.ps1 (7 domains) · action-items.ps1 · memory-manager.ps1
    | each is the single writer of its store
    v
Executive Context (core/executive-context.ps1)  — assembles ONE read-only view, references sources,
    stores nothing; NEW: folds in non-negotiables + the six domains + projects (fills `project`)
    v
Priority Engine (references goals + non-negotiables) · Executive Briefing (surfaces only today's few)
    · Workforce specialists (receive only their relevant domain slice) · Decision Framework (FINAL)
```

- **UI contains no business logic; core contains no rendering.** Workspaces call owner functions and
  re-render; owners never build WPF.
- **Tony reads domains through the Executive Context, never from UI controls.**
- **Memory Manager stays the only permanent-memory writer.** The life stores are separate and are not
  memory.
- **Decision Framework keeps final authority.** No automatic actions anywhere.
- **No placeholders in a completed workspace.** Sample/hardcoded cards are removed or replaced with real
  user data + honest empty states; nothing sample is presented as real.

## What Tony can now say (the point of the milestone)

- *"You committed to the gym as a non-negotiable, but today's calendar leaves no protected time."*
  (non-negotiable definition + calendar → Decision Framework flags the threat.)
- *"Your top agency goal is increasing production, but today's work is mostly administrative."*
  (agency goal from the goal store + action-item mix → priority reasoning.)
- *"You have a family commitment tonight, so I recommend completing the client follow-up before noon."*
  (family commitment + today's tasks → the briefing/priority ordering.)

All three are **derived** from the single Executive Context — no new integration, no fabrication.

## Closing the feedback loop (V1 Completion, Tier 1)

The workspaces made the Life OS **writable**; Tier 1 makes it **understood** so it no longer feels
write-only. No new store, tab, provider, or agent was added - only the read-back half of the loop,
built entirely on the existing Executive Context:

- **`Get-LifeContextDigest`** (in `executive-context.ps1`) folds the already-loaded domains and
  active goals into a concise, capped `lifeDigest` on the one context object - family commitments
  in the next 30 days, plus active health/financial/learning goals and items (each capped, paused
  goals excluded, source + id preserved). It writes nothing.
- **Tony now answers** "what health goals am I working on?", "what financial obligations do I
  have?", "what am I trying to learn?", and "what family is coming up?" from that digest - and when
  a domain is empty he says so plainly and offers to capture it, never inventing a goal, number,
  date, or advice.
- **The briefing** surfaces at most one or two calm, relevant life lines (family first), and omits
  the section entirely when nothing is worth raising - so read-back never becomes noise.

This is the same Single-Source-of-Truth discipline as everything above: the digest references the
stores, is assembled on demand, and is thrown away after the answer. See
[Executive_Context_Engine.md](Executive_Context_Engine.md) and
[Executive_Briefing.md](Executive_Briefing.md) for the mechanics, and
[V1_Completion_Plan.md](V1_Completion_Plan.md) for the tiered plan.

## Stages (each committed separately)

1. **Goals** — enrich the one goal store; first-class Goals workspace (CRUD); Priority sees active goals.
2. **Non-Negotiables** — definitions store + workspace; schedule-threat awareness.
3. **Family + Health** — commitments/dates/concerns; routines/workouts/recovery/next actions.
4. **Financial + Agency** — obligations/targets; production targets/strategic priorities (never fabricated).
5. **Learning + Home Projects** — resources/progress; projects fill the reserved `project` slot.
6. **Cross-workspace integration** — fold all domains into the one Executive Context; Priority references
   goals + non-negotiables; briefing surfaces only today's few; specialists get their slice; dedupe;
   preserve source + sourceId.
7. **Experience polish** — empty states, add/edit/archive flows, validation + honest errors, restart
   persistence, consistent executive design, no sample-as-real.

## Constraints honored

Single Source of Truth · one owner + one home per type · no duplicate goal/task/project/memory/priority
stores · UI has no logic, core has no rendering · Tony reads via Executive Context · Memory Manager the
only memory writer · Decision Framework final · no automatic actions · no placeholders when complete ·
sensitive Family/Health data stays local and minimal · never fabricate financial or business values.

## Related
- [Executive_Context_Engine.md](Executive_Context_Engine.md) — the single read every domain folds into.
- [Executive_Briefing.md](Executive_Briefing.md) — surfaces only what matters today.
- [Executive_Priority_Engine.md](Executive_Priority_Engine.md) — references goals + non-negotiables.
- [Workforce.md](Workforce.md) / [Executive_Management.md](Executive_Management.md) — specialists receive relevant domain slices.
- [Tony_Memory_With_Permission.md](Tony_Memory_With_Permission.md) — memory stays separate and permission-gated.
