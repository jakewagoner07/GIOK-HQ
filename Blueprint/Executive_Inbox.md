# The Executive Inbox — GIOK's Approval Center

**Epic 5.** The Executive Inbox is where anything the Workforce *discovers* waits for Jake's decision
before it becomes part of his operating system. **Nothing is ever added automatically.** Tony presents;
Jake approves, edits-then-approves, or rejects. This is the single permission gate through which
proposed additions flow into the real stores.

It is **not another provider** and **not another database of your data.** It holds only **pending
review items** — the proposals themselves. The moment a proposal is approved, the **owning module**
writes the real record (a goal goes to the goal store, a task to Action Items, and so on); the moment
it's rejected, it's removed. **No second copies of anything.**

---

## Why it exists

Every Workforce member (Sam, Ava, Emma, Riley, Mason, Randy, and every future hire) can notice
something that *should* become part of Jake's world — a goal implied by a conversation, a follow-up a
client is waiting on, a renewal to track, a family date, a health routine. Left to themselves, agents
that write are dangerous. The Executive Awareness Principle says nothing meaningful is dropped — but
GIOK's permission model says nothing is added without Jake. The Executive Inbox reconciles the two: the
discovery is **captured as a proposal**, surfaced calmly, and **only Jake's approval** turns it into
real data.

## Architecture (builds on what exists — no duplication)

```
Workforce member / Tony discovers something
        | Add-InboxProposal  (any member may propose; this is NOT acting - it needs approval)
        v
Executive Inbox  (core/executive-inbox.ps1  ->  executive_inbox.json, gitignored)
   holds ONLY pending proposals - never a copy of the real data
        | Jake decides on the Executive Inbox page (Tony presents, never auto-approves)
        |
   Approve / Edit-then-Approve  --->  the OWNING module writes the real record, then the
   |                                   proposal leaves the inbox (no second copy)
   Reject  ------------------------->  the proposal is removed
```

- **Uses the existing Executive Context and Workforce.** The inbox reads/complements them; it does not
  re-implement discovery or analysis. Specialists already produce evidence-backed recommendations; a
  proposal is simply one of those recommendations, parked for approval.
- **Single Source of Truth.** The inbox is the *only* place a **pending** item lives. Approved data
  lives **only** in its owner (goals in `identity/goals.json`, tasks in `action_items.json`, the seven
  life domains in `life_os.json`, memory in `tony_memory.json`). The inbox never keeps a copy after the
  decision.
- **No automatic actions.** Approval is always Jake's. Tony ranks and presents; Tony never approves.
- **Memory stays permission-gated by its own writer.** Approving a `memory` proposal routes through
  `Approve-Memory` — the Memory Manager remains the only permanent-memory writer.
- **Read-only providers are never written.** Calendar and CRM are read-only, so a `calendar`/`crm`
  proposal cannot create an event or a CRM record; approving it creates an **Action Item follow-up**
  (an honest reminder Jake can act on himself), never a fabricated write.

## The proposal (item schema)

Every inbox item carries exactly these fields:

| Field | Meaning |
|---|---|
| `id` | `INBOX-001` (sequential) |
| `discoveredBy` | which Workforce member proposed it (e.g., `Sam`, `Randy`, `Tony`) |
| `type` | the kind of thing (goal, project, task, non-negotiable, family, health, financial, agency, learning, calendar, crm, communication, document, memory) |
| `title` | short human title |
| `description` | the details / why it matters |
| `proposedDestination` | where it would go if approved (the owning store/workspace) |
| `evidence` | list of `{ source, sourceId, detail }` that grounds the proposal (never invented) |
| `confidence` | 0.0–1.0 from the proposing member |
| `status` | `pending` · `approved` · `rejected` (the store holds only `pending`; approve/reject are terminal) |
| `created` | timestamp |
| `source` | the origin signal (e.g., `email`, `crm`, `calendar`, `conversation`, `document`) |
| `sourceId` | the id within that source (message id, opportunity id, event id, …) — provenance preserved |

## Approval routing (type → the OWNING module that writes)

On approve, the inbox calls the owner's existing writer — it never writes the data itself:

| `type` | Owner writer (existing) | Result |
|---|---|---|
| `goal` | `Add-Goal` (identity.ps1) | a goal in the one goal store |
| `project` | `Add-LifeItem projects` | a home project |
| `task` / `communication` | `Add-ActionItem` (action-items.ps1) | an action item |
| `non-negotiable` | `Add-LifeItem nonNegotiables` | a non-negotiable |
| `family` / `health` / `financial` / `agency` / `learning` | `Add-LifeItem <domain>` | a life-domain record |
| `memory` | `Approve-Memory` (memory-manager.ps1) | an approved memory (its own writer) |
| `calendar` / `crm` / `document` | `Add-ActionItem` | an honest follow-up task (read-only providers can't be written) |

After a successful write the proposal is **removed** from the inbox (the real record now lives in its
owner — no duplicate). If an owner is unavailable, approval fails honestly and the proposal stays
pending.

## Roles

- **Any Workforce member (and Tony) may create proposals** via `Add-InboxProposal` — with evidence,
  confidence, and provenance. Proposing is *not* acting; it only requests Jake's approval.
- **Tony owns the Executive Inbox.** He surfaces it calmly (a pending count in awareness), presents
  recommendations with their evidence and confidence, and **never auto-approves**. Jake decides.

## The page

A new **Executive Inbox** workspace lists pending proposals — each showing who discovered it, its type,
title, description, evidence, and confidence — with three actions:

- **Approve** — the owner writes the record; the proposal clears.
- **Edit then Approve** — adjust the title/description/type/destination first, then approve.
- **Reject** — the proposal is removed.

Calm and honest: useful empty state ("Nothing waiting for your approval"), no sample data, no
automatic changes.

## Invariants honored

Single Source of Truth (pending-only store; owners hold approved data) · no duplicate storage · no
automatic actions (approval is always Jake's) · Memory Manager the only memory writer · Decision
Framework final · read-only providers never written · sensitive proposals stay local (gitignored
`executive_inbox.json`) · evidence-or-silence (a proposal carries its source + sourceId).

## Related
- [Workforce.md](Workforce.md) / [Executive_Management.md](Executive_Management.md) — the members who propose.
- [Executive_Context_Engine.md](Executive_Context_Engine.md) — the single read the inbox complements.
- [Tony_Memory_With_Permission.md](Tony_Memory_With_Permission.md) — the same ask-first philosophy, generalized.
- [Life_Operating_System.md](Life_Operating_System.md) — the owners the inbox routes approvals to.
