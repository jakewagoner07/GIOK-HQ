# GIOK — Product Roadmap (Phased)

*The prioritized build plan, organized by phase. Complements the version-oriented
`09_Product_Roadmap.md`; this one tracks the four capability phases and the near-term sprint queue.
Update the checkboxes and the "next five" each sprint.*

Legend: ✅ done · 🔄 in progress · ⬜ not started

---

## Phase 1 — Tony Core  *(the mind)*  — ✅ essentially complete

Give Tony judgment, voice, memory, and situational awareness — entirely local, no integrations.

- ✅ First Conversation onboarding (D1)
- ✅ Tony Brain + engine architecture (D2)
- ✅ Model-agnostic AI Provider Contract (D3)
- ✅ Claude provider connected, honest, live (D4, D7.1, D7.2)
- ✅ Decision Framework — judgment, Family before Financial, final authority (D5)
- ✅ Conversation experience — Talk with Tony, persistent local history (D7)
- ✅ Executive personality — broadly capable, purposefully grounded (D8)
- ✅ Observation Engine — notices patterns; celebrate/guide/question (D9)
- ✅ Executive Context Engine — single situational awareness (D10)
- ✅ Executive Briefing — the morning letter, Home centerpiece (D11)
- ✅ Memory With Permission — ask-first, Memory Review, user control (D12)
- ✅ Document Intelligence foundation — read for meaning, approval-gated (D6)
- ✅ Native UTF-8 + response-pipeline correctness (D7.2, D10.1)
- ✅ Executive Priority Engine — Act Now / Do Today / Keep Visible / Low-Value Noise; no-loss
  awareness; Decision Framework as final authority; folded into the briefing (D18)
- ✅ Executive Timeline — Tony understands time (new/aging/overdue/waiting/expiring) from existing
  timestamps only; no new storage; folded into the briefing (D19)
- ✅ Workforce Engine — Tony delegates to specialist analysts and merges into one recommendation; the
  only executive decision maker; framework for all future specialists (D20). Org chart + bylaws in the
  constitutional `Blueprint/Workforce.md` (Tony, Sam, Ava, Emma, Riley, Mason, Randy; Executive
  Awareness Principle; Rule of Progressive Delegation).
- ✅ Executive Management — Tony promoted from delegator to **Executive Manager**: decides who
  works/verifies/is skipped and when the evidence is enough; progressive delegation, deterministic
  trust scoring, conflict arbitration; pure module on top of D20 (Epic 4).
- ✅ **RC2 — Executive Intelligence Integration** — D18, D19, D20, Randy, and Executive Management
  merged into one release candidate; Emma and Riley activate on the merged engines; Randy uses the
  generic `crm` signal; all read-only, Decision Framework still final.

- ✅ **Daily Driver — Life Operating System** — the eight life/business workspaces (Goals,
  Non-Negotiables, Family, Health, Financial, Agency, Learning, Home Projects) are fully usable: Jake
  manages his own data; Tony consumes it through the one Executive Context. One goal store (enriched),
  one `life_os.json` (gitignored), the reserved `project` slot filled. See
  `Blueprint/Life_Operating_System.md`.
- ✅ **Executive Inbox (Epic 5)** — GIOK's approval center: the Workforce proposes additions, Jake
  approves/edits/rejects, and approvals route to the owning modules (no second copies). Tony never
  auto-approves. Pending-only `executive_inbox.json` (gitignored). See `Blueprint/Executive_Inbox.md`.
- ✅ **Workforce Activation (Epic 6)** — the Workforce starts proposing: per-specialist producers
  (`core/workforce-proposals.ps1`) turn evidence-backed findings into Executive Inbox proposals through
  a deterministic de-dup/quality gate (stable keys; suppress vs pending + owner records; confidence
  floor + caps). On-demand scan (inbox open + button); Tony gains read-only awareness + a calm briefing
  mention. Only Jake's approval ever writes. See `Blueprint/Workforce_Activation.md`.
