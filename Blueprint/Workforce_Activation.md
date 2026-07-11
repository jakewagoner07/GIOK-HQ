# Workforce Activation — the Workforce starts proposing

**Epic 6.** The Workforce already analyzes; now it **proposes**. Each specialist may turn an
evidence-backed finding into a **proposal** in the Executive Inbox. Tony presents; **Jake approves,
edits, or rejects**; only then does the **owning module** write. Nothing reaches the operating system
automatically.

## The permanent flow (the whole epic in one line)

```
Discover  ->  Analyze  ->  Propose  ->  Tony reviews  ->  Jake approves  ->  Owning module writes
(signal)     (specialist) (Executive   (awareness +      (Approve/Edit/     (Add-Goal / Add-LifeItem /
                           Inbox)        briefing)         Reject)            Add-ActionItem / Approve-Memory)
```

A **proposal is not an action.** Generating a proposal writes only to the pending Executive Inbox — never
to the OS. Approval (always Jake's) is the only thing that writes real data, through the existing owner.
So this epic changes *what the Workforce may create*, not *who may write*.

## Architecture

- **`core/workforce-proposals.ps1`** — the producer + de-duplication + scan layer. Per-specialist
  producers read the **same signals the specialists already analyze** (Gmail via `Get-Email`, Calendar
  via `Get-Calendar`, CRM via `Get-CRM`, the Priority Engine, the Timeline, Document Intelligence) and
  emit **candidate** proposals. `Invoke-WorkforceProposals` runs the producers, passes every candidate
  through the de-dup/quality gate, and adds survivors via `Add-InboxProposal`. No new external provider.
- **`core/executive-inbox.ps1`** (extended) — gains `Get-InboxSummary` (read-only awareness) and stable
  proposal-key helpers used by the gate.
- **When it runs (trigger):** on **opening the Executive Inbox** and via an explicit **"Check for new
  proposals"** button — *not* inside Executive Context or the Briefing (those still write nothing) and
  *not* on a background timer (no scheduler this epic). The scan is **idempotent** (the gate prevents
  repeats), so running it repeatedly is safe. Producers that need a disconnected provider stay silent.

### Invariants (unchanged, enforced)
Single Source of Truth · Executive Inbox is pending-only · **owning modules remain the only writers** ·
**Memory Manager the only memory writer** (a `memory` proposal routes through `Approve-Memory` on
approval) · **Decision Framework final** · **no automatic approval** · **no automatic sending, deleting,
scheduling, contacting, or CRM change** (producers only *propose*; read-only providers are never
written) · every proposal preserves `evidence`, `source`, `sourceId`, `discoveredBy`, `confidence` ·
Jake is never overwhelmed (dedup + confidence floor + per-scan caps).

## Producer rules by specialist

- **Sam — Head of Communications** *(female; sources are the connected Gmail accounts; Yahoo is future)*.
  Mission: no important communication is missed, regardless of source. Proposes, from the Email
  Intelligence attention items (which already exclude bulk): **communication follow-up** (a real human
  waiting / needs a reply / a client to follow up), **calendar suggestion** (an explicit invitation),
  **action item** (a clear deadline), and a **goal/project/non-negotiable only** when the message plainly
  states a real commitment Jake made. Never proposes from newsletters, promotions, automated
  notifications, vague informational mail, duplicates, or a message already represented by an active
  action item or pending proposal.
- **Ava — Calendar Manager.** Proposes **meeting-preparation action**, **calendar-conflict follow-up**,
  **threatened non-negotiable** (a non-negotiable exists but the day leaves no protected time), and
  **family-time conflict**. **Never writes the calendar** — every output is a proposal.
- **Riley — Timeline Analyst.** Proposes **overdue/aging follow-up**, **a commitment going stale**, and
  **an expiring item** — from existing timestamps only. Stable keys mean the *same unchanged* overdue
  condition is proposed once, not every day.
- **Emma — Priority Analyst.** Proposes a **neglected goal**, a **priority conflict**, and a **goal
  next-step action**. Keyed by goal id so an unchanged goal is not re-proposed daily.
- **Randy — CRM Manager.** Proposes **CRM follow-up**, **stalled-opportunity review**, **overdue task**,
  and **underwriting attention** — from real Opportunity data. On Jake's current account (**zero
  Opportunity records**) Randy **stays quiet** rather than fabricate.
- **Mason — Document Analyst.** Proposes **only** from a document Jake **explicitly** asks him to analyze
  (`Get-MasonProposals -Document <path>`), never from folder monitoring. Supported types: goal, project,
  action item, non-negotiable, family, health, financial, agency, learning, memory. Shows the extracted
  evidence and never treats uncertain language ("maybe", "thinking about") as a firm commitment.

## De-duplication & quality model (deterministic first)

Before a candidate becomes a proposal, the gate:
1. Builds a **stable proposal key** — `type:sourceId` when a source id exists (email message id, event
   id, opportunity id, goal id, action id), else `type:normalizedTitle` (lower-cased, punctuation
   stripped, distinctive words).
2. **Suppresses vs. pending inbox** — a pending proposal with the same key (or same `type`+`sourceId`,
   or same normalized meaning) blocks the candidate.
3. **Suppresses vs. the destination owner's active records** — e.g., a communication follow-up whose
   normalized title matches an existing open Action Item, or a goal-next-step whose goal already has a
   matching `nextStep`, is dropped (no duplicate destination record).
4. **Suppresses unchanged repeats** — the same key seen before (still pending or already an owner record)
   is not re-proposed; only a *changed* condition re-proposes.
5. **Confidence floor + per-scan cap** — low-confidence candidates and overflow beyond a small per-scan
   cap are dropped, so Jake is never flooded.
6. **Records the suppression reason in diagnostics** (`Write-TonyDiag`) — key + type + reason only,
   **never the private content**.

## Tony awareness (Stage 1) & presentation (Stage 8)

`Get-InboxSummary` gives Tony a **read-only** view: pending count, counts by type, oldest pending age,
and high-confidence / time-sensitive counts — folded into the Executive Context as `inbox` (a read, not
a write). Tony can then say: *"You have seven Workforce proposals waiting for review: two communication
follow-ups, three action items, and two goals."* — **counts, not sensitive details** (details only when
the question asks). The Executive Briefing mentions it **calmly and only when useful** — *"The Workforce
prepared five items for review; two are time-sensitive."* or *"Nothing needs approval right now."* —
never a list of every proposal.

## What this epic does NOT do
No new external providers · no auto-approval · no auto send/delete/schedule/contact/CRM-write · no
background/folder monitoring · no scheduler (the scan is on-demand) · no change to who writes real data.

## Related
- [Executive_Inbox.md](Executive_Inbox.md) — the approval center proposals flow into.
- [Workforce.md](Workforce.md) / [Workforce_Engine.md](Workforce_Engine.md) — the members now proposing.
- [Executive_Context_Engine.md](Executive_Context_Engine.md) — folds in the read-only inbox awareness.
- [Tony_Memory_With_Permission.md](Tony_Memory_With_Permission.md) — the same ask-first principle.
