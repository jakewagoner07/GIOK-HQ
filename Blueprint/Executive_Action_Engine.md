# Executive Action Engine (Epic 15, hardened 15.1)

The **sole execution authority** for Tony. Nothing in GIOK writes an owner store *as the
result of an action* except through this engine, and every execution originates from an
**approved Executive Inbox proposal** — never from a reasoning provider, never ambiently.

```
reasoning proposes  ->  Executive Inbox (pending)  ->  human APPROVES  ->  Action Engine
                                                                              |
   idempotency -> validate -> INTENT persisted -> execute -> result persisted |
   -> verify (from intent) -> succeeded                                       |
                    |            |            |     \-> failed  <-------------+
                    +------------+------------+---------> failed
```

Reasoning **proposes**; the human **approves**; the engine **records intent, executes, verifies,
and records the outcome**.

## Why it exists

Before Epic 15, `Approve-InboxItem` called `Invoke-InboxRoute` in one synchronous step: it
wrote the owner store and removed the proposal, with no explicit states, no verification, and no
audit trail. Epic 15 made execution a first-class state machine. Epic 15.1 (this hardening
sprint) closed the gaps a CTO review found, so the guarantees below are true **under crash,
retry, hostile-handler, and audit-log-failure scenarios** — the prerequisites for ever wiring a
real external connector.

## Guarantees (as enforced today)

- **Sole execution authority — fail closed.** The engine is the only path from an approved
  proposal to an owner write. `Approve-InboxItem` **has no fallback**: if the engine is
  unavailable it returns a calm error and leaves the proposal pending. There is deliberately no
  unvalidated/unaudited/unverified route.
- **Approval-first, grounded, instance-bound.** Execution requires explicit approval metadata
  (`approvedBy`, `approvedAt`, `source`, `fingerprint`, and — Epic 17 — the proposal `uid` + `id`)
  built from the real approval event. A direct call without approval fails safely; a proposal
  **edited after approval** no longer matches its fingerprint and is refused. Un-approved and
  rejected proposals never execute. **Approval binds to the exact proposal instance** (NB-1 closed):
  a reused approval object carrying a different `uid`/`id` is refused even when the content matches,
  so a direct caller can never execute one instance with another's approval. External connector
  actions **require** an instance-bound approval.
- **Intent before side effect.** Before any owner write, the engine persists an immutable
  **execution intent**: the action type, the target id — or a **pre-allocated new id** for
  create-style actions — and the exact facts that will prove the change landed. A log that cannot
  record intent blocks execution.
- **Verification before success — engine-owned.** Success is claimed only after the engine's own
  intent gate confirms the owner store changed. A handler's `verify` can add strictness but can
  never grant success; `ok=false` can never become `succeeded`; `ok=true` without a verified
  owner change fails.
- **Engine-private state.** Handlers receive a **deep-cloned request DTO** (proposal facts +
  intent — no `id`, `state`, or `history`). They cannot call `Set-ExecutionState`, and their
  return is reduced to `{ok, destination, newId, message}` — forged `state`/`history`/`succeeded`
  fields are dropped. The transition table permits only legal moves, and a terminal record is
  immutable.
- **Idempotency.** Every record carries an idempotency key (proposalId + content fingerprint). A
  succeeded twin returns its stored result (no second write); a non-terminal twin is resolved by
  verification, not re-executed; only a failed twin permits a deliberate retry. The key lives in
  the log, so idempotency survives restart. Duplicate approval clicks and repeated direct calls
  produce at most one owner write.
- **Restart safety — by stable identity (Epic 16A: exact-id for every create).** On launch, any
  non-terminal execution is resolved by **verifying its persisted intent** against the owner store,
  and success is proven by the **exact pre-allocated id**: every create — Action Items *and* owner-
  minted (goal/project/life/memory) — is a `create-id` intent whose deterministic id the owner
  persists. Recovery verifies that exact id exists. A matching **title is never evidence** (title-
  mode is retired). So the intended record actually landed → succeeded; it did not → failed (safe to
  re-propose). Recovery **never re-runs a write** and is idempotent (a second pass is a no-op).
- **Durable, corruption-aware audit.** `execution_log.json` is written by **atomic snapshot**
  (temp file + `[IO.File]::Replace`) with a `.bak` last-known-good copy, serialized by a named
  mutex. A corrupt primary recovers from the backup and **history is never silently erased**; if
  **both** copies are unreadable the store **fails closed** (reads empty, writes throw), so no
  execution proceeds unaudited and a log-write failure before a side effect prevents it.
  Retention is bounded (newest 500 terminal records; **non-terminal records are never pruned**).
- **Single source of truth.** Approved data lives ONLY in its owner; the log records *executions*,
  not business data. On verified success the proposal leaves the inbox (no copy); a failed
  execution leaves it pending.
- **Deterministic.** No AI, no network in `action-engine.ps1`; pure local dispatch.
- **No direct writes by reasoning providers.** Reasoning still only proposes.

## Execution states

`pending -> validating -> executing -> verifying -> succeeded | failed`
(`succeeded`/`failed` are terminal; `failed` is reachable from any non-terminal state). The
`Set-ExecutionState` transition table is the only legal set of moves; skipping a stage or
re-entering a terminal record is refused.

## Local actions (supported first) and action-specific validation

Validated **before** the intent is persisted (so a malformed payload writes nothing):

