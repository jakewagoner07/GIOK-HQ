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

## Hub navigation (Sprint Charlie)

Tony Alpha is now a **command hub**, not a single screen. A persistent top bar (brand +
live clock) and a nav bar sit above a swappable body. Six views:

| Tab | Reads from | Shows |
|-----|-----------|-------|
| **Dashboard** | agents_registry.json (+ the .md files, for summaries) | Greeting, clock, clickable summary cards |
| **Agents** | `agents_registry.json` | Every registered agent with all fields |
| **Issues** | `issues_log.md` | The full issues log |
| **Action Items** | `action_items.md` | The full action-items list |
| **Weekly Review** | `weekly_status.md` | The weekly status |
| **Roadmap** | `ROADMAP.md` | The roadmap |

**Clickable cards:** on the Dashboard, the summary cards are clickable — *Agents* opens the
Agents view, *Open Issues* → Issues, *Action Items* → Action Items, *Current Sprint* →
Weekly Review, plus quick links to Weekly Review / Roadmap.

**Agents view** shows, per agent: ID (`AG-###`), name, owner/department, priority, status,
last run, health score, schedule, dependencies, issues, and notes/report.

![Agents view](docs/agents-view.png)

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
