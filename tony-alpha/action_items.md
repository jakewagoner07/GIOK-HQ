# Action Items — Tony Alpha

Open decisions and to-dos. Most are driven by `issues_log.md` and by gaps in `agents_registry.json`.

**Status:** ☐ open · ◐ in progress · ☑ done

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
