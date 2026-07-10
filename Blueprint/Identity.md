# The Identity Workspace

*Sprint Mike. The foundation of GIOK.*

Identity is the **foundation** of GIOK — the user's **personal operating system**. Before GIOK
helps Jake run a business or a day, it helps him hold on to *who he is becoming*. Everything else
in GIOK — priorities, Checkups, scores, coaching — ultimately serves the identity defined here.

> **Vision and Goals are no longer separate top-level workspaces. They are sections inside
> Identity.** Who you are becoming (Vision) and what you're working toward (Goals) belong to your
> identity, not off in their own silos.

## Purpose
- Give Jake one place that answers *"Who am I becoming, and why?"*
- Anchor the daily grind to something permanent — vision, values, mission, legacy.
- Feed the rest of GIOK: the Life Score, coaching, the Morning Experience, and the audits all
  reference identity as the source of "what matters."

## Sections
Identity expands into nine sections, each backed by its own source-of-truth file in `identity/`:

| Section | File | What it holds |
|---------|------|---------------|
| **Overview** | (aggregated) | Executive summary of who Jake is becoming |
| **Vision** | `vision.json` | The long-horizon vision + progress |
| **Goals** | `goals.json` | Goals and their progress *(now lives here, not top-level)* |
| **Core Values** | `values.json` | The values Jake operates by |
| **Mission** | `mission.json` | The mission statement |
| **Legacy** | `legacy.json` | The legacy to be remembered for |
| **Annual Theme** | `annual_theme.json` | The theme for the year |
| **Journal** | `journal.json` | Reflective entries over time |
| **Timeline** | `timeline.json` | Milestones of the journey |

### Overview
The executive summary — a glance at the trajectory of the person, with cards for: **Identity
Score**, **Vision Progress**, **Goal Progress**, **Current Annual Theme**, **Core Values**,
**Latest Journal Entry**, **Recent Wins**, and **Tony's Reflection**. (Identity Score and Tony's
Reflection are placeholders until the scoring and reasoning engines are live.)

## Architecture
- **Identity owns all identity data.** The `identity/*.json` files are the single source of truth
  for vision, goals, values, mission, legacy, theme, journal, and timeline.
- **Other workspaces reference, never duplicate.** The Home dashboard, Life Score, Morning
  Experience, and audits may *read* identity data (via the identity data layer) but must never
  keep their own copy. One source of truth, always.
- **Self-contained.** Identity is a complete workspace — its data, its sections, its logic — that
  can evolve without redesigning the rest of GIOK. (See the "Every Workspace Is Self-Contained"
  principle in [02_Core_Principles.md](02_Core_Principles.md).)

## How Identity powers the rest of GIOK (future)
- **Life Score** draws on values and consistency to reflect whether Jake is living his identity.
- **Morning Experience & Briefing** surface the annual theme, a value, and goal progress.
- **End of Day Audit** reflects the day against the identity (did today move the vision? honor
  the values?).
- **Tony's coaching** is grounded in the identity — he coaches Jake toward who Jake said he wants
  to become, not a generic ideal.

## Evolution
- **V1 (now):** the workspace, nine sections, JSON source of truth, and an Overview built from
  local data. Placeholders where scoring/reasoning aren't live.
- **V2:** editing (write vision/goals/values/journal from the app), a real Identity Score,
  goal-to-task linkage, and journaling tied to the End of Day Audit.
- **V3:** Tony reasons over identity — proactive reflections, drift detection ("your recent days
  don't match your stated values"), and identity-aware coaching.

Identity is where GIOK stops being a productivity tool and becomes a **life operating system**.
