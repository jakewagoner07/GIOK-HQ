# Executive Action Engine (Epic 15)

The **sole execution authority** for Tony. Nothing in GIOK writes an owner store *as the
result of an action* except through this engine, and every execution originates from an
**approved Executive Inbox proposal** — never from a reasoning provider, never ambiently.

```
reasoning proposes  ->  Executive Inbox (pending)  ->  human APPROVES  ->  Action Engine
                                                                              |
     pending -> validating -> executing -> verifying -> succeeded            |
                    |             |            |     \-> failed  <------------+
                    +-------------+------------+--------> failed
```

Reasoning **proposes**; the human **approves**; the engine **executes, verifies, and records**.

## Why it exists

Before Epic 15, `Approve-InboxItem` called `Invoke-InboxRoute` in one synchronous step: it
wrote the owner store and removed the proposal, with no explicit states, no verification, and
no audit trail. That is fine until executions can fail partway (a half-written store, a crash
between write and confirmation, and — later — a live connector that a network can drop). The
Action Engine makes execution a first-class, observable, recoverable process.

## Guarantees

- **Sole execution authority.** No connector or module executes an approved action outside the
  engine. Local actions run through it now; when live connectors (Calendar/Email/CRM) gain write
  capability, they register as engine handlers — they never execute on their own.
- **Approval-first.** The only trigger is `Approve-InboxItem`. An un-approved proposal produces
  no execution and no owner write; a rejected proposal is never executed.
- **Verification before success.** Success is *never* claimed until the engine confirms the owner
  store actually changed (the new record exists by id, the field is set, the item is archived).
  A handler that reports success with an id the verifier cannot find is marked **failed**.
- **Complete audit trail.** Every execution is a durable record in `execution_log.json` with the
  full state history (each transition timestamped with a reason). The log is the history *and*
  the restart-recovery source.
- **Restart safety.** On launch, any execution left non-terminal (a crash mid-flight) is resolved
  by **re-verification**: if the owner change actually landed, it is marked succeeded; otherwise
  failed (safe to re-propose). It is **never re-run blindly** — that is how a crash could
  double-write.
- **Single source of truth.** Approved data lives ONLY in its owner. The engine writes through the
  owner's own functions and keeps no second copy of business data; the log records *executions*,
  not the data. On verified success the proposal leaves the inbox (no copy). A failed execution
  leaves the proposal **pending** so it can be retried.
- **Deterministic.** No AI, no network in `action-engine.ps1`; pure local dispatch.
- **No direct writes by reasoning providers.** Unchanged: reasoning still only proposes.

## Execution states

`pending -> validating -> executing -> verifying -> succeeded | failed`
(`succeeded`/`failed` are terminal). Persisted at every transition, so the state is durable.

## Local actions (supported first)

Executed against the Action Items owner store, each with an execute step **and** a verifier:

| Verb (proposal type) | Execute | Verify |
|---|---|---|
| `task` / owner types | route through the owner's writer (`Invoke-InboxRoute`) | the owner record exists by id (`Test-ExecutionApplied`) |
| `reminder` | create an Action Item carrying `remindAt` | the item exists **and** has `remindAt` |
| `set-priority` | set `priority` on the target Action Item (`sourceId`) | the target's `priority` equals the requested value |
| `defer` | set `deferredUntil` on the target Action Item | the target has `deferredUntil` |
| `archive` | archive the target Action Item | the target is `archived = true` |

Owner-routed proposals (goal / project / life domains / memory / connector follow-ups) also flow
through the engine and are verified by looking the new record up in its owner
(`Get-ActionItemsData`, `Get-GoalsList`, `Get-LifeItemById`, `Get-Memories`).

## Public surface (`core/action-engine.ps1`)

- `Invoke-ProposalExecution -Proposal` — the one execution path (validate → execute → verify).
  Never throws; any failure transitions to `failed` with a truthful reason.
- `Restore-ActionEngine` — startup recovery of non-terminal executions by re-verification.
- `Register-ActionHandler -Type -Execute -Verify` — register a local action verb (or, later, a
  connector) as an engine handler.
- `Test-ExecutionApplied -Destination -NewId` — the verification gate (owner-store lookup).
- Audit reads: `Get-Executions`, `Get-ExecutionById`, `Get-ExecutionHistory`, `Get-ExecutionSummary`.

`Approve-InboxItem` delegates to `Invoke-ProposalExecution`; if the engine module is absent it
falls back to the direct owner route, so approval is never a hard dependency on the engine.

## Store

`execution_log.json` (gitignored) — the audit trail and restart-recovery state. It records
*executions*, not business data (which remains solely in its owner). Like the Executive Inbox, it
can reference private titles, so it is local-only and never committed.

## Permanent decision

**Execution is a verified, audited, approval-gated process — never a silent side effect.** The
Action Engine is the only path from an approved proposal to an owner write, success is claimed only
after verification, and a crash is recovered by re-verification, never by a blind re-run.
