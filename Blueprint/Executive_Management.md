# Executive Management — Tony Manages the Workforce

**Epic 4.** D20 gave Tony a Workforce he could *delegate* to. Epic 4 promotes Tony from a **delegator**
into an **Executive Manager**: he no longer simply calls every relevant specialist — he decides *who
works, who begins first, who verifies, who is skipped, when the evidence is enough, and when
uncertainty needs another opinion* — then presents **one** recommendation. This is the difference
between a switchboard and a chief of staff.

It is implemented as a **pure core module**, `core/executive-management.ps1`, built **on top of** the
Workforce Engine (D20) — it does **not** redesign it. It reuses `Get-RelevantSpecialists`,
`Invoke-Specialist`, `Test-ReportAcceptable`, and `Merge-SpecialistReports` (which keeps the Decision
Framework as final authority). It stores nothing, holds no global state, makes no provider calls of
its own, and takes no actions.

---

## Mission

Give Jake a chief of staff who **manages** a growing team well: the right specialists, in the right
order, only as many as needed, with disagreements surfaced and confidence earned from evidence — so
one calm, trustworthy recommendation reaches Jake while the depth happens beneath the surface.

## From delegator (D20) to manager (Epic 4)

| D20 — delegate | Epic 4 — manage |
|---|---|
| Call every relevant specialist | Decide **who** works, in what **order**, and **how many** |
| Merge whatever comes back | Stop as soon as the answer is **confident** (fewest necessary) |
| Detect conflicts in the merge | **Arbitrate** conflicts, seek a tiebreaker, always surface them |
| Flat trust | **Deterministic trust scoring** decides when another opinion is needed |
| — | **Skip** unavailable specialists (never woken) and record **why** |

## Management Principles (implemented)

- **Rule of Progressive Delegation** — the fewest specialists necessary to *confidently* answer the
  question. A narrow question stops at the first confident, conflict-free report; a broad "what
  happened / full status" question deliberately consults breadth (breadth *is* the answer).
- **Executive Awareness Principle** — nothing meaningful is dropped in silence. Every skip, every
  conflict, every low-confidence flag is recorded and surfaced, never hidden. Simplicity by
  organization, not omission.
- **Trust Through Evidence** — confidence is *earned from evidence*, not asserted by authority.
  Deterministic trust scoring (below), with **no invented history**.
- **Least Necessary Work** — unavailable specialists are never woken; a single Executive Context is
  reused so no specialist re-calls a provider; a specialist is never analyzed twice in one run
  (in-run ledger). Fewer API calls, less latency, no wasted work.
- **Human Attention Is Precious** — one recommendation, with transparency about who was used and why.
  Never overwhelm Jake; never hide meaningful information.

## Management Flow

`Invoke-ExecutiveManager -Task -Context -Now` runs a deterministic loop:

1. **Relevance** — `Get-RelevantSpecialists` (or an explicit `-Only` set) selects who *could* help.
2. **Rank** — available specialists first, then stable order. The first is **who begins**.
3. **Breadth** — classify the question as narrow or broad (`Test-BroadQuestion`).
4. **Progressive loop**, in rank order:
   - **Unavailable → skip** and record "not woken (least necessary work)"; its `analyze` is never
     called.
   - **Narrow + already confident (no conflict) → skip** the rest and record "answered by fewer
     specialists (progressive delegation)".
   - Otherwise **consult** the specialist (reusing a cached report if already analyzed this run).
   - Score its **trust**; a low-trust report does not stop delegation — it earns a second opinion.
5. **Verification** — a low-trust report is checked against any later same-scope report: **corroborated**
   (confidence rises) or **disagreed** (a conflict is surfaced). If no verifier exists, it is flagged
   honestly as *a lead, not a certainty* (`needsVerification`).
6. **Conflict** — same-scope opposing assessments are detected and **arbitrated** (explained, leaning
   toward the better-evidenced side, always `surfaceToJake`).
7. **Merge** — `Merge-SpecialistReports` synthesizes the accepted reports into one recommendation, with
   the **Decision Framework keeping final authority** inside the merge (Family before Financial).
8. **Return** — a **superset** of the merged report (so every existing consumer keeps working) plus the
   management record: `plan`, `specialistsConsidered`, `specialistsUsed`, `specialistsSkipped`
   (+reasons), `verifications`, `trust`, `arbitration`, `managementReasoning`.

## Trust Model

Every Workforce member exposes, via `Get-SpecialistTrust`, five values Tony uses to decide whether
another opinion is required:

| Value | How it is derived (deterministic) |
|---|---|
| **Current confidence** | the specialist's own confidence on this report |
| **Historical reliability** | a **deterministic baseline** from availability (available `0.7` / not `0.3`) — explicitly **not** a fabricated track record; GIOK stores no review history |
| **Evidence quality** | `breadth (count, capped at 3) × provenance (share of evidence with a source id)`, halved if the report status is not `ok` |
| **Last successful review** | `Now` if this run produced an `ok` report; otherwise none (observed in-run, not persisted) |
| **Known limitations** | read-only; not-connected; no-data — surfaced honestly |

Composite **trust score** = `0.5·confidence + 0.3·evidenceQuality + 0.2·historicalBaseline`. Below the
verify threshold (`0.5`), Tony seeks corroboration. **No historical data is invented** — the baseline
is clearly labelled as deterministic, and true reliability history can be layered in later without
redesign.

## Conflict Model

When specialists on the same scope disagree, Tony:

1. **Identifies** the disagreement (same scope, opposing assessment).
2. **Requests additional evidence** if a same-scope tiebreaker is available (a verification pass).
3. **Explains** it plainly (who said what, about what).
4. **Presents one recommendation**, leaning toward the better-evidenced side.
5. **Never hides uncertainty** — the conflict is always flagged (`surfaceToJake`, `showRawToJake`) so
   Jake can see the disagreement and decide.

## Workforce Awareness

Within a single run Tony knows who has already analyzed something (an **in-run ledger**), so a
specialist is never analyzed twice and existing evidence is reused. Because all specialists read the
one Executive Context, consulting them does not re-fetch providers. Skips, reuse counts, and the
consulted set are all reported for transparency.

## What it deliberately does NOT do

- **No new storage, no global state.** Pure functions over the passed-in Context; nothing persisted.
- **No actions.** It only reads and merges specialist reports — it never sends, writes, or schedules.
- **No provider calls of its own.** Specialists (read-only) are the only ones that touch data.
- **Does not redesign D20.** It builds on the Workforce Engine and preserves the Decision Framework's
  final authority via the existing merge.
- **Backward compatible.** Its return is a superset of the merged report, so `claude-provider.ps1` and
  any other consumer work unchanged.

## Future compatibility

The manager is indifferent to *which* specialists exist — it discovers them through the registry,
ranks them by trust, and consults the fewest necessary. It supports **dozens** of Workforce members
(Sam, Ava, Emma, Riley, Mason, and every future hire — a CRM manager, finance analyst, and beyond)
**without redesign**: a new specialist simply registers the standard interface and is managed like the
rest.

## Related
- [Workforce.md](Workforce.md) — the constitutional org chart and bylaws Tony manages.
- [Workforce_Engine.md](Workforce_Engine.md) — the D20 delegation layer this builds on.
- [Tony_Decision_Framework.md](Tony_Decision_Framework.md) — the judgment that keeps final authority.
- [Executive_Context_Engine.md](Executive_Context_Engine.md) — the single source every specialist reads.
- [13_Project_Diamond.md](13_Project_Diamond.md) — the quality bar.
