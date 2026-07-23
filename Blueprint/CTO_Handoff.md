# GIOK — CTO Handoff

*Read this first when picking up GIOK development in a fresh chat. It carries the intent, the rules,
and the exact stopping point so nothing is lost. Pair it with `GIOK_Project_Status.md` (state) and
`Product_Roadmap.md` (what's next).*

---

## What GIOK is

GIOK is a **desktop operating system for a disciplined life and business**, built for Jake Wagoner
(licensed insurance agent, GIOK Agency, Ogden, UT). Living inside it is **Tony**, Jake's **AI Chief
of Staff**. The product exists to answer one question every day: **"What should Jake focus on
today?"** — and to help him become *better, not busy*.

It is a Windows PowerShell 5.1 + .NET WPF desktop app (no Node/Python). The first working product,
`tony-alpha/`, is a dark executive command center: Home with an Executive Briefing, Identity, Action
Items, Capture, End of Day Audit, Mission Control, a Talk-with-Tony conversation window, live
providers, and permission-based memory.

## Jake's product philosophy

Three lines are the soul of the product. If a feature contradicts any of them, it is wrong, no
matter how clever:

> **People Matter More Than Money.**
> **Your brain is for thinking, not remembering.**
> **GIOK helps you become better, not busy.**

Corollaries Jake holds to: **Family before Financial**; the ten-year test (a plan should still make
sense in ten years); **quality over quantity** — perfect experiences, don't pile on features; honesty
over polish (never fake data or hide failures).

## Project Diamond rules

Project Diamond is the quality standard. Nothing ships unless it is **useful, beautiful, simple,
fast, time-saving, and something Jake would use every day.** Practically:

- **Refine experiences, not feature counts.** Many D-sprints were behavioral refinements, not new
  screens.
- **Every sprint gets a Blueprint doc** explaining *why*, indexed in `Blueprint/00_README.md`.
- **Single Source of Truth.** No duplicate storage; engines *reference* sources, never copy them.
- **Honesty is a feature.** Unknown is said as unknown; failures explain themselves; no placeholders.
- **The blueprint wins over convenience.** Decisions are settled in `Blueprint/` first, code second.

## Tony's role

Tony is a **Chief of Staff, not a chatbot**. He is **broadly capable but purposefully grounded**:
he answers any question well (weather, history, math, general knowledge), **answer first, ground
second**, and never makes Jake feel he asked the wrong question. He reads the situation before
responding (Executive Context), weighs it against Jake's life (Decision Framework — *judgment*, not
intelligence, with Family before Financial), notices patterns kindly (Observation Engine), remembers
only with permission (Memory Manager), and explains live data in his own voice (providers are
implementation details). **AI is an implementation detail; Tony never reveals the model, prompts,
architecture, provider, or tokens.**

## Permanent architecture decisions

These are settled and should not be re-litigated without a blueprint change:

1. **Layering:** theme → core (data/logic) → providers → ui. UI has no business logic; core does no
   rendering. Dot-sourced by `dashboard.ps1` in dependency order.
2. **The AI is behind a contract.** `tony-provider-contract.ps1` is a model-agnostic request/response.
   Tony Brain never names a model; only the provider file (`claude-provider.ps1`) knows it.
3. **Judgment is separate from intelligence.** The Decision Framework runs *before* any provider and
   keeps **final authority**; the model informs, Tony judges.
4. **One Executive Context, assembled on demand, never stored.** It references sources and holds no
   state; two calls differ because the world differed, not because anything was cached.
5. **Two registries.** AI-provider registry (reasoning) and live-provider registry (information) are
   distinct. Live providers implement `relevant`/`query`/`status` and register; **Tony Brain consumes
   them generically — no per-provider dependency in the Brain.**
6. **Permanent memory is permission-gated.** `memory-manager.ps1` is the *only* writer; nothing else
   writes memory; detection proposes, the user approves.
7. **Native UTF-8 end to end.** Provider decodes responses as UTF-8; storage round-trips Unicode; no
   ASCII-rewriting "cleanup" layers.
8. **PS 5.1 reality:** no-BOM `.ps1` files are read as ANSI, so **source stays pure ASCII** — build
   non-ASCII at runtime (`[char]0xXXXX`, `\uXXXX` regex). No ternary; `$Input` is reserved.
