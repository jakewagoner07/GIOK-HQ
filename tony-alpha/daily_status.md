# Daily Status — Tony Alpha

> Refresh this at the start of each day. Pull facts from `agents_registry.json`.

---

## ☀️ Morning Briefing — 2026-07-08 (Wednesday)

**Good morning. Here's where the fleet stands.**

- **22 agents** are registered and under watch.
- **Status:** all 22 are currently `unknown` — Tony Alpha is in Phase 1 (command center only) and cannot yet observe real runs. This is expected, not an alarm.
- **Nothing is confirmed broken.** But nothing is confirmed healthy either — that gap is the #1 thing to close.
- **6 overlap flags** are open for review (see `issues_log.md`). None are urgent; all are "clarify intent" not "fix now."

**What matters today**
1. Confirm real schedules + last-run times for the daily-critical agents (GHL SMS Monitor, Email Triage, Morning Digest, Upwork Message Check) so their status can move off `unknown`.
2. Decide how the existing **Morning Digest** agent relates to this Morning Briefing — feed-in or replace. (Action item AI-004.)
3. Skim the 6 overlap flags; confirm or dismiss each.

**Today's expected agents** *(fill in once schedules are known)*
- _Daily agents pending schedule confirmation._

**Needs your decision**
- See `action_items.md` → items AI-001 through AI-006.

---

## Watch list (anything not `healthy`)

| Agent | Status | Last run | Issue |
|-------|--------|----------|-------|
| _All 22_ | `unknown` | — | Awaiting first observed run / manual status. |

*(As statuses are set, only warning/broken/unknown agents need to stay listed here.)*

---

## Template for future days

```
## ☀️ Morning Briefing — YYYY-MM-DD (Day)
- Fleet: X agents | healthy A · warning B · broken C · unknown D
- Overnight: <what ran, what didn't>
- What matters today: <top 3>
- Needs your decision: <items>

## Watch list
| Agent | Status | Last run | Issue |
```
