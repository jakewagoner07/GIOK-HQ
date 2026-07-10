# GIOK — Project Status

*Living status document. Snapshot of where GIOK stands, so any chat can pick up without losing
architecture, priorities, or history. Update this at the end of each sprint.*

Last updated: **RC1** (Alpha Cleanup and Release Review), after Sprint D16 (Gmail Provider).

---

## Snapshot

| | |
|---|---|
| **Product** | GIOK — a desktop life/business operating system for Jake Wagoner (GIOK Agency, Ogden, UT), with **Tony**, an AI Chief of Staff, living inside it. |
| **Current version** | **0.8 Alpha** (`tony-alpha/dashboard/theme/theme.json`) |
| **Current branch** | `feature/dashboard-alpha` |
| **Current PR** | **#1** — https://github.com/jakewagoner07/GIOK-HQ/pull/1 — **open, not merged**, base `main` |
| **Latest commit** | `9cbe816` pushed (*D16 Gmail live-data fixes*); **RC1 cleanup committed on top, unpushed** (this checkpoint) |
| **Remote sync** | D14/D15/D16 pushed; **RC1 local-only until Jake approves a push** |
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
- **Live-provider registry** (`live-providers.ps1`): live *information* signals (weather, calendar,
  email). Providers implement `relevant` / `query` / `status` and register; the Brain consumes them
  generically with no per-provider dependency.

**Shared provider building blocks (added D16, Single Source of Truth):**
- **`core/google-oauth.ps1`** — one installed-desktop-app OAuth mechanism (PKCE + loopback + offline
  refresh + revoke + UTF-8 REST GET), parameterized per provider. Gmail uses it now; Calendar
  migrates onto it next (low-risk follow-up).
- **`core/email-intelligence.ps1`** — provider-neutral Executive Email Intelligence (classification +
  summary). Gmail feeds it today; Outlook / Microsoft 365 / Yahoo feed the same engine later by
  normalizing to a shared message shape and registering as the generic **`email`** signal.

---

## Completed sprints D1–D16

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
| D15 | Calendar Intelligence (first/last/total, free blocks, meeting-heavy days) fed into the Executive Briefing | `7c73e10` (+`722dce4`) |
| D16 | Gmail Provider — read-only Executive Email Summary on shared OAuth + provider-neutral email intelligence | (this checkpoint) |

Each sprint has a Blueprint doc; see `Blueprint/00_README.md` for the index.

**D15 note (now LIVE):** Calendar is connected to Jake's real Google account and validated live
(today's events, all-day, recurring, meeting-heavy insights, calendar-aware briefing). A real bug
found only against live data — `freeWindows` scalar `+` on single-window days — was fixed (`722dce4`).

**D16 note (honest status):** the Gmail backend (OAuth, read-only fetch, normalization),
provider-neutral Email Intelligence (classification + Executive Email Summary), and the
email-aware Executive Briefing are built and **verified with fixtures + a stubbed-connected Home
render** (the "Today's Email" section renders correctly). The **live Gmail connection is pending
Jake's step**: enable the Gmail API on the existing Google Cloud project, add a Desktop-app client to
`gmail.config.json`, then Settings -> Gmail -> Connect (see `Gmail_Provider.md`).

---

## Current providers

- **Reasoning:** **Claude (Anthropic)** via the AI Provider Contract. Configured with a real key in
  the local `claude.config.json`; model lives only in the provider; `auto` selection. Status +
  diagnostics in Settings → Tony's Reasoning.
- **Live — Weather:** **Open-Meteo** (no key). Location defaults to Ogden, UT (overridable). Live and
  verified. Settings → Live Providers.
- **Live — Google Calendar (read-only):** OAuth 2.0 installed-desktop-app flow (PKCE, loopback,
  offline refresh), scope `calendar.readonly`. **Live and validated** against Jake's real account.
  Settings → Google Calendar.
- **Live — Gmail (read-only):** same installed-desktop-app OAuth (now on the shared
  `core/google-oauth.ps1`), scope `gmail.readonly`. Produces an **Executive Email Summary** via the
  provider-neutral `core/email-intelligence.ps1`; registered as the generic `email` signal. Read-only
  (never sends/labels/deletes); message bodies never fetched. Architecture complete and
  fixture-tested; **live connection pending Jake's Gmail-API enable + Connect** (see
  `Gmail_Provider.md`). Settings → Gmail.

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
| `tony-alpha/calendar.tokens.json` | Google Calendar access/refresh tokens |
| `tony-alpha/dashboard/providers/gmail.config.json` | Gmail OAuth client id/secret + optional triage lists |
| `tony-alpha/gmail.tokens.json` | Gmail access/refresh tokens |
| `tony-alpha/conversation.json` | Talk-with-Tony history |
| `tony-alpha/tony_memory.json` | Approved permanent memories |
| `**/memory-export-*.json` | User memory exports |
| `**/weather.config.json` | Optional per-user location override |
| `tony-alpha/logs/`, `**/tony-diagnostics.log` | Local diagnostics (never contain tokens/keys) |

