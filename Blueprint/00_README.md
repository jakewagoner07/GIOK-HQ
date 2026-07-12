# The GIOK Product Blueprint

**This is the constitution of GIOK.** It explains *why* the product exists — not just what
it does. Every future feature, screen, workflow, AI agent, and integration must follow it.

GIOK is not a dashboard. GIOK is the operating system for a disciplined life and business,
with **Tony** — Jake's AI Chief of Staff — living inside it. The product exists to answer one
question, every day: **"What should Jake focus on today?"**

> **People Matter More Than Money.**
> **Your brain is for thinking, not remembering.**
> **GIOK helps you become better, not busy.**

These lines are the soul of the product. If a feature contradicts any of them, it is wrong, no
matter how clever it is. The third line is delivered through the **Continuous Improvement
Framework** — Plan → Execute → Audit → Improve — run daily via the Morning Briefing and the End
of Day Audit ([Continuous_Improvement.md](Continuous_Improvement.md)).

---

## How to use this blueprint

- Read it before starting any sprint. Decisions are settled here first, code second.
- When in doubt, the blueprint wins over convenience. When the blueprint is silent, extend it —
  don't quietly invent a contradicting rule in code.
- This is a *living* document. It evolves deliberately, through explicit revision — never by
  drift.
- **Hold every sprint to [Project Diamond](13_Project_Diamond.md)** — the quality standard for
  GIOK. Features are easy; experiences are hard. Nothing ships unless it's useful, beautiful,
  simple, fast, time-saving, and something Jake would use every day.

## Contents