9. **Tony manages specialists; Tony never becomes one (D20 Workforce Engine).** Specialists register
   the standard interface (`workforce-engine.ps1`), analyze existing provider outputs only (no
   duplicate logic, no new storage, no independent agent memory), and return standard reports. They
   never act, never reach Jake directly, and cannot bypass Tony — only Tony's merged synthesis is
   presented, with transparency (specialists used, evidence, reasoning) and the Decision Framework as
   final authority. Future specialists plug in with no redesign. The **org chart and bylaws are
   constitutional** — see `Blueprint/Workforce.md` (Tony, Sam, Ava, Emma, Riley, Mason, **Randy** +
   future hires), which also settles two permanent rules: the **Executive Awareness Principle** ("Tony
   never silently ignores meaningful information; he reduces complexity without reducing awareness")
   and the **Rule of Progressive Delegation** ("Tony delegates to the fewest specialists necessary to
   confidently answer the question").
10. **Specialists are built around disciplines, not vendors (Epic 3, `Randy_CRM_Manager.md`).** Randy
   the CRM Manager understands **CRM as a discipline** (leads, pipeline, renewals, underwriting,
   requirements, policies, follow-ups) — **not GoHighLevel**. A CRM is a data source, not an identity;
   a new CRM (HubSpot, Salesforce, Zoho, Pipedrive, custom) is a **provider backend + normalizer**,
   never a redesign of the specialist. The CRM reads through the existing live-provider registry as the
   `crm` signal into the one Executive Context (no CRM store, no mirror DB — Single Source of Truth),
   and Randy consumes only the **normalized CRM model**. Provider architecture is in
   `Blueprint/CRM_Provider.md`. **Built (Epic 3 Phase 3):** a read-only **GoHighLevel** backend
   (`providers/gohighlevel-provider.ps1`) + provider-neutral `core/crm-intelligence.ps1` + Randy.
   Permanent invariants for every CRM backend: **read-only by construction** (the HTTP helper issues
   **only GET**; no create/update/delete, no messaging), **no CRM mirror** (fetch on demand, store
   nothing), **honest availability** (unexposed data such as policies/renewals/requirements is reported
   `unavailable`, never fabricated), and **auth via a HighLevel Private Integration Token** (static
   bearer, gitignored, least-privilege `*.readonly` scopes; OAuth is the future multi-tenant alternative
   behind the same contract). Writes remain a later consent-gated sprint.
11. **Tony MANAGES the Workforce, not just delegates (Epic 4, `Executive_Management.md`).** A pure core
   module (`core/executive-management.ps1`) on top of D20 (it does not redesign the engine) promotes
   Tony from delegator to Executive Manager: he decides who works, who begins first, who verifies, who
   is skipped, when the evidence is enough, and when uncertainty needs another opinion — then merges into
   one recommendation (Decision Framework still final). Permanent invariants: **progressive delegation**
   (fewest specialists for narrow asks; breadth for broad), **least necessary work** (unavailable
   specialists never woken; the single Executive Context reused; no specialist analyzed twice per run),
   **deterministic trust scoring with NO invented history**, **conflicts surfaced and arbitrated**, and
   **no new storage / no actions**. Its return is a **superset** of the D20 merged report, so all
   consumers work unchanged.
12. **The life/business domains have one owner and one home each (Daily Driver, `Life_Operating_System.md`).**
   Goals are ONE enriched store (`identity/goals.json`, owned by `identity.ps1`; legacy records
   back-filled on read) — a "family/health/learning goal" is a goal with a `domain` tag, never a second
   goal store. The seven non-goal domains (non-negotiables, family, health, financial, agency, learning,
   projects) are owned by ONE module (`core/life-os.ps1`) in ONE gitignored file (`life_os.json` —
   sensitive personal data). Home Projects fill the reserved Executive Context `project` slot. Every
   domain folds **read-only by reference** into `Get-TonyExecutiveContext` (no second copy); the
   workspaces are the only writers; UI holds no business logic; Tony reads domains only through the
   context; Memory Manager stays the only memory writer; Decision Framework stays final; no automatic
   actions. Adding a domain is configuration (register its fields), not new storage.
13. **The Executive Inbox is GIOK's single approval gate (Epic 5, `Executive_Inbox.md`).** Anything the
   Workforce discovers that should enter Jake's system becomes a **proposal** in
   `core/executive-inbox.ps1` (a **pending-only** queue in the gitignored `executive_inbox.json`) —
   **never added automatically.** Any member (or Tony) may propose via `Add-InboxProposal` (proposing is
   not acting); **Tony presents and never auto-approves.** On **approve**, the **owning module** writes
   the real record (`Add-Goal` / `Add-LifeItem` / `Add-ActionItem` / `Approve-Memory`) and the proposal
   **leaves the inbox — no second copy**; on **reject** it is removed. The inbox never writes domain data
   itself, so Single Source of Truth holds and **Memory Manager remains the only memory writer**
   (a `memory` proposal routes through `Approve-Memory`). **Read-only providers are never written** —
   `calendar`/`crm` approvals become honest follow-up Action Items, never a fabricated event or record.

14. **The Workforce proposes; only Jake's approval writes (Epic 6, `Workforce_Activation.md`).** Each
   specialist has a **producer** in `core/workforce-proposals.ps1` that turns an evidence-backed finding
   into an Executive Inbox proposal; `Invoke-WorkforceProposals` runs them through a **deterministic
   de-dup/quality gate** (stable `type:sourceId`/`type:normalizedTitle` keys; suppress vs pending inbox
   **and** vs the destination owner's active records; confidence floor + per-scan cap; suppressions
   logged to diagnostics as key+type+reason only, **never content**). Producing a proposal is **not** a
   write to the operating system — it only populates the pending queue; **approval (always Jake's) is the
   sole path to a real write**, through the existing owner (Decision 13). The scan runs **on demand**
   (Executive Inbox open + a "Check for new proposals" button) — **never** inside Executive Context or the
   Briefing (which write nothing) and **never** on a scheduler. Tony's awareness of the inbox is
   **read-only** (`Get-InboxSummary`: counts only, folded into the Executive Context). Specialists are
   registered under **persona names** (Sam — Head of Communications, *she*; Ava; Mason; Emma; Riley;
   Randy). No new external provider, no auto approval, no auto send/delete/schedule/contact/CRM-write.

15. **Conversational statements become Executive Inbox proposals, never direct writes (Epic 7,
   `Conversational_Capture.md`).** When Jake states a goal/task/routine/deadline/fact in normal
   conversation, a **pure, provider-agnostic, deterministic** intent engine
   (`core/conversational-capture.ps1`) recognizes the structured intent and prepares **one** proposal in
   the Executive Inbox (`discoveredBy = Tony`, `source = conversation`, `sourceId = <message id>`) — Tony
   **never** writes directly to Goals, Life OS, Action Items, Memory, Calendar, CRM, or Documents; only
   Jake's approval writes, through the existing owner (Decision 13). Routing is **deterministic, not
   LLM-only** — any future AI interpretation must pass through this validator, which is the authority.
   Confidence bands: high → propose + a truthful "prepared for your Executive Inbox"; moderate → **one**
   clarifying question and **no** proposal; low/casual → nothing (not every sentence becomes a proposal).
   De-dup is **content-based** (`type:normalizedTitle` vs pending inbox + owner records) so it is
   idempotent, even across different message ids. Tony must **never claim something was added before Jake
   approves it** (enforced by a claude-provider guardrail). No new store, tab, provider, or schema change.

16. **Communications are provider-neutral: many vendor backends, ONE normalized signal and ONE summary
   (Epic 8, `Yahoo_Provider.md`).** Sam is **Head of Communications** (she) and never learns the vendor.
   Each mail/message source is a **backend** (Gmail via OAuth; **Yahoo via read-only IMAP + a Yahoo
   app password** — the official method, not OAuth) that normalizes to the **same** model (preserving
   `sourceAccount` + `provider`) and exposes messages only. The provider-neutral aggregator
   (`core/communications.ps1`) is the **only** place backends merge; it runs the **existing**
   `Get-ExecutiveEmailSummary` **exactly once** — there is **no second Email Intelligence engine and no
   second Executive Email Summary** — and is the **single** registrant of the `email` live signal.
   **Vendor-specific logic never leaks into Sam.** All mailbox access is **read-only** (Yahoo: `EXAMINE`
   + `BODY.PEEK` headers only — never marks seen, never fetches bodies; never STORE/APPEND/EXPUNGE/COPY/
   MOVE/DELETE). **Historical search runs only on explicit request** (read-only, evidence shown, approval
   required, never auto-scans the mailbox). Credentials stay in gitignored `*.config.json` (only
   `*.example.json` tracked); the app password, message contents, and personal data are **never logged** —
   diagnostics carry only provider, state, counts, timing, and a safe error class. Future backends
   (Outlook/M365, SMS, voicemail, Slack/Teams, social) plug in here identically — no new engine, no new tab.

17. **Heavy read-only work runs off the UI thread, behind a bounded in-memory signal cache (Epic 9,
   `Performance_Responsiveness.md`).** Measurement proved GIOK's entire perceived slowness was **live
   provider latency** (Yahoo IMAP ~20s, Gmail ~10s, Calendar ~5s), executed on the WPF dispatcher and
   re-fetched independently by more than one action - **not** compute. Two permanent additions, and only
   because the numbers demanded them: (a) `core/executive-cache.ps1` - ONE **bounded, in-memory,
   non-persisted** cache of read-only provider signals (calendar/communications/CRM) with per-entry
   `fetchedAt`+TTL (calendar 2m, communications 2m, CRM 5m), **single-flight**, **stale-on-failure**
   (returns last good marked stale), and a **synchronized hashtable** so a worker runspace and the UI
   thread share ONE cache. It stores only what providers return - **never local-domain data** (Life OS/
   Goals/Memory stay invalidate-on-write by simply not being cached) and **never becomes a second source
   of truth**; the Executive Context is still rebuilt on demand from cached signals, so SSOT and
   provider/context ownership are unchanged. (b) `core/async-run.ps1` - ONE **persistent background
   worker runspace** builds the Home briefing **model** (fetch + context, pure data) off-thread; a
   `DispatcherTimer` marshals only the finished model back, and **only the WPF card build touches the
   dispatcher**. Worker errors degrade to a null model (calm fallback); `Stop-AsyncWorkers` disposes on
   window close (no orphan runspaces/locks). Providers stay pure for explicit-refresh paths. A
   conservative **per-view cache** reuses rendered visuals for pure-presentation, session-static views
   only (Agents + markdown docs); every editable/data-driven view is always rebuilt. All read-only,
   provider-neutral, mailbox/calendar/CRM behavior unchanged; no new user-facing feature.

18. **The first external reasoning driver serves one task, and consent is its availability (Epic 13,
   `Claude_Understanding_Driver.md`).** `core/reasoning-claude.ps1` registers `claude-understanding` into
   the Epic 12 kernel and supports **only** `understanding.extract` - Claude organizes the seven onboarding
   answers into the existing Understanding Model; no other task is migrated (goals.refine, briefing.compose,
   capture.classify, etc. stay unmigrated and fail closed). **Consent IS availability:** `isAvailable() =
   Claude configured AND consent granted for THIS attempt`, so a declined / unconfigured / unasked driver is
   **not a candidate** and the kernel never passes it the answers - privacy is structural, and the
   deterministic **local floor** (permanent, offline, keyless) answers instead (`meta.engine='local'`).
   Consent is per-attempt and cleared after; **"remember my choice" is explicit opt-in only, never silent**,
   written to the **existing gitignored `claude.config.json`** (no second secrets store). A strict-JSON
   prompt/parse contract; a tighter Claude-only grounding gate (multi-anchor / token-fraction) layers
   **over**, not replacing, the kernel validator; deterministic dedup; **one unsafe item rejects the whole
   Claude result**, and Claude output is **never combined** with local output (mixed provenance is worse than
   none). `maxMs` is enforced by **abandonment, not cancellation** (PS 5.1 cannot truly cancel
   `Invoke-WebRequest`): bounded work runs in a background runspace, the deadline abandons it and falls to
   the floor with `fallbackReason='timeout'`, late results are discarded by `requestId`, and runspaces are
   reaped on close. External drivers are **trusted in-process code, NOT sandboxed** - registering one is a
   code-review event. **Nothing is saved until Jake approves** on the review screen, and validation may
   reject Claude and fall back locally - a success, not a failure. No secrets / prompts / answers / responses
   / identity are logged; diagnostics carry only provider / task / request id, status, duration, safe error
   class, item counts, and fallback reason.

19. **The Daily Executive Plan is a read-only projection; it never writes (Epic 14,
   `Daily_Executive_Plan.md`).** Tony's Daily Executive Plan turns the day Jake already has (goals,
   calendar, follow-ups, commitments, Life OS) into a calm plan - top 3 outcomes, protect, follow up, can
   wait, recommendations, clarifications, workload (empty sections omitted). **Permanent decision, verbatim:**
   *the Daily Plan is a read-only executive projection; any write becomes a pending Executive Inbox proposal;
   no provider may write directly.* It creates **no second store** - `Get-DailyPlanSources` projects the one
   Executive Context into a compact, groundable sources list (each keeping its owner `sourceId`) and is
   thrown away after composing. It **migrates the existing ABI task `briefing.compose`** (no new task id): a
   deterministic local composer (`New-DailyPlanLocal`) is the **permanent floor** with Family-before-Financial
   inherited from the priority score, and the **same** Epic 13 Claude driver now also supports
   `briefing.compose` - **no separate provider path**; the Executive Reasoning Layer stays the only router /
   validator / fallback / timeout / attribution authority. **Consent is task-scoped:** onboarding
   (`understanding.extract`) consent does **not** grant daily-planning (`briefing.compose`) consent -
   executive-reasoning consent is its own per-attempt flag (own remember flag) in the existing gitignored
   `claude.config.json` (no second secrets store), gated at **routing time, before any data is sent**, by the
   kernel's additive task-aware availability check (`isAvailableForTask` / `Test-ProviderAvailableForTask`).
   **Validation is facts-by-machine, meaning-by-the-human:** the `briefing.compose` gate enforces valid shape,
   allowed sections only, every item's `sourceType`+`sourceId` referencing a supplied context source (**no
   invented goals / appointments / deadlines / names / amounts / commitments**), no fabricated action type,
   **no provider may claim an action occurred**, anything that writes is `requiresApproval=true`, caps, and
   **one unsafe item rejects the whole result** -> the local floor. Overload detection is conservative and
   **evidence-only** (calendar density, time-sensitive count, conflicts, do-today count, free time) and
   **never diagnoses stress / burnout / medical conditions**. **Tony recommends but never executes:**
   `create-action / schedule-followup / prepare-message / move-to-inbox / protect-calendar / defer-item` each
   becomes a pending proposal via `Add-InboxProposal` (dedup-checked), and only `Approve-InboxItem` -> the
   owning module writes (Decision 13) - **no direct Calendar / Email / CRM / Goal / Identity / Life OS
   write.** An optional off-by-default Home card opens the full view (async host-swap, reuses the context +
   shared cache, no duplicate fetch); it does **not** replace the Executive Briefing and adds no sidebar tab.

## Security / privacy rules

- **Never commit secrets.** API keys, OAuth client secrets, access/refresh tokens, authorization
  codes, and personal data stay in **gitignored local files**. Only `*.example.json` placeholders are
  tracked.
- **Private-by-default local files:** `claude.config.json`, `calendar.config.json`,
  `calendar.tokens.json`, `conversation.json`, `tony_memory.json`, `memory-export-*.json`,
  `weather.config.json`, `logs/`. All gitignored.
- **Diagnostics logs contain no tokens, keys, codes, or user message text** — states, counts, timing,
  and error classes only.
- **Google Calendar is READ-ONLY** this phase (`calendar.readonly`). Any write capability is a
  separate, consent-gated sprint (mirror Memory With Permission: Tony proposes, Jake approves).
- **No cloud sync, no service accounts for personal data, no hidden background monitoring, no
  automatic actions.** Live data is fetched only when relevant / on Refresh / on explicit request.
- **Before every push:** scan staged content for `sk-ant`, `GOCSPX`, `ya29.`, token values, and
  config files; confirm private files gitignored and absent from the remote.

## Current Git state

- **Current work:** `feature/daily-executive-plan` (**Epic 14 - Tony Daily Executive Plan**), branched
  from `main` @ `43e114c` - local-only, **not pushed, not merged.** The prior sprint,
  `feature/claude-understanding-driver` (**Epic 13**), branched from synchronized `main` @ `5477355`; the
  intervening Epic 5-14 sprints are recorded in `GIOK_Project_Status.md`.
- **`main`** is at `2459b66` (Alpha PR #1 + D17 PR #2 merged). **Never merge into `main` without Jake.**
- **`release/rc2-executive-intelligence`** is the current integration branch: D18, D19, D20 (+
  constitution), Randy, and Executive Management merged in dependency order (history preserved) from
  synchronized `main`. **Local-only until Jake approves a push; not merged into `main`.**
- Feature branches still exist on the remote: `feature/executive-priority-engine` (`6dddef5`),
  `feature/executive-timeline` (`50fb539`), `feature/workforce-engine` (`e65e8f8`; the constitution
  `1ac6810` rides inside Randy/Exec-Management), `feature/randy-crm-manager` (`9cbb914`),
  `feature/executive-management` (`510670f`).
- **Working tree:** clean except the intentional untracked `Founder/` and the gitignored local
  `crm.config.json` (Jake's real HighLevel token — never committed).
- **Workflow every sprint:** build → commit locally → **push only when Jake explicitly says so**. After
  a push, confirm branch status, commit hash, remote sync, clean tree, and a secret scan.

## Exact current stopping point

**Epic 14 — Tony Daily Executive Plan** is built on `feature/daily-executive-plan` (branched from `main` @
`43e114c`): a read-only executive projection over the single Executive Context (top 3 / protect / follow
up / can wait / recommendations / clarifications / workload), migrating the existing `briefing.compose`
task with a permanent deterministic local composer and the same Epic 13 Claude driver now supporting
`briefing.compose`, task-scoped executive-reasoning consent gated at routing time by the additive
`isAvailableForTask`, the facts-by-machine `briefing.compose` validator, evidence-only overload detection,
and recommendations that become pending Executive Inbox proposals (only Jake's approval writes). New
`core/daily-plan.ps1`; modified `reasoning-local` / `reasoning-claude` / `reasoning-consent` /
`reasoning-layer` / `async-run` / `home-layout` / `tony-ui`; permanent Daily-Plan tests added. **Stopped
before pushing** — the branch is local-only, not pushed, not merged into `main`. (Prior stopping point:
**Epic 13 — Claude Understanding Driver** on `feature/claude-understanding-driver`, verified with the
permanent Claude-driver suite, likewise local-only.)

## Recommended next steps

1. **CTO review of RC2**, then push `release/rc2-executive-intelligence` (Jake's approval) and open its
   PR against `main`.
2. **Executive Automation Foundation (local scheduler)** — pre-compose the now priority-ranked,
   time-aware, workforce-backed morning briefing (Phase 3's first "ahead of you" capability).
3. **D16 — Gmail read-only provider** (same OAuth/registry/Settings pattern).
4. Begin **Phase 3 (Executive Automation):** a local scheduler to pre-compose the morning briefing.

See `Product_Roadmap.md` for the prioritized plan and the reasoning behind the order.

## Instructions for the next CTO chat

1. **Read, in order:** this file → `GIOK_Project_Status.md` → `Product_Roadmap.md` → the relevant
   subsystem Blueprint docs (`00_README.md` indexes them).
2. **Work on `feature/dashboard-alpha` only.** Do not merge to `main`. Do not push unless Jake says
   to. Leave PR #1 open.
3. **Follow Project Diamond:** blueprint the *why*, keep Single Source of Truth, be honest, refine
   experiences.
4. **Respect the PS 5.1 rules** (ASCII source, no ternary, `[char]` for non-ASCII) and **use the Edit
   tool** for `.ps1` files — never raw `WriteAllText` (AV-lock risk).
5. **Never commit secrets;** run the pre-push secret scan; keep Calendar read-only.
6. **End each sprint** with a commit (message = the sprint name), a Blueprint doc, and an update to
   `GIOK_Project_Status.md` and `Product_Roadmap.md`.
7. **Verify before claiming done** — render headless screenshots and/or run a harness test; report
   faithfully (failures included).

---

## Epic 15 / 15.1 — Executive Action Engine (permanent decisions)

The **Executive Action Engine** (`core/action-engine.ps1`) is GIOK's **sole execution authority**:
the only path from an approved Executive Inbox proposal to an owner-store write. Permanent decisions
(Epic 15.1 hardening — do not regress):

1. **Fails closed** if unavailable — there is **no** legacy direct-write fallback in `Approve-InboxItem`.
2. **Intent is persisted before any side effect;** recovery re-verifies the persisted intent and
   **never blindly re-runs** a write.
3. **Handlers cannot control execution state** — state/history/terminal/result are engine-only; a
   handler receives a deep-cloned DTO and its return is sanitized to `{ok,destination,newId,message}`.
4. **One proposal maps to one idempotent execution** (key persisted; survives restart).
5. **Audit persistence is atomic + corruption-aware** (temp+replace, `.bak` recovery, fail-closed on
   double corruption, never silently erases history, bounded retention that never prunes non-terminal).
6. **`ok=false` can never become `succeeded`; `ok=true` without owner verification fails.**
7. **External connectors (Calendar/Gmail) are blocked** until these guarantees are exercised against a
   real side-effecting connector.

**Stopping point:** Epic 15 on `feature/executive-action-engine`; hardening on
`fix/executive-action-engine-hardening` (branched from Epic 15 HEAD — Epic 15 not merged to `main`).
Execution suite (26 + 53 adversarial) green; 8/8 mutation; reasoning suite green. Not pushed.

---

## Epic 16A — Deterministic Owner-Created IDs (permanent decisions)

The pre-connector hardening that retires title-mode from the Executive Action Engine. Permanent
decisions (do not regress):

1. **Every production create uses a pre-allocated stable id.** The engine derives a deterministic
   owner-format id (`<PREFIX>-X<8 hex of MD5(idempotency key)>`) before any side effect and passes it
   to the owner writer via `-Id`.
2. **Verification is exact-id based.** Recovery and runtime verify the exact owner-record id.
3. **Title-mode is retired** from all supported Action Engine create paths (a fail-closed, precise-id
   remnant survives only for legacy records).
4. **Recovery never infers success from titles** — a matching or pre-existing title is never evidence.
5. **A durable per-proposal `uid`** (not the reusable `INBOX-NNN` id) seeds identity/idempotency, so
   distinct proposal instances get distinct stable ids and retries of the same proposal reuse theirs.
6. **Connector creates must use provider-side ids and idempotency keys** (Calendar event id, Gmail
   message id) — never title/delta inference.

**Stopping point:** Epic 16A merged to `main` (`b83fb0b`).

## Epic 17 — Google Calendar Connector (permanent decisions)

GIOK's **first external side-effecting connector** — the write path (create/update/cancel events),
scope `calendar.events`, a **separate consent + token store** from the read-only provider. Full
contract in [Google_Calendar_Connector.md](Google_Calendar_Connector.md). Permanent decisions:

1. **Google Calendar writes occur only through the Action Engine.** No parallel path; no direct write
   from Tony, Claude, Daily Plan, Briefing, Inbox UI, Calendar view, reasoning, n8n, or any helper.
2. **Approval binds to the exact proposal instance** (uid + id + content fingerprint), not content
   alone — this closes NB-1 and is a permanent engine guarantee for external connectors.
3. **Create actions use provider-safe idempotency** — a deterministic client-specified event id
   (`giok` + hex of the idempotency key; base32hex) — never title/delta. A duplicate insert (409) is
   read back and treated as created; no duplicate event across retry/crash/restart.
4. **Success requires an exact provider event-id read-back.** An HTTP 200 without verified provider
   state is a failure (engine-owned `connector` verify mode).
5. **Recovery reconciles by exact provider id; it never blindly repeats a write** (windows A-E).
6. **Least-privilege write scope**, separate token store (`calendar.write.tokens.json`, gitignored);
   no calendar data flows to Claude merely because Calendar is connected.
7. **Gmail remains blocked** until a send-specific idempotency/verify contract exists.

**Stopping point:** Epic 17 on `feature/google-calendar-connector` (from `main` @ `b83fb0b`).
Execution suite 26 + **82** + 106 + 61 + 51 green; **7/7 connector mutation**; reasoning 8/8; 7/7
render. Not pushed. **Live test-calendar verification is pending** (needs the user's explicit
approval + real OAuth credentials on a dedicated test calendar — never the primary calendar).
