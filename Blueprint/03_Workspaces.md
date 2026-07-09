# 03 — Workspaces

GIOK is organized into **workspaces** — coherent areas of a life and business. Each workspace is
a lens on the same single source of truth, not a separate silo. The sidebar is the map; Tony and
the Home dashboard cut *across* workspaces to answer "what matters today."

Every workspace is defined by five things: its **Purpose**, the **Problems it solves**, **What
belongs there**, **What does NOT belong there**, and its **Future integrations**. The "does not
belong" line is as important as the rest — it's how GIOK stays calm instead of becoming a junk
drawer.

The hierarchy:

```
Home
├─ Goals
├─ Non-Negotiables
├─ Agency
├─ Health
├─ Financial
├─ Family
├─ Home Projects
├─ Learning
├─ AI Workforce
├─ Mission Control
├─ Tony
└─ Settings
```

---

## Home
- **Purpose:** The executive cockpit — the one screen that answers "What should Jake focus on
  today?" Full spec in [04_Home.md](04_Home.md).
- **Problems it solves:** Scattered attention; not knowing where to start; important-but-not-urgent
  work losing to noise.
- **What belongs:** Morning brief, today's priorities, Tony's recommendations, quick capture,
  cross-workspace highlights, scores at a glance.
- **What does NOT belong:** Deep editing, settings, raw lists, anything that isn't "today."
- **Future integrations:** Calendar, email, GHL — feeding the brief and priorities.

## Goals
- **Purpose:** Where long-horizon intentions live and are kept alive across quarters and years.
- **Problems it solves:** Goals set once and forgotten; no line from a daily task to a yearly aim.
- **What belongs:** Annual/quarterly goals, milestones, the "why," progress toward each.
- **What does NOT belong:** Day-to-day tasks (those are action items linked *to* a goal), vague
  wishes with no owner or measure.
- **Future integrations:** Life Score trends, calendar milestones, coaching from Tony.

## Non-Negotiables
- **Purpose:** The bright lines Jake refuses to cross — the disciplines that define him (5am
  training, annual Checkups, time with family, honesty with clients).
- **Problems it solves:** Values eroding under pressure; the urgent overriding the essential.
- **What belongs:** A short, sacred list of commitments and their streaks/consistency.
- **What does NOT belong:** Ordinary tasks, negotiable preferences, anything that dilutes the
  list. If everything is non-negotiable, nothing is.
- **Future integrations:** Consistency scoring, habit tracking, protective calendar blocking.

## Agency
- **Purpose:** The business command center — clients, the Checkup pipeline, leads, referrals,
  outreach, and revenue-driving activity.
- **Problems it solves:** Leads going cold; Checkups slipping; referrals never asked for; no
  single view of the book of business.
- **What belongs:** Client records, Checkup schedule, pipeline stages, lead/referral tracking,
  agency metrics, outreach drafts.
- **What does NOT belong:** Personal life items, generic notes, anything not tied to the business.
- **Future integrations:** GoHighLevel (CRM/SMS), email, calendar, e-signature, quoting tools.

## Health
- **Purpose:** Jake's physical and mental wellbeing — training, sleep, nutrition, recovery.
- **Problems it solves:** Health becoming invisible until it breaks; discipline in one area not
  reinforcing the others.
- **What belongs:** Workouts, health habits, metrics, medical reminders, the health portion of
  the Life Score.
- **What does NOT belong:** Business tasks, family logistics (unless health-related), raw
  everything-notes.
- **Future integrations:** Wearables (watch/ring), fitness apps, health records.

## Financial
- **Purpose:** Personal and business finances — budgets, cash flow, targets, obligations.
- **Problems it solves:** Money decisions made reactively; no clear picture of runway or goals.
- **What belongs:** Budgets, income/expense tracking, financial goals, bills/obligations, the
  financial Life Score.
- **What does NOT belong:** Executing trades or moving money (GIOK informs; Jake acts — see
  Principle 6), unrelated notes.
