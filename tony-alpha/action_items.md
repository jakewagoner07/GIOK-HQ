# Action Items — Tony Alpha

Open decisions and to-dos. Most are driven by `issues_log.md` and by gaps in `agents_registry.json`.

**Status:** ☐ open · ◐ in progress · ☑ done

---

## Manual reconciliation needed

The live CoWork scheduled tasks are not reachable from Claude Code (see `issues_log.md → Reconciliation status`), so the registry cannot be auto-verified against the real scheduler. Until that happens, treat all schedules/last-run/status as **unconfirmed** (`meta.verified_against_scheduler = false`).

**To reconcile (pick one, read-only — do not modify/delete any task):**
- ☐ **AI-R1 — Pull the list from CoWork.** In the interactive CoWork session where the tasks live, run `list_scheduled_tasks`; paste the output (name, schedule, taskId, lastRunAt) back here.
- ☐ **AI-R2 — Or export/paste manually.** Provide each task's name + schedule (+ last run if shown).

**Then, once real data is in hand:**
- ☐ **AI-R3 — Diff for MISSING agents.** Any live task not among the registry's 22 → add it.
- ☐ **AI-R4 — Diff for DUPLICATES.** Any two live tasks doing the same job → flag in `issues_log.md`.
- ☐ **AI-R5 — Fix INCORRECT schedules.** Replace each `"schedule": "unknown"` with the real cadence.
- ☐ **AI-R6 — Link source_task_id.** Set each agent's `source_task_id` from the real taskId.
- ☐ **AI-R7 — Populate last_run/status.** Only from observed data. Keep `unknown` otherwise.
- ☐ **AI-R8 — Flip the trust flag.** Set `meta.verified_against_scheduler = true` once the diff is complete.

---

## Confirm Architecture Review 001 metadata (provisional → confirmed)

`owner`, `priority`, and `dependencies` are populated but were assigned by the review, not by GIOK (flag META-001).

- ☐ **AI-A1 — Confirm owners.** Verify each agent's department. Open question: `AG-014` Log Hours Reminder — Admin or Finance? (Finance currently has 0 agents.)
- ☐ **AI-A2 — Confirm priorities.** Verify the tiers, esp. what is truly **Critical** (only AG-001 today) vs High.
- ☐ **AI-A3 — Confirm dependencies.** Verify the upstream systems per agent; these seed the future `integrations` registry.
- ☐ **AI-A4 — Confirm downstream-impact map.** Once dependencies are trusted, sanity-check which agents share a dependency (e.g. GoHighLevel → AG-001/010/022) so a single outage's blast radius is known.

## Future registries (Registry Principle — later sprints, not now)

The registry is Tony Alpha's first database; everything eventually registers itself. Scaffolded arrays exist and are empty for now.

- ☐ **AI-G1 — Register departments' detail.** (Seeded: 7 departments DEPT-001..007.) Expand with leads/notes when useful.
- ☐ **AI-G2 — Register integrations** (`INT-###`) — derived from agent `dependencies`. *(Deferred — do not build integrations yet, just catalog.)*
- ☐ **AI-G3 — Register modules** (`MOD-###`), **memory** (`MEM-###`), **skills** (`SK-###`), **workflows** (`WF-###`) as those pieces come online.

---

## Needs your decision

- ☐ **AI-001 — Confirm schedules.** Fill in the real `schedule` for each of the 22 agents (all currently `unknown`). Priority: the daily-critical ones (GHL SMS Monitor, Email Triage, Upwork, Morning Digest).
- ☐ **AI-002 — Confirm last-run + status.** For each agent, set `last_run` and move `status` off `unknown` so the watch list becomes meaningful.
- ☐ **AI-003 — GHL texting split (OVERLAP-001).** Confirm inbound-monitor vs. outbound-batch so they don't collide.
- ☐ **AI-004 — Morning Digest vs. Tony Briefing (OVERLAP-003 / 004).** Decide coexistence: feed-in or replace. Do not delete the CoWork task.
- ☐ **AI-005 — Meta-agent split (OVERLAP-005).** Confirm Health Check vs. Performance Review roles; point both into Tony Alpha.
- ☐ **AI-006 — Weekly cluster (OVERLAP-006).** Confirm the 4 weekly agents are distinct; consider making Weekly Command Center Reminder trigger Tony's Weekly Review.
- ☐ **AI-007 — Clarify Training Scanner purpose.** Staff training? Agent training? Industry content? Update its `purpose`.
- ☐ **AI-008 — Completeness check.** Confirm the list of 22 is complete — any scheduled task not captured should be added to the registry.

---

## Tony Alpha build backlog (Phase 2+, not now — see `ROADMAP.md`)

- ☐ **AI-101 — Live status ingestion.** Integrate so `last_run`/`status` update automatically instead of manually. *(Phase 2 — deferred.)*
- ☐ **AI-102 — Auto-generate daily/weekly.** Script that reads the registry and writes `daily_status.md` / `weekly_status.md`. *(Phase 2 — deferred.)*
- ☐ **AI-103 — Alerting.** Notify when an agent goes `broken` or misses its schedule. *(Phase 2 — deferred.)*
- ☐ **AI-104 — Windows desktop launch.** Wrap the core so it opens from a desktop icon. *(Phase 3 — deferred. Core kept UI-agnostic to allow this.)*
- ☐ **AI-105 — Mobile/web access.** Web dashboard and/or Android app reading the same registry. *(Phase 4 — deferred.)*

---

## Done

- ☑ **AI-000 — Stand up Tony Alpha command center.** Created registry + tracking + reporting files (2026-07-08).
- ☑ **AR-001 — Architecture Review 001 registry improvements.** Added stable IDs (AG-###), owner/department, priority, dependencies, health_score (null), and the "everything registers" scaffolding (departments seeded; modules/integrations/memory/skills/workflows scaffolded). Registry v2.0.0 (2026-07-08).
