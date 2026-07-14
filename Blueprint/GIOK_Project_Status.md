# GIOK — Project Status

*Living status document. Snapshot of where GIOK stands, so any chat can pick up without losing
architecture, priorities, or history. Update this at the end of each sprint.*

Last updated: **Epic 10 - Tony Understanding Engine (Onboarding V2)** (on
`feature/tony-understanding-engine`, branched from `main` @ `7738ee4`; Desktop App Identity merged via
PR #17, including its two post-review hardening fixes).

> **Epic 10 status (Tony Understanding Engine / Onboarding V2):** replace raw onboarding storage with a
> reviewable, consent-gated understanding. The 7-question interview is unchanged. **What was wrong:**
> `Complete-Conversation` copied raw answer text straight into Identity the moment the interview ended -
> `Set-IdentityValuesFromText`/`Set-IdentityGoalsFromText`/`Set-IdentityMission` - so (1) a sentence like
> "grow the agency and get healthy" could only split on commas, never into two real goals; (2) Identity
> was mutated before Jake saw anything - no review, no edit, no approval; (3) each write was try/caught
> separately, so a failure on the third left Identity half-written with no rollback. **Now:** the
> interview produces a **temporary Understanding Model** (held in the existing `first_conversation.json`,
> which already owns the original responses - no new store), Jake reviews it in a new **"Here's what I
> understood"** view where every item shows Tony's interpretation, *why* he extracted it, and the user's
> **original words** beside it, each editable; only **"Tony got it right"** writes Identity, in **one
> atomic transaction** (`Invoke-IdentityTransaction`: serialize all, snapshot all, write, restore every
> snapshot on any failure). Extraction is **local + deterministic** so onboarding never needs a key or a
> network (the Claude provider needs a gitignored key and has **no HTTP timeout**, which this epic
> forbids adding - it enriches only when configured, advisory, always falling back). Confidence reuses
> the existing convention (`conversational-capture.ps1:178`): high >=0.7 include; **conflict -> ask one
> question and extract nothing**; low -> omit and record so Tony can ask later. Never invents: **Strengths
> stays empty** unless volunteered, because none of the 7 questions asks about strengths. Destinations
> (no new stores): Goals -> `goals.json` (existing enriched schema, **no provenance fields** - a goal
> record's extra fields are stripped by `ConvertTo-NormalizedGoal` and then persisted stripped by
> `Update-Goal`, so provenance would be silently deleted by the first Life OS edit); Values ->
> `values.json`; Executive Summary -> `overview.json.tonyReflection`; Priorities/Challenges/Strengths/
> Boundaries -> a new `understanding` block **inside** `overview.json`, back-filled on read. Verified
> against redirected temp copies so no real runtime data was touched: one sentence -> 2 goals; raw
> answers never stored verbatim; conflicts produce a clarification not an assumption; hedged statements
> omitted; nothing written before approval; atomic write on approval and **full rollback proven** by
> forcing a mid-transaction failure; resume keeps review edits while a changed answer re-derives the
> model; 9/9 views render; app launches and exits with no orphans. Preserved: providers, agents,
> Workforce, Executive Context, storage layout, the async worker, and the 11 local runtime files.
> Local-only, not pushed.

> **Desktop App Identity status:** make Windows recognize GIOK as its own app instead of PowerShell -
> no app redesign, no business-logic change, no migration off PowerShell/WPF. Root cause: GIOK runs as
> `powershell.exe -File dashboard.ps1` and never set an explicit AppUserModelID, so Windows derived the
> taskbar/Alt+Tab identity from the host process (PowerShell). Fix (smallest safe, no compiled binary):
> (1) set a stable AUMID `GIOK.ExecutiveOS` in-process via a shell32 P/Invoke in `dashboard.ps1` before
> the window is created (interactive path only; best-effort try/catch) + defensive console-hide; (2)
> regenerate `theme/assets/giok.ico` as a proper multi-size icon (16-256px) from the same official
> `giok-logo.png`; (3) new `Install-GiokShortcuts.ps1` creates GIOK Desktop + Start Menu shortcuts on
> the existing silent `launch-tony.vbs` (hidden PowerShell, no console) with the GIOK icon, working
> dir, and a best-effort matching AUMID on the `.lnk`. A compiled launcher `.exe` was assessed and
> rejected (unnecessary + AV-risky). Verified: in-process AUMID sets+reads back as GIOK.ExecutiveOS;
> the app launches via the `.vbs` with a window titled "GIOK" (not PowerShell) and exits with no orphan
> process; two launches run two independent instances; identity block adds ~293 ms (immaterial vs the
> ~2.9s module load); shortcut carries the right target/icon/working dir; `.ico` is a valid 7-size
> icon; Home renders; parse + secret scan + git integrity clean. Antivirus note (honest): C# `Add-Type`
> compilation used for the shortcut-AUMID helper was transiently AV-blocked in testing; the app and
> installer are resilient (the shortcut is still created and the in-process AUMID drives runtime
> identity). **Requires a human on an interactive desktop to visually confirm the taskbar/Alt+Tab/Start
> Menu icons and no console flash.** Preserved: Life OS, Executive Context, Workforce, providers,
> storage, background worker, startup performance, and the 11 local runtime files. Local-only, not
> pushed.

> **Epic 9 status (Performance & Responsiveness):** measure-first optimization; **no new user-facing

> **Epic 9 status (Performance & Responsiveness):** measure-first optimization; **no new user-facing
> features**. A headless profiler (timings + component names only, no private content) proved the entire
> perceived slowness was **live provider latency on the UI thread**, re-fetched by multiple actions -
> Executive Inbox scan ~48s, Communications ~35s (Yahoo IMAP ~20s + Gmail ~10s), Home briefing end-to-end
> ~39s; compute (context 739ms, priority 379ms, most tabs <300ms) was already fine. Fixes: (1) a
> **bounded in-memory signal cache** (`core/executive-cache.ps1`; calendar/communications/CRM; TTLs 2m/2m/
> 5m; single-flight; stale-on-failure; synchronized so a worker and the UI share ONE cache) - caches only
> provider signals, never local data, never a second source; (2) a **background worker runspace**
> (`core/async-run.ps1`) that builds the Home briefing model off the dispatcher and marshals only the card
> build back, torn down on window close (no orphans); (3) a conservative **per-view cache** for
> pure-presentation views only. Measured before -> after: warm signal read ~35,000 -> 22 ms; Inbox scan
> ~48,000 -> 5,888 ms (8x); Home briefing ~39,000 -> 3,892 ms (10x); provider fetches per session 3+ -> 1
> each; cached tab switch 252 -> 5 ms. Home first paint 78 ms warm / ~532 ms cold (first-render JIT floor).
> Verified: off-thread execution, UI-thread marshaling, shared cache, nav responsive during refresh, close
> during refresh, temporary-failure degraded state, no orphan runspaces, no duplicate fetches, view-cache
> safety (editable views rebuild), full app launch, parse, secret scan, git integrity. All invariants
> preserved (SSOT, owners-only writers, Executive Context architecture, approval gate, read-only
> providers). Local-only, not pushed. Remaining bottlenecks: cold-paint JIT (~532ms), Inbox-scan compute
> (~6s, now warm not 48s) still on the UI thread - documented as follow-ons.

> **V1 Completion Tier 1 status (Close the Life OS feedback loop):** the Life OS was writable but

> **V1 Completion Tier 1 status (Close the Life OS feedback loop):** the Life OS was writable but
> **write-only** - Health, Financial, Learning, and broader Family data was invisible to Tony's reasoning,
> the briefing, and conversation. Tier 1 closes the read-back half of the loop with **no new store, tab,
> provider, or agent** - a pure digest over data the **one** Executive Context already loads. (1)
> **Executive Context** - `Get-LifeContextDigest` (pure, in `executive-context.ps1`) folds the loaded Life
> OS domains + active goals into a concise, capped `lifeDigest` (family commitments within 30 days; active
> health/financial/learning goals + items; paused excluded; caps ~4; `source` + `id` preserved; nothing
> fabricated); it writes nothing. (2) **Tony conversation** - the enriched provider **LIFE CONTEXT** block
> lets Tony answer "what health goals am I working on?", "what financial obligations do I have?", "what am
> I trying to learn?", "what family is coming up?" from the digest, with a no-invention / no medical-legal-
> tax-investment-advice guardrail; when a domain is empty he says so plainly and offers to capture it. (3)
> **Executive Briefing** - `Get-BriefingLifeFocus` surfaces at most one or two calm life lines (family
> first), rotated by day-of-year to avoid daily repetition, and **omits the section entirely** when
> nothing is relevant. (4) **Priority/Workforce** - Priority Engine + Decision Framework (Family-before-
> Financial final) already read active goals + non-negotiables and are unchanged; Executive Inbox and
> Conversational Capture untouched. Verified: deterministic digest/prompt/briefing suite all pass; live
> Tony answers all four domain questions honestly (currently no life data set -> "none yet" + capture
> offer, zero fabrication); full app launches and Home renders; secret scan + git integrity clean (4 source
> files changed, no private files). Local-only, not pushed. No release blockers currently identified.

> **Communications Polish Sprint status:** three targeted fixes to the Gmail + Yahoo experience, **no
> architecture change** (one aggregator, one Executive Email Summary, Sam provider-neutral, all mailbox
> access read-only, inbox pending-only). (1) **MIME subject decoding** - a provider-neutral RFC 2047
> decoder (`ConvertFrom-MimeSubject` in `email-intelligence.ps1`) decodes `=?UTF-8?Q?...?=` / `?B?`
> subjects (multi-word, any charset), preserves plain subjects, and fails safely to the original; called
> at each provider's normalization boundary (Gmail + Yahoo), so subjects display normally everywhere.
> (2) **Sam evidence provenance** - each communication proposal's evidence now carries provider, source
> account, sender, subject, and message id, with a concise human tag (e.g. `[Yahoo - jake.wagoner@yahoo.com]
> From Mike: Policy documents needed`); no tokens/passwords/private headers. (3) **Carrier false positive**
> - the OneDrive "memories" notice was matching the `policy` carrier hint via footer boilerplate "Privacy
> Policy"; `Test-EmailCarrier` now strips benign `<privacy|cookie|return|refund|shipping|exchange> policy`
> phrases before matching, so genuine insurance signals ("insurance policy", "policy renewal", "policy
> number", underwriting) are unaffected. Verified live: real Yahoo subjects decode (0 raw `=?...?=`),
> OneDrive no longer carrier, Yahoo unread unchanged (read-only), Sam evidence tagged, idempotent, all
> subsystems + full app launch pass; regression fixtures added. Local-only, not pushed.

> **Epic 8 status (Sam + Yahoo):** Sam is formally **Head of Communications** (she) and provider-neutral —
> she reads **one combined signal** across Business Gmail, Personal Gmail, and **Yahoo Mail** and gives
> Tony one report that still preserves each message's source account + provider. Yahoo joins as a second
> **vendor backend** (new `providers/yahoo-provider.ps1`): a minimal **read-only IMAP** client (pure
> .NET, `imap.mail.yahoo.com:993`, SSL, **Yahoo app password** — confirmed the official method) that
> `EXAMINE`s the inbox and fetches **headers only** via `BODY.PEEK` (never marks seen, no bodies) and
> normalizes to the **same** model as Gmail (`provider='yahoo'`). A new provider-neutral aggregator
> (`core/communications.ps1`) merges backends and runs the **existing** `Get-ExecutiveEmailSummary`
> **once** — no second engine, no second summary — and registers the one `email` live signal (moved off
> the Gmail provider). Daily mode feeds the combined summary; **Historical Search** runs only on explicit
> request (read-only, evidence shown, approval required, never auto-scans). Sam's Epic 6 proposals flow
> unchanged. Credentials in gitignored `yahoo.config.json` (only `yahoo.config.example.json` tracked);
> nothing sensitive logged (states/counts/timing/provider/error-class only). No new tab, no writes.
> Verified: not-configured/auth-failure/empty states, normalization (person/newsletter/bulk/invite),
> combined 3-inbox summary with cross-provider dedup + source preserved, Sam proposals + idempotency,
> historical-search evidence, read-only IMAP audit (no STORE/APPEND/EXPUNGE/DELETE/COPY/MOVE, EXAMINE +
> BODY.PEEK only, no body fetch), one `email` registrant, every subsystem loads, full app launch, secret
> scan + git integrity clean. **Real Yahoo-account read pending Jake's app password** (example config +
> gitignore rule shipped). Local-only, not pushed. No release blockers currently identified.

> **Epic 7 status (Conversational Capture):** Jake can now **tell Tony** something in normal
> conversation and Tony prepares the right **Executive Inbox proposal** — he never writes to the OS.
> New `core/conversational-capture.ps1` is a **pure, provider-agnostic, deterministic** intent engine:
> a gate (only real commitments/goals/reminders/routines/facts pass), weak-language demotion
> ("maybe/someday/eventually" → clarify, never a silent proposal), a type-routing table across all 10
> V1 types (goal, action item, project, non-negotiable, family, health, financial, agency, learning,
> memory), and high/moderate/low confidence bands. High → one proposal + a truthful "I've prepared it
> for your Executive Inbox"; moderate → **one clarifying question, no proposal**; low/casual → nothing.
> `sourceId` = the conversation message id (provenance); de-dup is **content-based** (`type:normalizedTitle`
> vs pending inbox + owner records) so it is idempotent. Hooked into `Send-TonyMessage` (surfaces one
> calm line, suppresses the redundant memory chip when it proposes) with a claude-provider guardrail so
> Tony never claims a direct write. Reuses the existing inbox + routing — **no new store, tab, or
> provider; no schema change.** Verified (fully isolated, zero real data touched): all 10 clear types
> propose correctly, ambiguous asks, casual/weak/question create nothing, duplicate creates no second
> proposal, approve routes to the correct owner, reject/edit-then-approve work, the engine's only write
> is `Add-InboxProposal`, Workforce Activation still adds+dedups, capture and Workforce coexist in one
> inbox, full app launches, secret scan + git integrity clean. Local-only, not pushed. No release
> blockers currently identified.

> **Epic 6 status (Workforce Activation):** the Workforce is **activated** — each specialist now
> **proposes** into the Executive Inbox. New `core/workforce-proposals.ps1` holds per-specialist
> producers (Sam — communications; Ava — calendar; Riley — timeline; Emma — priorities; Randy — CRM;
> Mason — a queued document) and `Invoke-WorkforceProposals`, a deterministic de-dup/quality gate
> (stable `type:sourceId`/`type:normalizedTitle` keys; suppress vs pending inbox **and** vs the
> destination owner's active records; confidence floor + per-scan cap; suppressions logged to
> diagnostics without private content). The scan runs **on demand** (Executive Inbox open + a "Check for
> new proposals" button) — never inside Executive Context or the Briefing (which write nothing), never
> on a timer. Tony gains **read-only** awareness (`Get-InboxSummary` folded into the Executive Context)
> and a calm briefing mention ("The Workforce prepared N items for your review; M are time-sensitive").
> Specialists registered under persona names (Sam — Head of Communications, she; Ava; Mason; Emma;
> Riley; Randy). **Nothing writes to the OS automatically — only Jake's approval writes.** Verified end
> to end against live Gmail + Calendar: Sam/Ava produced real proposals, dedup across scans added zero,
> Emma proposed from real goals, Mason from a queued doc (silent without one), Randy quiet on an empty
> pipeline, briefing + inbox render, no data-file or secret pollution. Local-only, not pushed. No
> release blockers currently identified.
>
> **Epic 5 (Executive Inbox), merged to `main`:** GIOK's **approval center** — a pending-only queue
> (`core/executive-inbox.ps1` → gitignored `executive_inbox.json`) where any Workforce member proposes
> additions and **Jake approves / edits-then-approves / rejects**; Tony presents and **never
> auto-approves**. On approve, the **owning module writes the real record** (`Add-Goal` /
> `Add-LifeItem` / `Add-ActionItem` / `Approve-Memory`) and the proposal leaves the inbox — **no second
> copy**; read-only providers (calendar/CRM) become honest follow-up Action Items, never a fabricated
> write. New Executive Inbox workspace + nav. Verified: propose/approve-routes-to-owner/reject/
> edit-then-approve across every type, no duplicate storage, all workspaces render, secret scan clean.
> Local-only, not pushed. No release blockers currently identified.

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
| `tony-alpha/executive_inbox.json` | Executive Inbox pending proposals — private (can carry sensitive details) |
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