- **Future integrations:** Accounting tools, banking (read-only), commission tracking.

## Family
- **Purpose:** The people who matter most — commitments, dates, shared logistics, memories.
- **Problems it solves:** Family losing to work; important dates and promises forgotten.
- **What belongs:** Family events, promises, shared reminders, kids' activities, memories/wins.
- **What does NOT belong:** Business tasks, anything that turns family into a project to optimize
  rather than people to be present for.
- **Future integrations:** Shared calendar, photos, reminders.

## Home Projects
- **Purpose:** The house and physical life admin — projects, maintenance, purchases.
- **Problems it solves:** Home tasks living on scattered lists; recurring maintenance forgotten.
- **What belongs:** Home to-dos, projects, maintenance schedules, shopping/home purchases.
- **What does NOT belong:** Business or family-relationship items, general ideas.
- **Future integrations:** Shopping lists, smart-home devices, vendor/contact records.

## Learning
- **Purpose:** Deliberate growth — courses, books, skills, industry study, content ideas.
- **Problems it solves:** Growth left to chance; captured ideas never revisited.
- **What belongs:** Learning goals, notes, reading list, courses, skill progress.
- **What does NOT belong:** Task management (link learning tasks to action items), unrelated
  captures.
- **Future integrations:** Note tools, course platforms, content pipeline.

## AI Workforce
- **Purpose:** The fleet of AI agents and scheduled workers GIOK oversees — the registry-backed
  automation that does work on Jake's behalf.
- **Problems it solves:** Automation running blind; no single place to see if agents are healthy,
  overlapping, or broken.
- **What belongs:** Agent registry, health/status, schedules, ownership, dependencies, agent
  performance. (Today this is the Agents view over `agents_registry.json`.)
- **What does NOT belong:** Human tasks, personal data, anything that isn't an automated worker
  or its output.
- **Future integrations:** The scheduler (CoWork), agent runtimes, per-agent live status.

## Mission Control
- **Purpose:** The dense, glanceable, second-monitor overview of the whole operation. Full spec
  in [08_Mission_Control.md](08_Mission_Control.md).
- **Problems it solves:** No single "situation room"; having to click through tabs to feel the
  state of things.
- **What belongs:** Live widgets — agent health, issues, priorities, sprint, recommendations,
  business + health metrics, alerts.
- **What does NOT belong:** Editing, configuration, deep drill-down (Mission Control links out to
  those).
- **Future integrations:** All live feeds — CRM, calendar, wearables, finances.

## Tony
- **Purpose:** The workspace for the relationship with Tony — his memory, recommendations,
  reasoning, and the "Ask Tony" surface. Full character in [06_Tony.md](06_Tony.md).
- **Problems it solves:** An assistant with no visible memory or accountability; not knowing why
  Tony suggested something.
- **What belongs:** Conversation/command surface, Tony's memory, recommendation history, coaching
  notes, trust settings.
- **What does NOT belong:** Raw data storage (Tony reads the registry; he isn't a second copy of
  it), unrelated content.
- **Future integrations:** LLM backends, voice, and Tony's read/act permissions across workspaces.

## Settings
- **Purpose:** Configuration of the whole system — branding/theme, workspace on/off, identity,
  permissions, preferences.
- **Problems it solves:** Hard-coded assumptions; no way to personalize or (later) support other
  users.
- **What belongs:** Theme (`theme.json`), workspace/identity settings, Tony's permissions,
  integration credentials (secured), preferences.
- **What does NOT belong:** Actual work content, data — settings configure GIOK, they don't store
  the life.
- **Future integrations:** Auth/identity, secret storage, per-user profiles (multi-user later).

---

**Rule for adding a workspace:** it must have a genuinely distinct purpose and a clear "does not
belong" boundary. If a proposed workspace overlaps an existing one, extend the existing one
instead. Calm comes from fewer, sharper spaces — not more.
