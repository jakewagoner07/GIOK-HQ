# Tony Alpha — Desktop Dashboard

A local desktop command center that reads the registry and shows everything at a glance.
Branded via a swappable **theme layer** (currently GIOK) — see [THEME.md](THEME.md).
Branding never affects functionality; it's pure presentation on top of the app.

![Dashboard preview](docs/dashboard-preview.png)

---

## How to launch

**Normal use — the "GIOK" desktop icon**, or double-click **`launch-tony.vbs`**.
This is the **silent launcher**: no PowerShell or command-prompt window ever appears —
only the Tony Alpha application window, so it feels like a native Windows app.

**Debug / see output — `launch-tony.bat`.** Same app, but runs in a visible console so
you can read errors. Handy when something isn't working.

**From a terminal:**
```powershell
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File dashboard.ps1
```

A window titled *Tony Alpha – Command Center* opens, centered, with a live clock.

### Launchers at a glance
| File | Console window? | Use |
|------|-----------------|-----|
| `launch-tony.vbs` | none (silent) | everyday launch / desktop icon |
| `launch-tony.bat` | yes (visible) | debugging, seeing errors |

> The desktop "Tony Alpha" icon runs `wscript.exe "launch-tony.vbs"`, which starts
> PowerShell hidden (`-WindowStyle Hidden`, window style 0). If startup ever fails, a
> native error dialog is shown instead of failing silently.

### Requirements
Nothing to install. Uses **Windows PowerShell 5.1** + **.NET WPF**, both built into
Windows 11. (Node.js / Python are **not** required and are not installed on this machine —
which is why WPF was chosen over Electron.)

---

## End of Day Audit (Sprint November)

GIOK's signature evening ritual — the counterpart to the Morning Experience. Honest review,
improvement, and preparation for tomorrow; it answers *"Did today move Jake closer to the life
he is building?"* Accessible from the **sidebar**, **Home** (quick link), and the **command bar**
(`audit`).

- **Scores** — Business, Health, Family, Financial, Learning, Consistency, Relationship (0-10
  steppers); **Overall** is the derived average.
- **Today's Wins** — add/remove wins.
- **Incomplete Items** — live open action items with **Move to tomorrow / Keep open / Archive /
  Delete**.
- **Non-Negotiables** — checkboxes (Workout, Learning, Reading, Family Time, Prospecting, Social
  Posting, Water, Protein, Sleep) + custom (future).
- **Reflection** — Largest Win, Largest Lesson, What Could Have Been Better, What Are You Grateful
  For, One Promise To Tomorrow, Tomorrow's #1 Priority.
- **Tony's Audit** — placeholder coaching summary (AI later).
- **History** — review past audits.

**Storage:** `end_of_day_audit.json`, keyed by date — nothing is overwritten across days. Logic
in `core/end-of-day-audit.ps1`; the UI renders from the model.

![End of Day Audit](docs/end-of-day-audit.png)

## Identity Workspace (Sprint Mike)