- ✅ **Conversational Capture (Epic 7)** — Jake tells Tony in normal conversation ("I want to lose 20
  pounds") and a pure deterministic intent engine (`core/conversational-capture.ps1`) prepares the right
  Executive Inbox proposal (`discoveredBy=Tony`, `sourceId`=message id). Gate + weak-language demotion +
  type routing across all 10 V1 types; high→propose, moderate→one clarifying question, low→nothing;
  content-based idempotent dedup. Tony never writes directly; reuses the existing inbox + routing (no new
  store/tab/provider). See `Blueprint/Conversational_Capture.md`.
- ✅ **V1 Completion Tier 1 - Close the Life OS feedback loop** - the Life OS was write-only; Health,
  Financial, Learning, and broader Family data was invisible to Tony. A pure `Get-LifeContextDigest` over
  data the one Executive Context already loads gives Tony a concise, capped, source-tagged `lifeDigest`; he
  now answers domain questions ("what health goals am I working on?", "what family is coming up?") from it
  and the briefing surfaces one calm, selective life line (family first, omitted when nothing matters).
  Read-only, no invention, no advice; **no new store/tab/provider/agent**. See
  `Blueprint/V1_Completion_Plan.md`.
- ✅ **Performance & Responsiveness (Epic 9)** - measure-first; **no new features**. Profiling proved the
  slowness was live provider latency on the UI thread (Inbox scan ~48s, Communications ~35s, Home briefing
  ~39s), not compute. A bounded in-memory signal cache (`core/executive-cache.ps1`; TTL, single-flight,
  stale-on-failure, shared across a worker+UI via a synchronized hashtable) + a background worker runspace
  (`core/async-run.ps1`) that builds the briefing model off the dispatcher + a conservative per-view cache.
  Measured 8-10x on the worst operations; provider fetches deduped to 1/source/window; cached tab switch
  252->5 ms. Read-only, SSOT and Executive Context ownership preserved. See
  `Blueprint/Performance_Responsiveness.md`.
- ✅ **Desktop App Identity** - Windows recognizes GIOK as its own app, not PowerShell. Root cause: no
  explicit AppUserModelID, so the taskbar/Alt+Tab identity defaulted to the host process. Fix (no
  compiled binary): a stable in-process AUMID (`GIOK.ExecutiveOS`) + console-hide in `dashboard.ps1`, a
  multi-size `giok.ico` from the official logo, and `Install-GiokShortcuts.ps1` for branded Desktop +
  Start Menu shortcuts on the existing silent `.vbs` launcher. Window titled "GIOK", clean shutdown, no
  business-logic change. See `Blueprint/Desktop_App_Identity.md`.
- ✅ **Tony Understanding Engine / Onboarding V2 (Epic 10)** - onboarding stops copying raw answers into
  Identity. The same 7 questions now feed an Understanding Engine
  (`core/understanding-engine.ps1`) that organises them into Goals, Values, Priorities, Challenges,
  Strengths, Boundaries and an Executive Summary - each item carrying its **source question, the user's
  original words, Tony's reason, and an internal confidence score**. One sentence can become several
  goals; hedged statements are omitted and asked about later; **conflicts produce a question, never an
  assumption**; nothing unsupported is invented (Strengths stays empty unless volunteered). Jake reviews
  everything in a new **"Here's what I understood"** view - interpretation beside his original words,
  every item editable - and only **"Tony got it right"** commits it, in one **atomic transaction that
  rolls back completely** if any write fails. Extraction is local/deterministic (no key, no network);
  Claude only enriches when configured. **No new store** (the pending model lives in the existing
  conversation file; Priorities/Challenges/Strengths/Boundaries in an `understanding` block inside
  `overview.json`), no provider or agent changes. See `Blueprint/Tony_Understanding_Engine.md`.
- ✅ **Personalizable Workspace (Epic 11)** - the user's data comes first, and the layout is theirs.
  **Goals** no longer opens on a blank form: goals render first, `+ Add Goal` sits on the header and the
  form appears only on request (Cancel writes nothing), with **domain + status filters** and **Delete
  behind a confirm** (it used to delete on one click). **Home** renders from a saved layout - **Customize
  Home** lets you show/hide, reorder, resize (small/medium/large) and reset, across 16 cards. The
  preferences file stores **only** `{id, visible, order, size}` (gitignored, user-specific): every card
  reads its **existing owner** live and navigates to that owner's workspace, so **no business data is
  duplicated** and deleting the file loses nothing. Provider cards **peek** the shared cache and never
  fetch on paint; hiding everything keeps the briefing; a toggle never restarts the background briefing.
  Single store for goals, no new tab, no new provider/agent. See
  `Blueprint/Personalizable_Workspace.md`.

**Remaining in Phase 1 (small):** the **Projects model** is now real (Home Projects fills the reserved
`project` context field). *(The dormant `tony-memory.ps1` framework was retired at RC1.)*

---

## Phase 2 — Connected Tony  *(live signals)*  — 🔄 in progress

Tony understands the real world through read-only providers, all on one reusable architecture.

- ✅ Live-provider registry — `relevant`/`query`/`status`, generic consumption (D13)
- ✅ Weather provider — Open-Meteo, keyless, live (D13)
- ✅ Google Calendar provider (read-only) — OAuth+PKCE, contract, Settings (D14)
- ✅ Calendar Intelligence — first/last/total, free blocks, meeting-heavy days (D15)
- ✅ Calendar-aware Executive Briefing (on demand, connected-only) (D15)
- ✅ **Google Calendar go-live** — live-connected + validated against Jake's real account (D15)
- ✅ Shared Google OAuth module + provider-neutral Email Intelligence (D16)
- ✅ Gmail provider (read-only) — Executive Email Summary, generic `email` signal (D16)
- ✅ Email-aware Executive Briefing (on demand, connected-only) (D16)
- ✅ **Gmail go-live** — live-validated on Jake's real account (D16)
- ✅ **Multi-account Google (D17)** — one Calendar + one Gmail provider read MANY accounts (business +
  personal); per-account tokens; merge/dedupe at the intelligence layer; Calendar migrated onto the
  shared OAuth module; live-validated across two real accounts
- ✅ **Yahoo Mail (Epic 8)** — Yahoo joins as a second read-only backend (IMAP + app password) behind
  Sam's one provider-neutral communications signal; Gmail + Yahoo merge into the single Executive Email
  Summary (no second engine); Sam is Head of Communications (she); daily + explicit historical search;
  read-only, no writes. See `Blueprint/Yahoo_Provider.md`.
- ⬜ Outlook / Microsoft 365 / SMS / voicemail / Slack / Teams / social — plug into the same `email`
  (communications) architecture as additional backends (join the merge; named, not yet built)
- ⬜ Maps provider (travel time; pairs with Calendar)
- ⬜ News / Stocks providers (read-only signals)

**Boundary:** everything read-only. Any write-back (RSVP, send, create event) is Phase 3+ and
consent-gated.

---

## Phase 3 — Executive Automation  *(Tony acts ahead of you)*  — ⬜ not started

Tony prepares and protects the day proactively, still proposing rather than acting unilaterally.

- ⬜ Local scheduler — pre-compose the morning briefing ("prepared while you slept")
- ⬜ Proactive, calendar-aware daily planning (free-block protection, workload assessment)
- ⬜ Meeting preparation (context + attendees + suggested agenda from Calendar/Gmail)
- ⬜ Automated End-of-Day Audit assistance and week-ahead letters
- ⬜ **Write capabilities with approval** — the first actions Tony takes on Jake's behalf (create
  event, RSVP, draft email), each behind an explicit confirm-before-act model
