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
