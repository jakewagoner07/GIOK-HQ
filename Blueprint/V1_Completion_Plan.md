# V1 Completion Plan — finish the operating system, don't expand it

GIOK's workspaces exist; this plan **closes the loops** so the OS feels finished rather than adding new
surface. It is ordered by daily-usability payoff. No new providers, tabs, stores, agents, or major
architecture — every step folds **already-entered** data forward through the **existing** Executive
Context, Briefing, and provider prompt.

## The tiers (payoff order)
- **Tier 1 — Close the Life OS feedback loop** *(this milestone)*. Health, Financial, Learning, and
  broader Family data is entered but was **write-only** — invisible to Tony's reasoning, the briefing,
  and conversation. Surface it, read-only, calmly.
- **Tier 2 — Let the Workforce/Tony propose into the six dormant domains** (the inbox routing already
  supports non-negotiable/family/health/financial/agency/learning; no producer emits them yet).
- **Tier 3 — Finish CRUD + validation** (Action Items rename; numeric/enum validation; delete
  confirmation; reconcile Home Projects' dual lifecycle).
- **Tier 4 — Remove the seams** (retire SAMPLE/coming-soon cards; nav/UX cleanups).

---

# Tier 1 — Close the Life OS Feedback Loop

**Mission.** Health, Financial, Learning, and broader Family information must no longer feel write-only.
Tony understands and **selectively** surfaces what Jake already entered — without overwhelming him.

## Architecture (read-only assembly, no new stores)
The data is already loaded into the **one** Executive Context (`$life` = the seven Life OS domains via
`Get-LifeItems -ActiveOnly`; `$activeGoals` = the goal store). Tier 1 adds a **pure digest builder** over
that already-loaded data and threads it through the existing surfaces:

```
Life OS stores (life_os.json + identity/goals.json)   <- Single Source of Truth (unchanged owners)
        | Get-LifeItems -ActiveOnly / Get-ActiveGoals  (already assembled in the ONE context)
        v
Get-LifeContextDigest  (NEW, pure, in executive-context.ps1)
  concise, capped, source-tagged per-domain summaries (family/health/financial/learning)
        | context.lifeDigest  (read-only field; no new store)
        +-- provider LIFE CONTEXT block  -> Tony can ANSWER domain questions (Stage 3)
        +-- Executive Briefing lifeFocus -> ONE calm, selective life line (Stage 2)
        +-- Priority Engine / Decision Framework already read activeGoals + non-negotiables (Stage 4)
```

- **No new store, tab, provider, agent.** The digest is computed on demand from what the context already
  holds; it is never persisted.
- **Single Source of Truth preserved.** Goals live in `identity/goals.json`; the six life domains in
  `life_os.json`. The digest only *reads* them (through the existing accessors) and tags every entry
  with its `id` + `source` (`goal` or `life:<domain>`).

## Stage 1 — Executive Context (`Get-LifeContextDigest`)
For **family, health, financial, learning**, assemble a concise, capped, structured digest from the
already-loaded goals + life items:
- **Family** — `upcoming` dated commitments (date within today..+30d, sorted, capped 3, with `daysAway`),
  plus the active-item count. *(Not just today's items.)*
- **Health** — active `health` goals (title/progress/nextStep/targetDate) + health routines/next-actions
  (life items: title/kind/cadence/detail), capped.
- **Financial** — active `financial` goals + obligations/targets (life items: title/amount/dueDate/
  `daysAway`), capped.
- **Learning** — active `learning` goals (progress/nextStep/targetDate) + learning items (resource/
  progress/nextStep), capped.
Rules: **paused/inactive excluded** (active goals only; `-ActiveOnly` life items); **missing dates
tolerated** (no `daysAway`, item still shown); **caps** (≈4 per list) so the prompt never bloats;
`source` + `id` preserved; **nothing fabricated** — only fields Jake entered.

## Stage 2 — Executive Briefing (`lifeFocus`)
One calm, life-aware line (occasionally two), chosen deterministically from the digest, surfaced **only
when it matters**:
- an **upcoming family commitment this week** worth protecting,
- a **financial due/review date approaching**,
- a **health goal with a clear next step but a full day** (uses the live calendar's meeting-heavy signal),
- a **learning goal that hasn't moved** (uses the goal's existing `updated` timestamp — no new history DB).
Rules: **omit when nothing is relevant**; not all domains every day; prefer 1–2 high-value observations;
**no medical/legal/tax/investment advice**; **no invented urgency**; reduce day-to-day repetition by
rotating among eligible observations by day-of-year and relying on date/`updated` timestamps that
naturally change.

## Stage 3 — Tony conversation
The enriched provider **LIFE CONTEXT** block lets Tony answer, from the Executive Context (never from UI
controls or files): "what health goals am I working on?", "what financial goals/obligations do I have?",
"what am I trying to learn?", "what family commitments are coming up?", "how do my goals and schedule fit
today?". Tony uses only the digest's facts; the guardrail against invention stays in force.

## Stage 4 — Priority & Workforce compatibility
- The **Priority Engine** already reads `context.activeGoals` (all domains) and non-negotiables; confirm
  it surfaces health/financial/learning goals and that **family commitments can outweigh conflicting
  financial/business work** (the **Decision Framework's Family-before-Financial** remains final).
- **Workforce specialists** receive only their relevant slice of the one context — **no specialist is
  expanded outside her/his role**. **Executive Inbox** and **Conversational Capture** are **unchanged**.

## Invariants
Single Source of Truth · read the existing Life OS stores only · no duplicate storage · no new tabs · no
automatic actions · never fabricate values/progress/dates/risks/advice · Decision Framework final ·
**Family Before Financial** and **People Matter More Than Money** permanent · the briefing stays calm and
selective.

## Related
- [Life_Operating_System.md](Life_Operating_System.md) · [Executive_Context_Engine.md](Executive_Context_Engine.md)
  · [Executive_Briefing.md](Executive_Briefing.md) · [Tony_Decision_Framework.md](Tony_Decision_Framework.md)
