# Issues Log — Tony Alpha

Tracks agents that are **broken**, **missing**, **duplicate**, or **overlapping**. Each entry is a flag for review — an overlap flag is *not* an accusation that an agent is wrong, just a "confirm these are distinct on purpose."

**Legend:** 🔴 broken · 🟠 missing · 🟡 duplicate · 🔵 overlap · ✅ resolved

---

## Open flags

### 🔵 OVERLAP-001 — GHL SMS Monitor ↔ GHL Lead Text Batch Reminder
Both touch GoHighLevel texting. Likely fine (inbound monitor vs. outbound batch reminder), but confirm they don't both react to the same events.
**Agents:** `ghl-sms-monitor`, `ghl-lead-text-batch`
**Ask:** Is one strictly inbound (replies) and the other strictly outbound (batch sends)?

### 🔵 OVERLAP-002 — Lead Research/Referral ↔ Engagement Leads
Both operate on "leads." Confirm one is top-of-funnel research/sourcing and the other is follow-up/engagement of existing leads.
**Agents:** `lead-research-referral`, `engagement-leads`
**Ask:** Do they read/write the same lead list? Any risk of double-contacting a lead?

### 🔵 OVERLAP-003 — Email Triage Digest ↔ Morning Digest
A triage digest and a morning digest may cover the same ground.
**Agents:** `email-triage-digest`, `morning-digest`
**Ask:** Does Morning Digest include the email triage, or are they two separate emails? Consolidate if redundant.

### 🔵 OVERLAP-004 — Morning Digest ↔ Tony Alpha Morning Briefing
Tony Alpha now produces a Morning Briefing. The existing Morning Digest agent may duplicate it.
**Agents:** `morning-digest` + Tony Alpha (`daily_status.md`)
**Ask:** Should Morning Digest feed Tony's briefing, or should Tony's briefing replace it? (Per ground rules, do NOT delete the CoWork task — decide on coexistence first.)

### 🔵 OVERLAP-005 — Agent Health Check ↔ Performance Review on Agents
Two meta-agents that watch the other agents — now with Tony Alpha as a third overseer.
**Agents:** `agent-health-check`, `performance-review-agents`
**Ask:** Health Check = "is it running?"; Perf Review = "is it doing good work?" — confirm split. Both should report *into* Tony Alpha rather than each maintaining a separate view.

### 🔵 OVERLAP-006 — Weekly cluster (4 agents)
Four weekly agents run in the same window: Weekly Status Draft, Sunday Weekly Planning, Sunday Evening Recap, Weekly Command Center Reminder.
**Agents:** `weekly-status-draft`, `sunday-weekly-planning`, `sunday-evening-recap`, `weekly-command-center-reminder`
**Ask:** Confirm each has a distinct output. Candidate: let *Weekly Command Center Reminder* trigger Tony Alpha's Weekly Review instead of being a standalone nudge.

---

## Reconciliation status

> ⚠️ **Live CoWork scheduled tasks were NOT accessible from Claude Code (2026-07-08).**
> A read-only reconcile was attempted against the real scheduler and came up empty from this environment:
> - `scheduled-tasks` MCP (`list_scheduled_tasks`) → "No scheduled tasks found"
> - `CronList` (cron jobs) → "No scheduled jobs"
> - Disk (`~/.claude/`, Claude app data) → no readable task/`SKILL.md` definitions; app state is in opaque Electron/IndexedDB stores.
>
> The 22 agents in `agents_registry.json` are catalogued from the owner-provided list, **not** confirmed against the live scheduler. Because of this, `meta.verified_against_scheduler` is `false` and every `source_task_id` is `null`.
>
> **Consequence:** the findings below that depend on live data — *missing*, *duplicate*, and *incorrect-schedule* — cannot be confirmed yet. Only overlap flags (derived from stated purpose) are reliable. See `action_items.md → Manual reconciliation needed`.

## Broken / missing

- 🔴 None confirmed broken. *(Cannot yet verify — all statuses `unknown` until runs are observed.)*
- 🟠 None confirmed missing. *(No known scheduled task is absent from the registry. If a task exists that isn't in the list of 22, add it.)*

---

## Resolved

_(none yet)_

---

## How to log a new issue

```
### <emoji> <TYPE-NNN> — <short title>
<what and why>
**Agents:** `id-a`, `id-b`
**Ask / Action:** <the decision or fix needed>
```
Also add the issue to the affected agent's `issues` array in `agents_registry.json`.
