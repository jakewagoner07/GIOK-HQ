# 08 — Mission Control

Mission Control is GIOK's **situation room** — the dense, glanceable, full-screen overview of the
entire operation. It lives **inside GIOK** (a first-class workspace) and can also **open in its
own window** for a dedicated second monitor. Its job is to let Jake *feel the state of everything*
without clicking through tabs.

A first working version already exists (eight live panels, openable in a separate window). This
document defines what it becomes.

## Purpose
- **Ambient awareness.** Left open on a second screen, Mission Control keeps the whole
  operation — business, agents, health, alerts — in Jake's peripheral vision all day.
- **Situation, not editing.** Mission Control shows and links out; it is read-mostly. Deep work
  happens in the workspaces it points to.
- **One honest surface.** Every widget reads live from the single source of truth. No stale
  copies, no faked numbers.

## Layout
- **Grid of live widgets**, sized for full-screen density — designed to be readable from across a
  desk.
- **Priority reading order:** what needs a human now (alerts, priorities) at top-left; steady-state
  metrics (business, health, agents) filling the grid; system status quietly at the edge.
- **Dark executive styling** (navy/orange), consistent with GIOK branding, tuned for long-running
  display without eye strain.
- **Second-monitor mode:** a dedicated window with its own branded header, independent of the main
  app, so Jake can drag it to another screen and leave it running.

## Live widgets
- **Agent Health** — fleet status, who's healthy/warning/broken, coverage.
- **Open Issues** — flagged overlaps, duplicates, and problems needing attention.
- **Today's Priorities / Action Items** — the vital few, live.
- **Current Sprint / Focus** — what the operation is building now (from the roadmap).
- **Tony Recommendations** — proactive suggestions, ranked.
- **Business Metrics** — pipeline, Checkups, referrals, revenue pulse.
- **Health** — the wellbeing band (later fed by wearables).
- **System Status** — registry version, verification state, data freshness, "as of" time.

## Alerts
- Mission Control is where **time-sensitive events** announce themselves: an agent failed, a
  client replied, a Checkup is overdue, a non-negotiable is at risk, a metric crossed a
  threshold.
- Alerts are **ranked by consequence** and **honest** — a real problem is shown as a real problem,
  never softened into invisibility.
- Alerts link straight to the place to act.

## Tony Recommendations
Tony's recommendations get a permanent home here, so the situation room isn't just *data* but
*advice*: the next best move, with its reason, always in view.

## AI Workforce
A live view of the agent fleet as a *workforce*: what each agent is for, whether it ran, whether
it's healthy, and what it produced — the registry made visible and monitored. Mission Control is
where Jake sees his automated staff at a glance.

## Business Metrics
The agency's vital signs — enough to know, without opening the Agency workspace, whether the
business is moving: active clients, Checkups completed this month, referral flow, pipeline health.

## Health
The wellbeing counterpart to business — so the second monitor never lets health go invisible
while the business is watched. People (and the person) first, on the very surface built for
watching numbers.

## Future live integrations
Every widget is built to swap its placeholder for a live feed with no redesign:
- **CRM (GoHighLevel):** pipeline, client activity, SMS/lead events → priorities and alerts.
- **Calendar:** the day's real appointments and Checkups.
- **Email:** actionable messages surfaced as alerts.
- **Wearables:** live health metrics.
- **Finances:** budget/cash signals (read-only).
- **Agent runtimes:** real per-agent run status and output.

Mission Control's promise: at any moment, one glance tells Jake whether the operation — business
*and* life — is on track, and if not, exactly where to look.
