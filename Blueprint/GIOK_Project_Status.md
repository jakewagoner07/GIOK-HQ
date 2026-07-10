# GIOK — Project Status

*Living status document. Snapshot of where GIOK stands, so any chat can pick up without losing
architecture, priorities, or history. Update this at the end of each sprint.*

Last updated: end of **Sprint D14** (Read-Only Google Calendar Provider).

---

## Snapshot

| | |
|---|---|
| **Product** | GIOK — a desktop life/business operating system for Jake Wagoner (GIOK Agency, Ogden, UT), with **Tony**, an AI Chief of Staff, living inside it. |
| **Current version** | **0.8 Alpha** (`tony-alpha/dashboard/theme/theme.json`) |
| **Current branch** | `feature/dashboard-alpha` |
| **Current PR** | **#1** — https://github.com/jakewagoner07/GIOK-HQ/pull/1 — **open, not merged**, base `main` |
| **Latest commit** | `2a2d42a` — *Build Read-Only Google Calendar Provider* |
| **Remote sync** | local HEAD = remote HEAD (0 ahead / 0 behind) |
| **Platform** | Windows PowerShell 5.1 (STA) + .NET WPF. No Node/Python. Entry point: `tony-alpha/dashboard/dashboard.ps1`. |

---

## Current architecture

Layered, dot-sourced by `dashboard.ps1` in this order: **theme → core (data/logic) → providers →
ui**. UI never holds business logic; core never renders. Single Source of Truth throughout.

**Tony subsystem (the brain and its seams):**

```
Talk with Tony / Command bar / Home
        |
   Tony Brain  (core/tony-brain.ps1)  — orchestrator; the single entry point Invoke-TonyBrain
        |-- Live signals (generic): Get-RelevantLiveSignals -> registered live providers
        |-- Executive Context Engine (core/executive-context.ps1) — assembled ONCE, references sources
        |     folds in: memory, observations, decision-framework judgment, optional live signals
        |-- Decision Framework (core/tony-decision-framework.ps1) — judgment; FINAL authority
        |-- Provider Contract (core/tony-provider-contract.ps1) — model-agnostic request/response
        |-- AI Provider (providers/claude-provider.ps1) — Claude explains, in Tony's voice
        -> Tony makes the final recommendation
```

