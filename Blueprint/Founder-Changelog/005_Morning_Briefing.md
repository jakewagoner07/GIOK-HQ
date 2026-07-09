# 005 — The Morning Briefing

**Date:** 2026-07-09
**Version:** 0.5 → 0.6 Alpha (Sprints Kilo & Lima)

## Problem
Even with a beautiful dashboard, the first thing Jake saw each morning was *data* — cards and
numbers he had to interpret. But the real question every morning is human and singular: **"What
should I focus on today?"** A grid of widgets doesn't answer that. And the very first moment
inside GIOK — the first minute — was transactional, when it should be the moment that sets the
tone for the whole day.

## Decision
Two moves, one week apart in spirit:
- **Morning Briefing (Kilo):** replace the plain greeting on Home with **Tony's executive
  briefing** — greeting, a rotating daily principle, today's priorities, Tony's recommendations,
  score snapshots, notifications — rendered from a dedicated model, feeling *prepared before Jake
  arrived*.
- **Morning Experience (Lima):** make the **first minute** premium and calm — a centered welcome
  with a greeting, a quote (with real attribution), *why this today*, the day's principle and
  focus, priorities, one recommendation, and a **Begin My Day** button that transitions into the
  dashboard.

## Reasoning
- **Every day should begin with Tony, not with a spreadsheet.** A chief of staff briefs you; he
  doesn't hand you raw telemetry. The briefing exists to answer the one question and get Jake
  moving with intention.
- **The first minute is emotional, and that's the point.** The Morning Experience grounds Jake *as
  a person* before the Morning Briefing starts him *as an operator*. Ownership and discipline are
  easier to sustain when the day opens with meaning, not a to-do dump.
- **A dedicated model, rendered only by the UI.** All the briefing logic lives in core; the screen
  is pure presentation. That keeps "what matters today" swappable and honest (live data where we
  have it, clearly-labeled placeholders where we don't).

## Lessons Learned
- **Composition beats a monolith.** The Morning Experience is built from independent, replaceable
  section components. Each can evolve — a better quote engine, an AI-generated focus — without
  redesigning the screen. Small pieces, cleanly seamed, age well.
- **Placeholders with attribution are honest.** Even the quote library carries author, theme, and
  source; nothing pretends to be more than it is.
- Renaming "Morning Brief" to "Morning **Briefing**" was small but right — a briefing is something
  a chief of staff *delivers*, and the word carries the relationship.

## Future Ideas
- "Why this today" powered by real signals — goals, health, scores, patterns, capture history, and
  past audits — instead of placeholder reasoning.
- The morning read aloud on the drive; the Begin My Day transition animating into the day.

## Related Blueprint Documents
- [04_Home.md](../04_Home.md) — the Morning Briefing on the executive home.
- [Continuous_Improvement.md](../Continuous_Improvement.md) — the Morning Experience → Briefing as
  the PLAN step of the daily loop.
- [06_Tony.md](../06_Tony.md) — Tony as the one who prepares and delivers the briefing.