- ⬜ Life Score framework activation (replace sample scores with real signals)

---

## Phase 4 — Tony OS  *(everywhere, for the whole operation)*  — ⬜ future

GIOK becomes the operating layer across devices and the agency.

- ⬜ Desktop-icon launch / installer; keep core UI-agnostic, wrap it later
- ⬜ Mobile / web / Android surfaces (per the alpha roadmap)
- ✅ Agent Workforce activated (the "AI Workforce" becomes real) — the D20 Workforce Engine + Epic 4
  Executive Manager are live with six specialists (Sam, Ava, Emma, Riley, Mason, Randy), and **Epic 6**
  has them **proposing** into the Executive Inbox (evidence-backed, de-duplicated, approval-gated);
  future specialists (Finance, Social, Health, Research, Travel, Phone, Meeting) register the same
  interface and inherit the same producer/proposal pattern
- 🔄 Agency integrations — **read-only GoHighLevel is built** (Randy, the CRM Manager; generic `crm`
  signal; HubSpot/Salesforce/Zoho/Pipedrive are provider backends, not a Randy redesign); write-with-
  approval is later and consent-gated
- ⬜ Cross-workspace automation; document ingestion into memory (approval-gated)

---

## Next recommended sprints

1. **D19 — Executive Automation Foundation (local scheduler).**
   Pre-compose the morning briefing (now MULTI-ACCOUNT and PRIORITY-RANKED) so it's ready the instant
   GIOK opens; the seam already exists in the briefing/context/priority engines.
   *Why next:* turns "connected" into "ahead of you" — the first Phase-3 capability, and the D18
   Executive Priority Engine gives it a ranked plan worth pre-computing.

