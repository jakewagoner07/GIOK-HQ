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
| — | [First Conversation](First_Conversation.md) | Why GIOK starts with conversation, not configuration |
| — | [Identity](Identity.md) | The Identity workspace — GIOK's foundation; Vision & Goals live here |
| — | [Continuous Improvement](Continuous_Improvement.md) | Plan → Execute → Audit → Improve; Morning Briefing & End of Day Audit |
| — | [Capture](Capture.md) | How Capture is built, version by version (companion to 05) |
| — | [Tony Memory](Tony_Memory.md) | How Tony's structured memory evolves through V3 |

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
