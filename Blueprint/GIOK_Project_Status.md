# GIOK — Project Status

*Living status document. Snapshot of where GIOK stands, so any chat can pick up without losing
architecture, priorities, or history. Update this at the end of each sprint.*

Last updated: end of **Sprint D20** (Workforce Engine), branched from `main` after D17 + the D18
deferral note (D18 and D19 remain on their own branches, unmerged).

> **D18 status:** D18 – Executive Priority Engine is feature complete and pushed to
> `feature/executive-priority-engine`. Merge is intentionally deferred pending 3–5 days of founder
> validation during normal daily use. No release blockers currently identified.
>
> **D19 status:** D19 – Executive Timeline is feature complete on `feature/executive-timeline`. No
> release blockers currently identified.
>
> **D20 status:** D20 – Workforce Engine is feature complete on `feature/workforce-engine` (branched
> from `main`, independent of D18/D19). The Priority and Timeline analysts activate automatically once
> those engines merge. The permanent org chart and bylaws are formalized in the constitutional
> `Blueprint/Workforce.md` (Tony, Sam, Ava, Emma, Riley, Mason + future hires; Executive Awareness
> Principle; Rule of Progressive Delegation). No release blockers currently identified.
>
> **Epic 3 status (Business Intelligence / CRM):** **Randy — CRM Manager** is hired as a permanent,
> constitutional Workforce member on `feature/randy-crm-manager` (branched on top of the D20 Workforce
> foundation, so it inherits the constitution). Randy understands **CRM as a discipline, not
> GoHighLevel** — future CRMs (HubSpot, Salesforce, Zoho, Pipedrive, custom) are provider backends, not
> a Randy redesign. Phase 1 (Randy's charter, `Blueprint/Randy_CRM_Manager.md`) and Phase 2 (CRM
> provider architecture, `Blueprint/CRM_Provider.md`) are documentation. **Phase 3 (read-only
> GoHighLevel CRM provider) is now BUILT:** `providers/gohighlevel-provider.ps1` (vendor backend +
> normalizer, HighLevel API v2, read-only, HTTP-GET-only), `core/crm-intelligence.ps1` (provider-neutral
> book-of-business intelligence), and **Randy** registered in `core/workforce-specialists.ps1`. Verified
> with a 48-check mocked harness (disconnected, auth-fail, empty, multi-location, one-location-fails,
> leads/opps/stages, aging/stalled, overdue follow-ups, duplicates, Randy's standard report, Tony
> delegation, GET-only/no-write, no-mirror) + a clean full-app Home render. **Live validation is pending
> Jake connecting a HighLevel Private Integration token** in `crm.config.json` (cannot be fabricated in a
> build environment). No release blockers currently identified.

---

## Snapshot

| | |
|---|---|
| **Product** | GIOK — a desktop life/business operating system for Jake Wagoner (GIOK Agency, Ogden, UT), with **Tony**, an AI Chief of Staff, living inside it. |
| **Current version** | **0.8 Alpha** (`tony-alpha/dashboard/theme/theme.json`) |
| **Current branch** | `feature/multi-google-accounts` (branched from `main` @ `cc17879`) |
| **Current PR** | Alpha **PR #1 merged to `main`** (`74c0a63`). D17 will open a new PR when pushed. |
| **Latest commit** | `main` @ `cc17879` (pushed); **D17 multi-account committed on the feature branch, unpushed** (this checkpoint) |
| **Remote sync** | Alpha is live on `main`; **D17 local-only until Jake approves a push** |
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
Live-Provider registry (`live-providers.ps1`), and the **Workforce Engine** (`workforce-engine.ps1` +
`workforce-specialists.ps1`, D20) — a specialist registry Tony delegates to and merges, staying the
only executive decision maker.

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
| D18 | Executive Priority Engine — Act Now / Do Today / Keep Visible / Low-Value Noise; no-loss | `6dddef5` (branch; **merge deferred for founder validation**) |
| D19 | Executive Timeline — Tony understands time (new/aging/overdue/waiting/expiring) from existing timestamps | `50fb539` (branch, unmerged) |
| D20 | Workforce Engine — management layer; delegate to specialist analysts, merge reports, one recommendation; Tony stays the only decision maker | (this checkpoint) |

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
- **Live — CRM / GoHighLevel (read-only), MULTI-LOCATION (Epic 3 Phase 3):** HighLevel API v2
  (`services.leadconnectorhq.com`, `Version: 2021-07-28`), authenticated by a **Private Integration
  Token** (static bearer in the gitignored `crm.config.json`). Reads pipelines, opportunities,
  contacts, and opportunity-linked tasks **read-only (HTTP GET only)** across one or more locations,
  normalizes them to the vendor-neutral CRM model, and feeds **Randy the CRM Manager** the generic
  `crm` signal. Policies/renewals/requirements are honestly reported **unavailable** (not native to
  GHL); underwriting is derived from real pipeline-stage identity. No CRM mirror — fetched on demand.
  **Live validation pending Jake's HighLevel token.**

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
| `tony-alpha/dashboard/providers/crm.config.json` | HighLevel Private Integration Token + location id(s) + CRM tuning (read-only) |
| `tony-alpha/conversation.json` | Talk-with-Tony history |
| `tony-alpha/tony_memory.json` | Approved permanent memories |
| `**/memory-export-*.json` | User memory exports |
| `**/weather.config.json` | Optional per-user location override |
| `tony-alpha/logs/`, `**/tony-diagnostics.log` | Local diagnostics (never contain tokens/keys) |

**Committed safe templates:** `claude.config.example.json`, `calendar.config.example.json`,
`gmail.config.example.json`, `crm.config.example.json` (placeholders only).

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

## Next recommended sprint

**Merge validation (D18/D19/D20) → then Executive Automation Foundation (local scheduler).** Several
capabilities now sit on unmerged branches awaiting founder validation (D18 Priority, D19 Timeline,
D20 Workforce). Once merged, the local scheduler can pre-compose a multi-account, priority-ranked,
time-aware, workforce-backed morning briefing. See `Product_Roadmap.md` for the full ordering.

**Testing note (D20 Workforce Engine):** verified — 5 specialists register with the standard
interface; relevance + delegation; standard report shape; merge into one recommendation with
evidence + reasoning (transparency); quality control rejects poor reports; conflicting opinions
flagged (`showRawToJake`); low-confidence → `needsVerification`; Priority/Timeline analysts degrade
honestly without their engines and light up with them; ordinary questions bypass the workforce; the
Executive Briefing is unchanged; a live "What happened overnight?" produced a merged, transparent
answer; conversation, memory, Document Intelligence, Calendar, and Gmail all still pass; full app
launch clean.