| # | Document | What it settles |
|---|----------|-----------------|
| 01 | [Vision](01_Vision.md) | Why GIOK exists; mission, values, philosophy, long-term vision |
| 02 | [Core Principles](02_Core_Principles.md) | Permanent engineering & product principles |
| 03 | [Workspaces](03_Workspaces.md) | The complete GIOK workspace hierarchy |
| 04 | [Home](04_Home.md) | The executive home dashboard |
| 05 | [Capture System](05_Capture_System.md) | Capture-everything philosophy and routing |
| 06 | [Tony](06_Tony.md) | Tony's personality, role, and boundaries |
| 07 | [Life Score](07_Life_Score.md) | The Life Score framework |
| 08 | [Mission Control](08_Mission_Control.md) | The second-screen command center |
| 09 | [Product Roadmap](09_Product_Roadmap.md) | Version 1 → 3 and beyond |
| 10 | [Design System](10_Design_System.md) | Branding, color, type, components |
| 11 | [Mobile Vision](11_Mobile_Vision.md) | The future mobile experience |
| 12 | [Future Architecture](12_Future_Architecture.md) | Long-horizon architectural concepts |
| 13 | [Project Diamond](13_Project_Diamond.md) | The standard for building GIOK — quality over quantity |
| — | [Tony's Brain](Tony_Brain.md) | Tony's reasoning architecture; the AI provider seam |
| — | [Tony's AI Provider Contract](Tony_AI_Provider_Contract.md) | The model-agnostic request/response language |
| — | [Tony Is an Operating System](Tony_Is_An_Operating_System.md) | Why Tony isn't a chatbot; connecting the first provider (Claude) |
| — | [Tony's Decision Framework](Tony_Decision_Framework.md) | Tony's judgment layer — evaluate before responding |
| — | [Document Intelligence](Document_Intelligence.md) | How Tony reads documents for meaning and connects them to the OS — with approval |
| — | [Tony Conversation](Tony_Conversation.md) | "Talk with Tony" — the persistent conversation experience, not a search box |
| — | [Tony Is Helpful First](Tony_Helpful_First.md) | Tony answers the question first, guides second — and never makes you feel you asked wrong |
| — | [Tony Observation Engine](Tony_Observation_Engine.md) | Tony notices patterns — observations, not reminders; celebrate, guide, never criticize |
| — | [Executive Context Engine](Executive_Context_Engine.md) | Tony's single, live situational awareness — assembled before every response, never stored |
| — | [Executive Briefing](Executive_Briefing.md) | The morning letter from Tony — Home's centerpiece; calm, personal, never a dashboard |
| — | [Executive Priority Engine](Executive_Priority_Engine.md) | Ranks every real item into Act Now / Do Today / Keep Visible / Low-Value Noise — nothing legitimate is ever forgotten |
| — | [Tony Memory, With Permission](Tony_Memory_With_Permission.md) | Tony never remembers without asking — the permission model, Memory Review, and user control |
| — | [Weather Provider](Weather_Provider.md) | Tony's first live provider — the permanent architecture every future live service follows |
| — | [Google Calendar Provider](Google_Calendar_Provider.md) | Read-only Google Calendar via OAuth — Tony understands your schedule; the pattern for Gmail |
| — | [Gmail Provider](Gmail_Provider.md) | Read-only Gmail — Executive Email Summary; shared OAuth + provider-neutral email intelligence (Outlook/M365/Yahoo plug in) |
| — | [Multi-Account Google](Multi_Account_Google.md) | One Calendar + one Gmail provider reading MANY Google accounts (business + personal); per-account tokens, merged at the intelligence layer |
| — | [Executive Timeline](Executive_Timeline.md) | Tony understands time — what's new/aging/overdue/ignored/expiring, derived only from existing timestamps; no new storage |
| — | [The GIOK Workforce](Workforce.md) | **Constitutional** — the permanent org chart and bylaws of Tony's team (Tony, Sam, Ava, Emma, Riley, Mason, Randy + future hires); the Executive Awareness Principle and Rule of Progressive Delegation |
| — | [Workforce Engine](Workforce_Engine.md) | Tony's management layer — delegate to specialist analysts, merge reports, present one recommendation; Tony stays the only decision maker (D20) |
| — | [Executive Management](Executive_Management.md) | Promotes Tony from delegator to Executive Manager — decides who works/verifies/is skipped and when evidence is enough; progressive delegation, deterministic trust scoring, conflict arbitration (Epic 4) |
| — | [Randy — CRM Manager](Randy_CRM_Manager.md) | **Constitutional** — hires Randy, the CRM Manager; her charter and why she is built around CRM as a discipline (not GoHighLevel) so future CRMs need no redesign |
| — | [CRM Provider](CRM_Provider.md) | Read-only GoHighLevel backend + normalizer behind the generic `crm` signal Randy consumes; the normalized CRM model; preserves all five invariants |
| — | [Life Operating System](Life_Operating_System.md) | **Daily Driver** — the eight life/business workspaces (Goals, Non-Negotiables, Family, Health, Financial, Agency, Learning, Home Projects) made fully usable; the data-ownership map (one type → one owner → one home); folded into the one Executive Context |
| — | [Executive Inbox](Executive_Inbox.md) | **Epic 5** — GIOK's approval center: the Workforce proposes, Jake approves/edits/rejects; a pending-only queue that routes approvals to the owning modules (no second copies); Tony never auto-approves |
| — | [Workforce Activation](Workforce_Activation.md) | **Epic 6** — the Workforce starts proposing: per-specialist producers turn evidence-backed findings into Executive Inbox proposals through a deterministic de-dup/quality gate; on-demand scan; Tony's read-only awareness + calm briefing mention; only Jake's approval ever writes |
| — | [Conversational Capture](Conversational_Capture.md) | **Epic 7** — Jake tells Tony in normal conversation ("I want to lose 20 pounds") and a pure deterministic intent engine prepares the right Executive Inbox proposal (`discoveredBy=Tony`); high→propose, moderate→one clarifying question, low→nothing; content-based idempotent dedup; Tony never writes directly |
| — | [First Conversation](First_Conversation.md) | Why GIOK starts with conversation, not configuration |
| — | [Identity](Identity.md) | The Identity workspace — GIOK's foundation; Vision & Goals live here |
| — | [Continuous Improvement](Continuous_Improvement.md) | Plan → Execute → Audit → Improve; Morning Briefing & End of Day Audit |
| — | [Capture](Capture.md) | How Capture is built, version by version (companion to 05) |
| — | [Tony Memory](Tony_Memory.md) | How Tony's structured memory evolves through V3 |

## Project handoff (living documents)

Start here to pick up GIOK development in a fresh chat:

| Document | What it carries |
|----------|-----------------|
| [CTO Handoff](CTO_Handoff.md) | Read first — intent, rules, permanent decisions, exact stopping point, next-chat instructions |
| [Project Status](GIOK_Project_Status.md) | Current version/branch/PR, architecture, D1–D14, providers, private files, known issues, testing |
| [Product Roadmap](Product_Roadmap.md) | Phases 1–4, completed/in-progress, next five sprints, deferred ideas, dependencies |

## The story behind it

The [Founder Changelog](Founder-Changelog/00_INDEX.md) is the journal of *why* GIOK is being
built the way it is — the problems, decisions, reasoning, and lessons behind each milestone. The
Blueprint says what GIOK is; the changelog says why it became that.

## Status of the product today (context, not constitution)

The first working product — **Tony Alpha** (`tony-alpha/`) — already exists: a dark executive
desktop command center with a registry, interactive action items, a command bar, multi-window
Mission Control, and a theme system. That work proves the direction. This blueprint defines
where it goes and the rules it must never break.

*Scope note: this blueprint sets product direction and principles. It intentionally does not
duplicate or override the technical architecture notes in `tony-alpha/` (ROADMAP.md, THEME.md,
etc.) — those remain the implementation record.*
