# GIOK — Project Status

*Living status document. Snapshot of where GIOK stands, so any chat can pick up without losing
architecture, priorities, or history. Update this at the end of each sprint.*

Last updated: **Daily Driver — Life Operating System** (on `feature/life-operating-system`, branched
from `main` @ `bda857c`; RC2 already merged to `main`).

> **Life OS milestone status:** the eight life/business workspaces (Goals, Non-Negotiables, Family,
> Health, Financial, Agency, Learning, Home Projects) are now fully usable — Jake enters and manages his
> own data, and Tony consumes it through the one Executive Context. **New owners/stores:** the enriched
> single goal store (`identity/goals.json`, owned by `identity.ps1`) and one new `core/life-os.ps1`
> owning `life_os.json` (gitignored — sensitive Family/Health/Financial data, never committed) for the
> seven non-goal domains. Every domain folds READ-ONLY into `Get-TonyExecutiveContext` (fills the
> reserved `project` slot); the Priority Engine sees active goals; the Briefing gets a calm
> life-awareness line; the provider gets a LIFE CONTEXT block so Tony references Jake's own goals /
> non-negotiables / family / agency. Single Source of Truth preserved (no duplicate goal/task/project/
> memory/priority store); Memory Manager still the only memory writer; Decision Framework still final;
> no automatic actions. Verified: full CRUD + restart persistence + validation + no-dup-storage; all
> workspaces render; Executive-Management (36) and CRM/Randy (59) harnesses still pass. Local-only,
> not pushed.

> **RC2 status (Executive Intelligence Integration):** the five approved pending branches are
> integrated into one release candidate on `release/rc2-executive-intelligence` (branched from
> synchronized `main` @ `2459b66`), merged in dependency order with history preserved: **D18** Executive
> Priority Engine → **D19** Executive Timeline → **D20** Workforce Engine (+ constitution) → **Randy**
> (read-only GoHighLevel CRM) → **Executive Management** (Epic 4). Verified together: the app launches;
> **Emma (Priority) and Riley (Timeline) activate on the merged engines**; **Randy uses the generic
> `crm` signal** (live GoHighLevel connects read-only); the **Executive Manager** delegates across all
> six specialists with progressive delegation, trust scoring, and conflict arbitration; the Decision
> Framework keeps final authority; everything read-only; nothing new stored. No release blockers
> currently identified. **Not merged into `main` and not pushed** (awaiting CTO approval).

---

## Snapshot

| | |
|---|---|
| **Product** | GIOK — a desktop life/business operating system for Jake Wagoner (GIOK Agency, Ogden, UT), with **Tony**, an AI Chief of Staff, living inside it. |
| **Current version** | **0.8 Alpha** (`tony-alpha/dashboard/theme/theme.json`) |
| **Current branch** | `release/rc2-executive-intelligence` (branched from `main` @ `2459b66`; integrates D18/D19/D20/Randy/Executive Management) |
| **Current PR** | Alpha PR #1 and D17 PR #2 **merged to `main`** (`main` @ `2459b66`). RC2 opens a PR when pushed (CTO-approved). |
| **Latest commit** | RC2 integration on the branch, **local-only until Jake approves a push**; `main` unchanged at `2459b66`. |
| **Remote sync** | D18/D19/D20/Randy/Executive-Management each live on their own remote branch; RC2 is local until approved. |
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
| D16 | Gmail Provider — read-only Executive Email Summary on shared OAuth + provider-neutral email intelligence | `8dc0dcc` (+`9cbe816`) |
| RC1 | Alpha Cleanup & Release Review (retired dead `tony-memory.ps1`; fixed `Get-ConversationPath` collision) — merged to `main` | `0530933` (merge `74c0a63`) |
| D17 | Multi-Account Google — one Calendar + one Gmail provider read MANY accounts; per-account tokens; merge/dedupe at the intelligence layer | `593df92` (merge `b1f011d`) |
| D18 | Executive Priority Engine — ranks every real item into Act Now / Do Today / Keep Visible / Low-Value Noise; no-loss; folded into the Executive Briefing | `6dddef5` (RC2) |
| D19 | Executive Timeline — Tony understands time (new/aging/overdue/waiting/expiring) from existing timestamps; folded into the briefing | `50fb539` (RC2) |
| D20 | Workforce Engine — Tony delegates to specialist analysts and merges into one recommendation; constitutional org chart (`Workforce.md`) | `e65e8f8`/`1ac6810` (RC2) |
| Epic 3 | Randy — read-only GoHighLevel CRM (generic `crm` signal, normalized model, live-validated); CRM-agnostic | `5935aea`/`3359351`/`9cbb914` (RC2) |
| Epic 4 | Executive Management — Tony manages the Workforce (progressive delegation, trust scoring, conflict arbitration) | `510670f` (RC2) |

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
- **Live — Google Calendar (read-only), MULTI-ACCOUNT (D17):** OAuth 2.0 installed-desktop-app flow
  (PKCE, loopback, offline refresh) on the shared account-aware `core/google-oauth.ps1`, scope
  `calendar.readonly`. **Live-validated across two real accounts** (business + personal), merged and
  deduped by iCalUID. Settings → Google Calendar (per-account connect/disconnect).