| Verb | Execute (from the persisted intent) | Validation | Verify (engine intent gate) |
|---|---|---|---|
| `task` / connector follow-up | create an Action Item under a **pre-allocated id** | non-empty title | the pre-allocated id exists |
| `reminder` | create the pre-allocated item with `remindAt` | valid timestamp → normalized ISO-8601 **with explicit UTC offset** | id exists and `remindAt` set |
| `set-priority` | set `priority` on the target (`sourceId`) | value in `low\|medium\|high`; target exists | target `priority` == value |
| `defer` | set `deferredUntil` on the target | valid, **non-past** date; target exists | target has `deferredUntil` |
| `archive` | archive the target | target exists | target `archived == true` |
| owner-minted (`goal`/`project`/life/`memory`) | owner writer with a **pre-allocated `-Id`** (`Add-Goal -Id` / `Add-LifeItem -Id` / `Approve-Memory -Id`) | non-empty title; owner validates id format + duplicate | the **exact pre-allocated id** exists in the owner store — never title |

Unknown proposal fields are **rejected**, not silently ignored.

## External connectors (Epic 17: Google Calendar is the first)

An external, side-effecting connector plugs into this **one** execution path — never a parallel one —
via `Register-ActionConnector -Types -BuildIntent -Execute -Verify`:

- **BuildIntent** validates + normalizes the connector's own payload (before any side effect) and
  returns the fields that will **prove the change landed by exact provider id** — for a create, a
  **deterministic client-specified id** derived from the execution idempotency key. These become the
  immutable `connector`-mode intent.
- **Execute** performs the approved external request and returns sanitized `{ok, destination, newId,
  message}` (the provider id in `newId`). It cannot change execution state.
- **Verify** is the engine's **authoritative** gate for `connector` mode: an **independent provider
  read-back by exact id**. The engine *requires* it — a missing connector/verifier or a non-true
  verdict fails closed, so an HTTP 200 without verified provider state can never reach `succeeded`.

The connector proposal carries a structured `payload`; a payload edit changes the fingerprint (so a
prior approval is invalid). Recovery re-verifies by the exact provider id in the intent and **never
re-runs** the write. Google-specific knowledge lives entirely in the connector
(`core/connectors/google-calendar.ps1`); the engine stays deterministic and network-free. See
[Google_Calendar_Connector.md](Google_Calendar_Connector.md).

## Public surface (`core/action-engine.ps1`)

- `Invoke-ProposalExecution -Proposal -Approval` — the one execution path (idempotency → validate
  → persist intent → execute → persist result → verify). Never throws.
- `Restore-ActionEngine` — startup recovery of non-terminal executions by verifying persisted intent.
- `Register-ActionHandler -Type -Execute -Verify` — register a local verb (or, later, a connector).
- `Get-ProposalFingerprint` / `Get-ExecutionIdempotencyKey` — identity + dedup.
- Audit reads: `Get-Executions`, `Get-ExecutionById`, `Get-ExecutionHistory`, `Get-ExecutionSummary`,
  `Get-ExecutionLogState` (`ok`/`backup`/`fresh`/`failed`).

## Store

`execution_log.json` plus its `.bak`/`.tmp` companions (all gitignored) — the audit trail and
restart-recovery state. It records *executions*, not business data (which remains solely in its
owner), and can reference private titles, so it is local-only and never committed.

## Permanent decisions (Epic 15.1)

- **The Action Engine fails closed** if unavailable — there is no legacy direct-write fallback.
- **Every production create uses a pre-allocated stable id (Epic 16A).** The engine derives a
  deterministic owner-format id (`<PREFIX>-X<8 hex of MD5(idempotency key)>`) before any side
  effect, persists it in the immutable intent, passes it to the owner writer (`-Id`), and verifies
  by that **exact id**. The id is stable across restart/retry and never regenerated. A durable
  per-proposal `uid` seeds the identity so distinct proposal instances get distinct ids even though
  inbox ids are reused.
- **Verification is exact-id based; recovery never infers success from titles.** Title-mode is
  **retired** from every supported create path (a fail-closed, precise-id-only remnant remains for
  any legacy record). A pre-existing or same-title record can never satisfy recovery.
- **Connector creates must use provider-side ids and idempotency keys** — a Calendar event id, a
  Gmail message id — never title/delta inference. The local owner-create-id contract is their template.
- **Intent is persisted before any side effect**; recovery re-verifies the persisted intent and
  **never blindly re-runs** a write.
- **Handlers cannot control execution state** — state, history, terminal status, and result
  persistence are engine-only; handler returns are sanitized.
- **One proposal maps to one idempotent execution.**
- **Audit persistence is atomic and corruption-aware**, fails closed when unreadable, and never
  silently erases history.
- **Google Calendar is the first external connector (Epic 17).** Calendar writes occur **only**
  through the Action Engine; create actions use a **provider-safe deterministic client event id**
  (never title/delta); success requires an **exact provider event-id read-back**; recovery reconciles
  by that id and never blindly repeats a write; approval **binds to the exact proposal instance**.
- **Gmail remains blocked** until a send-specific idempotency/verify contract exists (a Gmail send is
  irreversible and has no natural idempotency key; Calendar — idempotent-keyable and reversible — is
  deliberately first). The local handlers and the Calendar connector are the template.
