# 04 — Home (Executive Dashboard)

The Home dashboard exists to answer **one question**: *"What should Jake focus on today?"*

Everything on Home earns its place by helping answer that question in under ten seconds. If a
component doesn't help Jake decide what to do next, it belongs deeper in a workspace, not on
Home. Home is the executive cockpit — calm, prioritized, glanceable, and personal.

## Design intent
- **One screen, one glance.** Jake should feel oriented immediately: the day, the top few things,
  what Tony thinks, and where the business/life stands.
- **Priorities over lists.** Home shows the *vital few*, not the complete many. Full lists live
  in their workspaces.
- **Human first.** People-related items (a client's Checkup, a family promise) get visual
  priority over vanity numbers — "People Matter More Than Money" on the screen itself.
- **Capture always present.** Quick Capture is one keystroke away from anywhere, so a thought is
  never lost between screens.

## Components

### Morning Brief
Tony's short narrative of the day: what happened overnight, what's due, what changed, and the one
thing to not miss. Warm, concise, human. This is the first thing Jake reads.

### Today's Priorities
The top 3–5 things that actually matter today, drawn live from action items and the Checkup
pipeline, ordered by impact — not by whatever is loudest. Each links to its detail.

### Tony Recommends
Tony's proactive suggestions, each tagged by why (live signal vs. coaching nudge): overdue
Checkups, a referral to ask for, a non-negotiable at risk, an agent that needs attention.

### Agency Overview
The business pulse: active clients, policies in force, Checkups this month, referrals — enough to
feel the state of the book without opening the Agency workspace.

### Upcoming Appointments
The day's meetings and Checkups, in time order, with who and why — so Jake walks in prepared.

### Notifications
Time-sensitive things that need awareness now: a client reply, an agent failure, a bill due, an
alert from Mission Control. Distinct from recommendations — these are *events*, not advice.

### Quick Capture
An always-available input to dump a thought instantly (text now; voice/photo/share later).
Capture first, organize later — Tony routes it (see [05_Capture_System.md](05_Capture_System.md)).

### Recent Wins
A short list of things recently completed or achieved — closed a client, hit a streak, finished a
project. Wins fuel consistency; GIOK makes progress visible, not just the backlog.

### Goals Progress
A compact view of movement toward the active goals — the line from today's work to the year's
intentions.

### Life Score
The overall wellbeing score and its trend (see [07_Life_Score.md](07_Life_Score.md)) — a single
honest number for "how is life going," with a tap-through to categories.

### Business Score
The counterpart for the agency: a single honest number for business momentum (pipeline health,
Checkup completion, referral flow), with its trend.

### Quick Actions
One-click starts for the highest-frequency moves: add task, start a Checkup, log a win, open
Mission Control, ask Tony.

## Layout priority (top to bottom, importance-ordered)
1. **Greeting + brand line** ("Good Morning, Jake" · *People Matter More Than Money*) + Quick
   Capture / Ask Tony.
2. **Morning Brief** and **Today's Priorities** — the core of the answer.
3. **Tony Recommends** and **Notifications** — advice and events.
4. **Agency Overview**, **Upcoming Appointments**, **Business Score** — the business band.
5. **Life Score**, **Goals Progress**, **Recent Wins** — the life band.
6. **Quick Actions** — fast moves.
7. **System status** — demoted to a quiet footer; developers' data never dominates Jake's day.

## Rules for Home
- Nothing on Home is un-actionable. Every card either tells Jake something to *do* or *know* today.
- Placeholders are clearly marked until live data replaces them — never faked as real.
- Cards are entry points: clicking a Home card opens the fuller view (already true today).
- When Home gets crowded, the fix is *prioritize and demote*, never *add another column*.

Home is the daily contract between Jake and GIOK: open it, and know exactly what today is for.