**Committed safe templates:** `claude.config.example.json`, `calendar.config.example.json`,
`gmail.config.example.json` (placeholders only).

---

## Known issues

- **Google Calendar is live-connected and validated.** (Was the prior known issue; resolved D15.)
- **Gmail not yet live-connected.** Requires Jake enabling the Gmail API on the existing Google Cloud
  project + a Desktop-app client in `gmail.config.json` + Connect. Fixture-verified; live triage
  accuracy (needs-reply / carrier / invitations) confirmed only once connected.
- **OAuth "Testing" mode:** while the consent screen is in Testing, Google expires refresh tokens
  after ~7 days for BOTH Calendar and Gmail — publish to Production for durable personal use.
- **Email triage is heuristic + user-curated.** "Client"/"important contact" detection is honest only
  to the extent Jake fills `importantContacts`/`clientDomains` in `gmail.config.json`; otherwise Tony
  says "a person is waiting" rather than guessing a relationship.
- **Some Home data is clearly-labeled sample** (Agency Overview, Appointments, Agent Health cards;
  Life/Business scores) — flagged "SAMPLE," awaiting real integrations.
- **`Founder/Tony_Feedback.md`** is an untracked local note (intentionally left alone).
- **Bitdefender may repeatedly lock or quarantine `tony-alpha/dashboard/core/document-intelligence.ps1`,**
  interfering with git operations (checkout/pull can leave the file un-removable or the tree
  partially updated). Workaround: add an explicit **file-level Bitdefender exception** for that file
  (folder-level exclusion alone has not been sufficient).

## Technical debt

- **`core/tony-memory.ps1`** (old structured-memory framework) — **retired at RC1** (deleted; its
  functions were never called and it declared a conflicting schema on `tony_memory.json`, which
  `memory-manager.ps1` owns).
- **`Get-ConversationPath` name collision** — **fixed at RC1**: `first-conversation.ps1` now uses
  `Get-FirstConversationPath` so onboarding state stays in `first_conversation.json` and can never
  be routed into (or clobber) the Talk-with-Tony `conversation.json`.
- **Reserved-but-empty fields:** `project` (no projects model yet) and `recentDocument` (no
  document-activity store) in the Executive Context.
- **Overdue detection** is a "open 2+ weeks" proxy because Action Items have no due-date field.
- **No automated test/CI.** Verification is per-sprint manual + headless PNG renders.
- **PS 5.1 constraint:** source must stay ASCII (no-BOM files read as ANSI). Use `[char]0xXXXX`,
  `\uXXXX` regex, and the Edit tool — never raw `WriteAllText` of `.ps1` (once tripped AV, D10.1).

## Current testing status

- **Method:** headless render verification (`dashboard.ps1 -Screenshot out.png -View <name>`) +
  targeted PowerShell harness tests dot-sourcing the modules. No CI.
- **Live-verified:** Claude reasoning (real key, 200s), Weather (Open-Meteo live), **Google Calendar
  (real account: today/all-day/recurring/insights/briefing)**, full response pipeline, native UTF-8
  rendering, memory permission flow, observation/decision/context engines.
- **Architecture-verified, live pending:** Gmail (classification + Executive Email Summary fixtures,
  raw->normalized parse, routing, disconnected honesty, and a stubbed-connected Home render all pass;
  live OAuth needs Jake to enable the Gmail API + Connect).

## Next recommended sprint

**Gmail go-live (Jake) → then D17 — Executive Automation Foundation (local scheduler).** First, Jake
enables the Gmail API and connects (Settings -> Gmail), so the D16 Executive Email Summary runs on
real mail. Then **D17** pre-composes the morning briefing (now Calendar- and Gmail-aware) so it is
ready the instant GIOK opens — the first Phase-3 "ahead of you" capability. A small, low-risk
follow-up also migrates the Calendar provider onto the shared `core/google-oauth.ps1`. See
`Product_Roadmap.md` for the full ordering and rationale.