**Supporting engines (all core/):** Observation Engine (`tony-observations.ps1`), Memory Manager
(`memory-manager.ps1`, the only permanent-memory writer), Executive Briefing
(`executive-briefing.ps1`, Home's centerpiece), Document Intelligence (`document-intelligence.ps1`),
Live-Provider registry (`live-providers.ps1`).

**Two registries, deliberately separate:**
- **AI provider registry** (in `tony-brain.ps1`): who *reasons* for Tony (Claude; auto-select).
- **Live-provider registry** (`live-providers.ps1`): live *information* signals (weather, calendar).
  Providers implement `relevant` / `query` / `status` and register; the Brain consumes them
  generically with no per-provider dependency.

---

## Completed sprints D1–D14

*(Foundation before the Diamond D-series: Capture + Tony Memory, Morning Briefing, Morning
Experience, Identity, End of Day Audit, Project Diamond Blueprint, Sunday Night Usability = v0.8.)*

| Sprint | Deliverable | Commit |
|---|---|---|
| D1 | Tony's First Conversation (onboarding = conversation, not config) | `ac8781a` |
| D2 | Tony Brain Architecture (engines + AI provider seam) | `cef6e3e` |
| D3 | Tony AI Provider Contract (model-agnostic request/response) | `7ce06b5` |
| D4 | Connect Tony to Claude Provider | `1bde844` |
| D5 | Tony Decision Framework (judgment layer, weighted to People First) | `a72a7ee` |
| D6 | Document Intelligence Foundation (read for meaning, approval-gated) | `ab81b02` |
| D7 | Tony Conversation Experience ("Talk with Tony" window, local history) | `8c7eaf3` |
| D7.1 | Bring Tony to Life (live Claude answers; honest, no placeholders) | `6a3b51b` (+`0788735`) |
| D7.2 | Fix Tony Response Pipeline (thinking-block parsing bug) | `0d93e84` |
| D8 | Refine Tony's Executive Personality → broadly capable, grounded | `c6cb265` (+`6edb2b0`) |
| D9 | Tony Observation Engine (notices patterns; celebrate/guide/question) | `dd36311` |
| D10 | Executive Context Engine (single situational awareness) | `969d0f7` |
| D10.1 | Fix remaining UTF-8 rendering bug (native UTF-8 end to end) | `35a317a` |
| D11 | Executive Briefing (the morning letter; Home centerpiece) | `9f14fb3` |
| D12 | Tony Memory With Permission (ask-first; Memory Review) | `aced16c` |
| D13 | Weather Provider (first live provider; Open-Meteo, keyless) | `a354a4b` |
| D14 | Read-Only Google Calendar Provider (OAuth + PKCE, read-only) | `2a2d42a` |

Each sprint has a Blueprint doc; see `Blueprint/00_README.md` for the index.

---

## Current providers

- **Reasoning:** **Claude (Anthropic)** via the AI Provider Contract. Configured with a real key in
  the local `claude.config.json`; model lives only in the provider; `auto` selection. Status +
  diagnostics in Settings → Tony's Reasoning.
- **Live — Weather:** **Open-Meteo** (no key). Location defaults to Ogden, UT (overridable). Live and
  verified. Settings → Live Providers.
- **Live — Google Calendar (read-only):** OAuth 2.0 installed-desktop-app flow (PKCE, loopback,
  offline refresh), scope `calendar.readonly`. Architecture complete and tested; **live connection
  pending Jake's Google Cloud setup** (see below). Settings → Google Calendar.

---

## Current workspaces

**Active:** Home (Executive Briefing centerpiece), End of Day Audit, Capture, Action Items, Identity
(Vision/Goals/Values/Mission/Legacy/Annual Theme/Journal/Timeline), Mission Control (multi-window),
AI Workforce (Agents), Tony (now the **Memory Review**), Settings.
**Special views:** First Conversation (onboarding), Morning Experience.
**Coming soon (dimmed placeholders):** Non-Negotiables, Family, Health, Financial, Agency, Home
Projects, Learning.

---

## Current private / local files (gitignored — never on GitHub)

| File | Purpose |
|---|---|
| `tony-alpha/dashboard/providers/claude.config.json` | Anthropic API key + model |
| `tony-alpha/dashboard/providers/calendar.config.json` | Google OAuth desktop client id/secret |
| `tony-alpha/calendar.tokens.json` | Google access/refresh tokens |
| `tony-alpha/conversation.json` | Talk-with-Tony history |
| `tony-alpha/tony_memory.json` | Approved permanent memories |
| `**/memory-export-*.json` | User memory exports |
| `**/weather.config.json` | Optional per-user location override |
| `tony-alpha/logs/`, `**/tony-diagnostics.log` | Local diagnostics (never contain tokens/keys) |

**Committed safe templates:** `claude.config.example.json`, `calendar.config.example.json` (placeholders only).

---

## Known issues

- **Google Calendar not yet live-connected.** Requires Jake's manual Google Cloud setup (OAuth
  Desktop client + Calendar API + consent). While the OAuth app is in "Testing," Google expires
  refresh tokens after ~7 days — publish to Production for durable personal use.
- **Live-OAuth edge cases unvalidated** (recurring/all-day/DST/multi-calendar) until a real
  connection exists.
- **Some Home data is clearly-labeled sample** (Agency Overview, Appointments, Agent Health cards;
  Life/Business scores) — flagged "SAMPLE," awaiting real integrations.
- **`Founder/Tony_Feedback.md`** is an untracked local note (intentionally left alone).

## Technical debt

- **`core/tony-memory.ps1`** (old structured-memory framework) is superseded by
  `memory-manager.ps1` but still dot-sourced and dormant — safe to retire.
- **Reserved-but-empty fields:** `project` (no projects model yet) and `recentDocument` (no
  document-activity store) in the Executive Context.
- **Overdue detection** is a "open 2+ weeks" proxy because Action Items have no due-date field.
- **No automated test/CI.** Verification is per-sprint manual + headless PNG renders.
- **PS 5.1 constraint:** source must stay ASCII (no-BOM files read as ANSI). Use `[char]0xXXXX`,
  `\uXXXX` regex, and the Edit tool — never raw `WriteAllText` of `.ps1` (once tripped AV, D10.1).

## Current testing status

- **Method:** headless render verification (`dashboard.ps1 -Screenshot out.png -View <name>`) +
  targeted PowerShell harness tests dot-sourcing the modules. No CI.
- **Live-verified:** Claude reasoning (real key, 200s), Weather (Open-Meteo live), full response
  pipeline, native UTF-8 rendering, memory permission flow, observation/decision/context engines.
- **Architecture-verified, live pending:** Google Calendar (routing, disconnected honesty,
  free-time/conflict logic, fixture wiring all pass; live OAuth needs Jake).

## Next recommended sprint

**D15 — Calendar Go-Live + Calendar-Aware Briefing.** Have Jake complete the Google OAuth setup;
validate live edge cases (recurring/all-day/DST/multi-calendar); then let the Executive Briefing
optionally weave in the day's first commitment and free blocks (on demand, not per render). This
cashes in D14 and strengthens the morning experience. (Then **D16 — Gmail read-only provider**, same
pattern.) See `Product_Roadmap.md` for the full ordering and rationale.