2. **D20 — Projects Model.**
   A real projects store so the Executive Context `project` field is live, Action Items can link to a
   project/goal, and priority "why" gets specific.
   *Why next:* removes standing technical debt and sharpens judgment across Home, briefing, and
   context — compounding value for every later sprint.

3. **D21 — Meeting Prep + Focus-Block Protection.**
   Using Calendar + Gmail (now across all accounts), Tony drafts a short prep for the next meeting and
   proposes protecting the clearest free block.
   *Why next:* the first genuinely "chief-of-staff" proactive help, and a natural on-ramp to
   consent-gated write actions later.

4. **Gmail/Calendar to Production (Jake, manual).** Publish the OAuth consent screen so refresh tokens
   stop expiring every ~7 days; complete Google verification for the sensitive read-only scopes.

---

## Deferred ideas

Maps / News / Stocks providers · write-back to Calendar/Gmail (consent-gated) · GoHighLevel
integration · document ingestion into permanent memory · agent-workforce activation · Mission Control
as a true second screen · Life Score real signals · mobile/web/Android surfaces · multi-user /
per-user personalization.

## Dependencies

- **D15** depended on Jake's Google Cloud OAuth setup (manual) from D14 — done; Calendar is live.
- **D16 (Gmail)** reused the OAuth + live-provider pattern on a shared `core/google-oauth.ps1` +
  provider-neutral `core/email-intelligence.ps1`; no Brain changes. Registered as the generic `email`
  signal so **Outlook / Microsoft 365 / Yahoo** later implement only a backend + normalizer.
- **D17 (automation)** depends on durable live connections (D15/D16) and a desktop scheduler (Windows
  Task Scheduler or a lightweight loop) — a real desktop constraint to design for.
- **D18 (projects)** unblocks the Executive Context `project` field and better priority reasons; no
  external dependency.
- **Write capabilities (Phase 3)** depend on the **permission model from D12** plus a
  confirm-before-act UX — Tony proposes, Jake approves; never automatic.

## Why this ordering

Phase 1 gave Tony a mind; Phase 2 is giving him senses. The near-term queue finishes the sense that's
half-built (Calendar), adds the next highest-value one (Gmail), then converts sensing into
anticipation (automation) — but only after there's real data worth anticipating on. Projects is
slotted early because it's cheap, retires debt, and makes every downstream judgment sharper. Write
actions come last and slowest, deliberately: trust is the product, so Tony earns the right to *act*
only after he has proven he can *understand* — and always by asking first.