**Identity** is the foundation of GIOK — the user's personal operating system. **Vision and Goals
are now sections inside Identity**, not separate workspaces. It expands into nine sections:
Overview, Vision, Goals, Core Values, Mission, Legacy, Annual Theme, Journal, Timeline. The
**Overview** is an executive summary (Identity Score, Vision/Goal Progress, Annual Theme, Core
Values, Latest Journal, Recent Wins, Tony's Reflection).

- **Source of truth:** `identity/*.json` (overview, vision, goals, values, mission, legacy,
  annual_theme, journal, timeline). Identity **owns** this data; other workspaces reference it,
  never duplicate it (`core/identity.ps1`).
- **Sidebar redesign:** an icon sidebar (Home · Identity · Non-Negotiables · Family · Health ·
  Financial · Agency · Home · Learning · AI Workforce · Mission Control · Tony · Settings), with
  placeholder "coming soon" workspaces for the not-yet-built areas.

Blueprint: `Identity.md`, plus the new principle **"Every Workspace Is Self-Contained."**

![Identity](docs/identity.png)

## Morning Experience (Sprint Lima)

GIOK now **opens on the Morning Experience** — the premium "first minute": a calm, centered
welcome that grounds Jake before the dashboard. Built from independent, replaceable components
(each a `New-ME*` function) rendered from a dedicated model in `core/morning-experience.ps1`:
- **Greeting** (personalized) + date
- **Daily Principle** (rotating pill)
- **Morning Thought** — a quote from a **local library** with full attribution (quote, author,
  theme, category, source). No internet retrieval.
- **Why This Today** — Tony's reasoning (placeholder now; future: goals, scores, patterns, audits)
- **Today's Focus** — one sentence (future AI-generated)
- **Today's Priorities** (live) + **Tony Recommendation**
- **Begin My Day** — prominent button that transitions into the Home dashboard.

`Begin My Day` → Home, whose greeting is Tony's Morning Briefing (below).

![Morning Experience](docs/morning-experience.png)

## Morning Briefing (Sprint Kilo)

The Home greeting is replaced by **Tony's Morning Briefing** — his executive briefing that
prepares Jake for the day and answers *"What should Jake focus on today?"* It renders **only**
from a dedicated model in `core/morning-brief.ps1` (no dashboard logic in the UI):
- **Greeting, date, weather** (placeholder), and a "Prepared by Tony" stamp.
- **Daily Principle** — rotates through GIOK principles by date.
- **Today's Priorities** — live from action items (+ open/unprocessed counts).
- **Tony Recommends** — a recommendation-engine placeholder that prioritizes open action items →
  unprocessed captures → open issues → goals (future).
- **Today's Snapshot** — Life Score / Business Score (placeholder) + live Notifications.

The model also carries Open Action Items, Recent Captures, Agent Health, and Upcoming
Appointments for future expansion. Dark executive branding throughout.

![Morning Briefing](docs/dashboard-preview.png)

## Capture & Tony Memory (Sprint Juliet)

**Capture** is GIOK's front door — *your brain is for thinking, not remembering.*
- **`+ Capture Something`** — a prominent button on Home and in the Capture workspace opens a
  dedicated **Capture window**: free text + optional category (12 categories), no required fields.
- **`capture: <text>`** in the command bar drops straight into the Inbox.
- **`capture.json`** is the source of truth (separate from Action Items). Everything lands in the
  **Inbox** first; nothing is auto-deleted.
- **Processing:** Mark Processed, Convert to Action Item (real), Convert to Goal / Reminder
  (placeholder destinations), Archive, Delete, Restore.
- **Home** shows Today's / Unprocessed / Recent captures.

**Tony Memory** — structured memory (not conversation memory). A framework workspace with nine
categories (People, Ideas, Preferences, Business, Family, Goals, Relationships, Lessons,
Patterns) backed by `tony_memory.json`. Framework only for now; Tony populates it over time.

See `Blueprint/Capture.md` and `Blueprint/Tony_Memory.md` for how these evolve through Version 3.

![Capture Inbox](docs/capture-view.png)
![Capture window](docs/capture-window.png)

## Multi-window & Mission Control (Sprint Hotel)

**Open in New Window** — a persistent toolbar (top-right of the body) pops the current view
into its own native window: Agents, Issues, Action Items, Weekly Review, Roadmap,
Recommendations, Agency, Appointments. Each popout is a **live read-only snapshot** — GIOK
branded, titled, rendered from the same source files, with **no shared/duplicated state**
(so a popout never hijacks the main window; edits stay in the main app).

**Mission Control** — a dense, full-screen **second-monitor** overview (sidebar tab, or the
**Open Mission Control** button which opens it in its own window). Eight live panels: Agent
Health, Open Issues, Action Items, Current Sprint, Tony Recommendations, Agency Overview
(sample), Upcoming Appointments (sample), and System Status.

![Mission Control](docs/mission-control.png)

## Dark executive theme + "Ask Tony" command bar (Sprint Golf)

GIOK ships in a **premium dark theme** by default — dark navy background, orange highlights,
light text, rounded cards. It's fully theme-driven: edit `theme/theme.json` (`mode` + `colors`)
to switch palettes, including back to light, without touching code. (Themes carry a `heading`
color so titles render correctly on both dark and light backgrounds.)

The Home screen has a global **"Ask Tony" command bar** (focus with **Ctrl+K**). It runs local
commands — no external AI yet, just the foundation:
- `open agents` / `open issues` / `open action items` / `open weekly review` / `open roadmap` → navigate
- `add task: <text>` → creates a new action item in `action_items.json`

Command parsing lives in `core/command-bar.ps1` (`Invoke-TonyCommand`), separate from the UI.

## Executive home (Sprint Echo)

GIOK opens on **Jake's executive command center**, not a system console. A **left sidebar**
(GIOK logo, Jake's photo, name, "Licensed Insurance Agent", "GIOK Agency", nav, Settings,
version, clock) sits beside a main area that answers *"what does Jake need to know right now?"*

**Home** shows: greeting, the brand line *"People Matter More Than Money."*, **Today's Top 3
Priorities** (live from `action_items.json`), **Agency Overview** (placeholder metrics),
**Tony Recommends** (live signals + sample nudges), **Upcoming Appointments** (placeholder),
**Agent Health** (live from the registry), quick links, and a demoted system-status strip.

Placeholder groups (appointments, agency metrics, some recommendations) are clearly marked
and structured so live integrations can replace them later.

**Every Home card is clickable** (hover highlight, "open >" affordance, hand cursor): Top 3 →
Action Items, Tony Recommends → Recommendations, Agency Overview → Agency, Upcoming
Appointments → Appointments, Agent Health → Agents, and the system strip → Issues. Cards
whose real tab doesn't exist yet open a focused **"Coming soon"** detail view (Agency,
Appointments, Recommendations) with sample data and a back-to-Home button.

