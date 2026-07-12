# Conversational Capture — tell Tony, and he prepares the proposal

**Epic 7.** Jake says something in normal conversation ("I want to lose 20 pounds"), and Tony
**recognizes the structured intent and prepares the right Executive Inbox proposal** — never writing to
the operating system himself. It is the Workforce Activation flow (Epic 6) extended to the one place Jake
already talks to Tony: the conversation.

## The permanent flow

```
Jake says it  ->  Tony recognizes possible structured info  ->  Tony PROPOSES
              ->  Executive Inbox  ->  Jake approves / edits / rejects  ->  owning module writes
```

A proposal is **not** an action. Recognizing intent and preparing a proposal writes **only** to the
pending Executive Inbox. Approval (always Jake's) is the only thing that writes real data, through the
existing owner. Tony never says a thing was "added" or "saved" before Jake approves — at most it was
"prepared for your Executive Inbox."

## Architecture

- **`core/conversational-capture.ps1`** — a **pure, provider-agnostic intent engine**. Given a message
  (and its conversation message id), it deterministically decides whether the message contains a
  structured commitment/goal/plan/reminder/routine/fact, what **type** it is, a clean **title**, a
  **confidence band**, and an **evidence excerpt** — or that it should be **ignored**, or that Tony
  should **ask one clarifying question**. It contains **no LLM call and no provider wording**.
- **Reuses everything.** Proposals are created through the existing `Add-InboxProposal`; de-duplication
  reuses `Get-ProposalKey` / `Test-DestinationDuplicate`; approval routing is the **unchanged** inbox
  routing (Epic 5). No new store, no new tab, no new external provider, no schema change.
- **The conversation hook** (`Send-TonyMessage`, `ui/tony-ui.ps1`): a natural-language message that is
  not an explicit quick-command runs through the engine after it is logged (so its message id is known).
  The engine's outcome surfaces as one calm, **truthful** line appended to Tony's reply.
- **Determinism first.** Routing is 100% deterministic in V1 — the mission's "Tony recognizes" is
  realized by rules, not the model. If an AI interpretation is ever added, it must pass **through this
  deterministic validator**; the engine is the authority, never the model alone.

### Invariants (unchanged, enforced)
Tony **never** writes directly to Goals, Life OS, Action Items, Memory, Calendar, CRM, or Documents ·
all conversational changes go through the **Executive Inbox** · **Jake must approve** · Single Source of
Truth · **Memory Manager the only memory writer** (a `memory` proposal routes through `Approve-Memory`
on approval) · **Decision Framework final** · no automatic approval · no automatic actions · no new
storage · **not every sentence becomes a proposal** · Tony asks **one short clarifying question** when
the type/intent is uncertain · Tony never falsely claims something was added before approval.

## The intent model (deterministic)

For each message the engine derives signals, then routes:

**Gate — is there any intent at all?** A message is only considered when it carries a **commitment / goal
/ reminder / routine / non-negotiable / remember** marker. Casual talk, jokes, questions-without-a-
commitment, and hypotheticals fall straight through to *ignore*.

**Weak language demotes.** "maybe / someday / eventually / might / thinking about / what if / in theory /
would be nice" pull a would-be goal down to **moderate** (clarify) — never a silent high-confidence
proposal. "I want to…" is a commitment; "Maybe someday…" is not.

**Type routing (first match wins where precedence matters):**

| If the message… | Type | Example |
|---|---|---|
| is an explicit reminder / single next action (`remind me to…`, `remember to…`) | **action item** (`task`) | "Remind me to call Mike tomorrow." |
| says a routine is inviolable (`… is non-negotiable`, `no matter what`) | **non-negotiable** | "Family dinner every Sunday is non-negotiable." |
| names a multi-step build (`project`, `build/launch/roll out a …`, "this sounds like a project") | **project** | "This sounds like a project." |
| is a fact/preference to preserve (`remember that …`, `keep in mind …`, `for the record …`) | **memory** | "Remember that my E&O policy renews in March." |
| is a health aspiration (lose/gain weight, workout, sleep, run, diet…) | **health** | "I want to lose 20 pounds." |
| is a money aspiration (save, invest, budget, pay off, $…) | **financial** | "I want to save \$50,000." |
| is business growth (GIOK, agency, subscribers, clients, policies, pipeline…) | **agency** | "I want GIOK to reach 1,000 subscribers." |
| is skill/knowledge (learn, study, course, certification, a language…) | **learning** | "I want to learn Spanish." |
| is a family routine/commitment (no "non-negotiable") | **family** | "We have movie night every Friday." |
| is a clear achievement with no domain | **goal** | "I want to write a book." |

**Confidence bands → behavior:**
- **High** — a clear single type, an explicit commitment, no weak language → **create the proposal** and
  tell Jake plainly: *"That sounds like a Health goal. I've prepared it for your Executive Inbox."*
- **Moderate** — a commitment with weak language, or two plausible types → **ask one clarifying
  question**, create nothing: *"Should I treat that as a Financial goal, or just remember it as a future
  idea?"*
- **Low** — no real commitment / casual / a bare question → **do nothing** (no proposal, no claim).

**Distinctions the engine makes:** "I want to…" vs "Maybe someday…"; a tracked **goal** vs an approved
**memory** (`remember that <fact>` → memory; `I want to <achieve>` → goal); an **action item** vs a
**project** (single concrete action vs multi-step build); a **routine** vs a **non-negotiable** (only
"non-negotiable"/"no matter what" makes it inviolable); a **domain** item vs a **general** goal.

## Clarification behavior
Only at **moderate** confidence, and only **one** question, offering the two most likely readings
(domain-goal vs remember-as-idea, or type-A vs type-B). No proposal is created until Jake answers; his
answer is a normal next message that the engine re-reads.

## Deduplication (idempotent)
Every proposal preserves the **source conversation message id** as `sourceId` (provenance), but
de-duplication is **content-based**: the engine compares the candidate's `type:normalizedTitle` against
(1) every pending inbox proposal and (2) the destination owner's active records (`Test-DestinationDuplicate`).
So saying the same thing twice — even in two different messages with different ids — creates **no second
proposal**. Creating a proposal is idempotent.

## What every capture proposal carries
`discoveredBy = Tony` · `source = conversation` · `sourceId = <message id>` · `type` · `title` ·
`description` · `proposedDestination` (the owning store/workspace label) · `confidence` · `evidence`
(the exact excerpt of what Jake said) · `status = pending`.

## What this epic does NOT do
No new tab · no new external provider · no new store or schema field · no LLM-only routing · no automatic
approval or action · no direct writes · it does not turn ordinary conversation into a stream of proposals.

## Related
- [Executive_Inbox.md](Executive_Inbox.md) — the approval center every capture flows into.
- [Workforce_Activation.md](Workforce_Activation.md) — the same Discover→Propose→Approve→Owner-writes flow.
- [Tony_Memory_With_Permission.md](Tony_Memory_With_Permission.md) — the ask-first principle a `memory` capture honors.
- [Life_Operating_System.md](Life_Operating_System.md) — the owners approvals route to.
