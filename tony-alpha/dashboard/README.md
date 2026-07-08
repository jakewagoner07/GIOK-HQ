# Tony Alpha — Desktop Dashboard (Sprint Alpha)

The first working Tony Alpha desktop application. It proves Tony can launch as a real
desktop window that reads the registry and shows the command-center at a glance.

![Dashboard preview](docs/dashboard-preview.png)

---

## How to launch

**Easiest:** double-click **`launch-tony.bat`**.

**Or from a terminal:**
```powershell
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File dashboard.ps1
```

A window titled *Tony Alpha – Command Center* opens, centered, with a live clock.

> Later (Phase 3), `launch-tony.bat` becomes the target of a Windows desktop-icon
> shortcut — no code change needed.

### Requirements
Nothing to install. Uses **Windows PowerShell 5.1** + **.NET WPF**, both built into
Windows 11. (Node.js / Python are **not** required and are not installed on this machine —
which is why WPF was chosen over Electron.)

---

## What it shows
- **Good Morning, Jake** — greeting adapts to time of day (Morning/Afternoon/Evening).
- **Current Date & Time** — live, updates every second.
- **Agent Summary** — total agents, status breakdown, priority breakdown *(LIVE from registry)*.
- **Registry Health** — version, verified-vs-scheduler flag, health-score coverage, source, last updated *(LIVE)*.
- **Open Issues** — flags from the issues log *(PLACEHOLDER this build)*.
- **Action Items** — open + done items *(PLACEHOLDER this build)*.
- **Current Sprint** — the active sprint *(PLACEHOLDER this build)*.

Panels sourced from live data vs. placeholder are labelled in the UI (see the **Data Sources** card).

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
