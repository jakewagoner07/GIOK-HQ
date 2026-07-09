# The GIOK Product Blueprint

**This is the constitution of GIOK.** It explains *why* the product exists — not just what
it does. Every future feature, screen, workflow, AI agent, and integration must follow it.

GIOK is not a dashboard. GIOK is the operating system for a disciplined life and business,
with **Tony** — Jake's AI Chief of Staff — living inside it. The product exists to answer one
question, every day: **"What should Jake focus on today?"**

> **People Matter More Than Money.**
> **Your brain is for thinking, not remembering.**

These two lines are the soul of the product. If a feature contradicts either one, it is wrong,
no matter how clever it is.

---

## How to use this blueprint

- Read it before starting any sprint. Decisions are settled here first, code second.
- When in doubt, the blueprint wins over convenience. When the blueprint is silent, extend it —
  don't quietly invent a contradicting rule in code.
- This is a *living* document. It evolves deliberately, through explicit revision — never by
  drift.

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

## Status of the product today (context, not constitution)

The first working product — **Tony Alpha** (`tony-alpha/`) — already exists: a dark executive
desktop command center with a registry, interactive action items, a command bar, multi-window
Mission Control, and a theme system. That work proves the direction. This blueprint defines
where it goes and the rules it must never break.

*Scope note: this blueprint sets product direction and principles. It intentionally does not
duplicate or override the technical architecture notes in `tony-alpha/` (ROADMAP.md, THEME.md,
etc.) — those remain the implementation record.*