- **Live — Gmail (read-only), MULTI-ACCOUNT (D17):** same shared OAuth, scope `gmail.readonly`.
  Produces one **Executive Email Summary** across all connected accounts via the provider-neutral
  `core/email-intelligence.ps1` (dedupe by Message-ID); registered as the generic `email` signal.
  **Live-validated across two real accounts.** Read-only (never sends/labels/deletes); bodies never
  fetched. Settings → Gmail (per-account connect/disconnect).
- **Live — CRM / GoHighLevel (read-only), MULTI-LOCATION (Epic 3):** HighLevel API v2 authenticated by
  a **Private Integration Token** (static bearer in the gitignored `crm.config.json`). Reads pipelines,
  opportunities, contacts, and opportunity-linked tasks **read-only (HTTP GET only)**, normalizes to the
  vendor-neutral CRM model, and feeds **Randy the CRM Manager** the generic `crm` signal. Lead signals
  derive from opportunities (not raw contacts); policies/renewals/requirements reported **unavailable**
  when GHL doesn't expose them. **Live-validated on Jake's real account.** No CRM mirror.

**Intelligence & management layers (RC2-integrated):** Executive Priority Engine (`executive-priority.ps1`,
D18) and Executive Timeline (`executive-timeline.ps1`, D19) — both folded into the Executive Briefing and
wrapped by the Emma/Riley analysts; the **Workforce Engine** (`workforce-engine.ps1` +
`workforce-specialists.ps1`, D20) with six specialists (Sam, Ava, Emma, Riley, Mason, Randy); and the
**Executive Manager** (`executive-management.ps1`, Epic 4) that manages them. All pure/read-only over the
single Executive Context; Decision Framework keeps final authority.

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
| `tony-alpha/calendar.tokens.json` | Google Calendar **per-account** access/refresh tokens (accounts[]) |
| `tony-alpha/dashboard/providers/gmail.config.json` | Gmail OAuth client id/secret + optional triage lists |
| `tony-alpha/gmail.tokens.json` | Gmail **per-account** access/refresh tokens (accounts[]) |
| `tony-alpha/conversation.json` | Talk-with-Tony history |
| `tony-alpha/tony_memory.json` | Approved permanent memories |
| `tony-alpha/life_os.json` | Life OS domains (non-negotiables, family, health, financial, agency, learning, projects) — private personal data |
| `**/memory-export-*.json` | User memory exports |
| `**/weather.config.json` | Optional per-user location override |
| `tony-alpha/logs/`, `**/tony-diagnostics.log` | Local diagnostics (never contain tokens/keys) |

**Committed safe templates:** `claude.config.example.json`, `calendar.config.example.json`,
`gmail.config.example.json` (placeholders only).

---

## Known issues

- **Calendar and Gmail are live-connected and validated across TWO real accounts** (D15/D16/D17;
  business + personal, merged and deduped).
- **Connecting non-org accounts needs an External consent screen.** An **Internal** OAuth consent
  screen only allows accounts in the Workspace org (`403 org_internal` otherwise). To add a personal
  Gmail, the consent screen was switched to **External (Testing)** with each account added as a
  **test user**. Read-only Gmail is a "sensitive" scope; Production would require Google verification.
- **OAuth "Testing" mode:** Google expires refresh tokens after ~7 days **per account** for Calendar
  and Gmail — publish to Production for durable use.
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
- **Live-verified:** Claude reasoning (real key), Weather (Open-Meteo), **Google Calendar + Gmail
  across TWO real accounts** (D17: both calendars, both inboxes, same-event-on-two-calendars dedup,
  light second account, expired-token resilience on one account while the other worked, disconnect-one
  isolation, and the combined Executive Briefing), single-account migration to the new per-account
  store, full response pipeline, native UTF-8, memory permission flow, observation/decision/context.
- **Read-only re-audited (D17):** only `calendar.readonly` + `gmail.readonly` scopes; every POST hits
  OAuth token/revoke only; data reads are GET — no write scope or write call anywhere.
- **Executive Priority Engine (D18):** ranked Act Now / Do Today / Keep Visible / Low-Value Noise
  verified across empty/busy days, family-vs-business, urgent-email-vs-time-block, cross-source
  dedupe, many-small-items, promotions, and a disconnected provider — fixtures + a live Home render
  ("Act first / Also today / Still visible"). No-loss invariant holds.

**RC2 integration verification (all passing):** every `.ps1` parses; full app launches (Home / Agents /
Tony render); all six specialists available with **Emma and Riley now activating on the merged Priority
& Timeline engines** and Randy on the `crm` signal; the Executive-Management harness (36 checks:
progressive delegation, least-necessary-work, conflict arbitration, low-confidence verification, trust
scoring, evidence reuse / no duplicate calls, Context preserved, Decision Framework seam, no storage /
no actions) and the CRM/Randy harness (59 checks) both pass on the merged tree; **live GoHighLevel
connects read-only** post-merge; the Executive Manager delegated to Emma + Riley end-to-end (no-loss
"kept visible" intact); both engines fold into the Executive Briefing. All integrations read-only.

## Next recommended sprint

**Executive Automation Foundation (local scheduler).** Pre-compose the morning briefing (now
multi-account, priority-ranked, and time-aware) so it is ready the instant GIOK opens — the first
Phase-3 "ahead of you" capability. It has rich signals worth pre-computing: the D18 Executive Priority
Engine and the D19 Executive Timeline (both integrated in RC2). See `Product_Roadmap.md` for the full
ordering.
