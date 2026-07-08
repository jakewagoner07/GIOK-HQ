# Tony Alpha — Command Center

**Role:** Tony Alpha is the command center that oversees GIOK's scheduled tasks/agents (Claude CoWork and others). It does **not** run, replace, or rebuild those agents — it tracks them, summarizes what matters, and flags problems.

**Owner:** GIOK
**Created:** 2026-07-08
**Phase:** 1 — Command center + registry only (no integrations, no UI, no agent rebuilds). Later phases (desktop icon → web/Android) *wrap* this core; see [`ROADMAP.md`](ROADMAP.md).

---

## What Tony Alpha does

1. **Store** the list of agents/tasks → [`agents_registry.json`](agents_registry.json)
2. **Track** what each agent does → registry `purpose` field
3. **Track** last run, status, and issues → registry `last_run` / `status` / `issues` fields
4. **Summarize** what matters today → [`daily_status.md`](daily_status.md)
5. **Produce a Morning Briefing** → [`daily_status.md`](daily_status.md) (top section)
6. **Produce a Weekly Review** → [`weekly_status.md`](weekly_status.md)
7. **Flag** broken / missing / duplicate / overlapping agents → [`issues_log.md`](issues_log.md)

Open action items live in [`action_items.md`](action_items.md).

---

## Files

| File | Purpose |
|------|---------|
| `agents_registry.json` | Tony Alpha's **first database** and source of truth: all agents (stable ID, owner, priority, dependencies, health score, purpose, schedule, last run, status, issues) + scaffolded registries for departments/modules/integrations/memory/skills/workflows. |
| `daily_status.md` | Morning Briefing + "what matters today." Refreshed each day. |
| `weekly_status.md` | Weekly Review. Refreshed weekly. |
| `issues_log.md` | Broken / missing / duplicate / overlapping agent flags. |
| `action_items.md` | Open decisions and to-dos, mostly driven by the flags. |
| `tony_summary.md` | This file — the one-page overview. |
| `ROADMAP.md` | Phased build plan (desktop icon, then web/Android) + principles that keep the core wrappable. |

---

## Registry principle (Architecture Review 001)

**The registry is Tony Alpha's first database.** Everything eventually **registers itself** here — agents, modules, departments, integrations, memory, skills, and workflows — each with a **stable ID** so nothing is referenced by name alone. Agents and departments are populated now; the other registries are scaffolded (empty arrays) and filled in later sprints.

ID scheme: agents `AG-###` · departments `DEPT-###` · modules `MOD-###` · integrations `INT-###` · memory `MEM-###` · skills `SK-###` · workflows `WF-###`.

**Every agent now carries:** `stable_id`, `owner` (department), `priority` (Critical/High/Normal/Low), `dependencies` (upstream systems), `health_score` (null until measurable), plus the existing purpose/schedule/status fields.

**Dependencies → downstream impact.** `dependencies` lists what an agent needs *upstream*. To see what a failure hits *downstream*, invert the graph: if a shared dependency (e.g. GoHighLevel, Gmail) breaks, every agent listing it is affected. Example: **Morning Digest** depends on Calendar, Email, Tasks — if Email fails, the Morning Digest is degraded.

> ⚠️ `owner`, `priority`, and `dependencies` were assigned by the architecture review and are **provisional** until GIOK confirms them (see `action_items.md`). `health_score` is null and `status`/`last_run` remain unverified.

## Fleet snapshot (2026-07-08)

- **Total agents tracked:** 22 (`AG-001`–`AG-022`)
- **Status breakdown:** 22 `unknown` · 0 healthy · 0 warning · 0 broken · 0 paused
  - *`unknown` is honest:* Tony Alpha cannot yet observe real runs. Status stays `unknown` until either integrations are added or a status is set manually.
- **Health scores:** all `null` (not yet measurable).
- **By owner (provisional):** Operations 8 · Marketing 4 · Sales 4 · Communications 4 · Security 1 · Admin 1 · Finance 0
- **By priority (provisional):** Critical 1 · High 6 · Normal 12 · Low 3
- **Open flags:** 6 overlap candidates + 1 provisional-metadata flag (see `issues_log.md`)

### By category
- **comms (2):** GHL SMS Monitor, Upwork Message Check
- **email (3):** Yahoo Reader, Email Triage Digest, Gmail Junk Labeler
- **leads (3):** Lead Research/Referral, Engagement Leads, GHL Lead Text Batch
- **social (4):** Social Media Scan, Weekly Social Plans, Content Batch, (+ Buffer check is system)
- **reporting (3):** Morning Digest, Weekly Status Draft, Sunday Evening Recap
- **planning (1):** Sunday Weekly Planning
- **admin (1):** Log Hours Reminder
- **system (5):** Training Scanner, Agent Health Check, Buffer Connection Check, Weekly Command Center Reminder, Malwarebytes Scan, Performance Review on Agents

---

## Ground rules (Phase 1)

- Do **not** replace or duplicate the existing Claude CoWork scheduled tasks.
- Do **not** build integrations, publishing, or a fancy UI yet.
- Keep everything as plain files in this folder so it stays inspectable and version-controlled.
- When a schedule/purpose is uncertain, it is marked `unknown` and raised in `action_items.md` — nothing is guessed silently.

## How to update (manual, for now)

- Edited a real run? Set that agent's `last_run` (ISO date) and `status` in `agents_registry.json`.
- Found a problem? Add it to the agent's `issues` array **and** to `issues_log.md`.
- Refresh `daily_status.md` at the start of the day; refresh `weekly_status.md` weekly (candidate trigger: the existing *Weekly Command Center Reminder* task).