### Navigation (left sidebar)
| Tab | Reads from | Shows |
|-----|-----------|-------|
| **Home** | registry + action_items.json + issues_log.md + ROADMAP.md | Executive summary of the day |
| **Agents** | `agents_registry.json` | Every registered agent with all fields |
| **Issues** | `issues_log.md` | The full issues log |
| **Action Items** | `action_items.json` | Interactive task manager |
| **Weekly Review** | `weekly_status.md` | The weekly status |
| **Roadmap** | `ROADMAP.md` | The roadmap |
| **Settings** | theme | Workspace & branding info |

**Agents view** shows, per agent: ID (`AG-###`), name, owner/department, priority, status,
last run, health score, schedule, dependencies, issues, and notes/report.

![Agents view](docs/agents-view.png)

### Action Items — interactive task manager
The Action Items tab is a real, local task manager. **Source of truth: `action_items.json`**
(the app renders from JSON, not raw markdown).
- **Check** an item → marks complete, strikes it through, and saves.
- **+ Add** (or press Enter in the box) → creates a new item (`AI-###` auto-numbered).
- **Delete** → removes an item.
- **Archive completed** → moves all done items to the archive.
- **Active / Archived** toggle → review archived items; **Restore** brings one back.

State is persisted to `action_items.json`; `action_items.md` remains as a human-readable
narrative/log and can be regenerated from JSON later. No external integrations — fully local.

![Action Items](docs/action-items.png)

### What's live vs placeholder
- **Live from files:** Agent Summary, Registry Health, and the Agents view (registry);
  Issues / Action Items / Weekly Review / Roadmap (their `.md` files, read on each navigation).
- **Placeholder:** only *Current Sprint* (no backing file yet).

Every navigation re-reads the source files, so the hub always reflects the latest content —
`agents_registry.json` stays the single source of truth and nothing is duplicated.

---

## Architecture (business logic is separate from the UI)

```
dashboard/
├── core/
│   └── tony-core.ps1     # BUSINESS LOGIC ONLY — reads agents_registry.json,
│                         # computes the model (summary, health, etc.). No UI code.
├── ui/
│   └── tony-ui.ps1       # PRESENTATION ONLY — turns a model into a WPF visual.
│                         # Never reads the registry, never computes anything.
├── dashboard.ps1         # ENTRY POINT — wires core → ui, opens the window
│                         # (or renders a PNG with -Screenshot). No logic, no layout.
├── launch-tony.bat       # double-click launcher
└── docs/
    └── dashboard-preview.png
```

**Data flow:** `agents_registry.json` → `Get-TonyModel` (core) → `New-TonyDashboardVisual` (ui) → window.

**Single source of truth:** the registry JSON is read live at launch. No data is duplicated;
the dashboard is purely a *renderer* of it — consistent with the roadmap principle that a
future web/Android UI is just another renderer of the same JSON.

**Why the layers are split:** the model object (`Get-TonyModel`) is the contract. Swap the WPF
UI for a web front end later and the core is reused unchanged; change the registry schema and
only the core adapts. Neither layer reaches into the other.

### Render a screenshot (headless)
```powershell
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File dashboard.ps1 -Screenshot out.png
# optional: -Now "2026-07-08 08:15" to force the greeting/clock, -Width / -Height to size
```
This uses the *same* UI builder as the live window, rendered to PNG via WPF `RenderTargetBitmap`.

---

## Not in this build (by design)
- ❌ Gmail / Calendar / any API connection
- ❌ Live wiring of Open Issues / Action Items / Sprint (still placeholder)
- ❌ Writing back to the registry (read-only)

Goal of Sprint Alpha was strictly: **prove Tony launches as a real desktop app.** Done.
