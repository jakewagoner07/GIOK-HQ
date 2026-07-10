# 004 — Identity

**Date:** 2026-07-09
**Version:** 0.6 Alpha (Sprint Mike)

## Problem
GIOK was becoming a very good place to run a *day* and a *business*. But a life run entirely by
to-do lists and dashboards drifts. Under pressure, the vital-but-quiet things — vision, values,
legacy, who you're actually becoming — lose to whatever is loudest. Meanwhile "Vision" and "Goals"
were drawn as their own separate workspaces, scattered off in silos, disconnected from the person
they belonged to.

## Decision
Make **Identity** the *foundation* of GIOK — the user's personal operating system — and move
**Vision and Goals inside it** as sections, alongside Core Values, Mission, Legacy, Annual Theme,
Journal, and Timeline. Identity owns all identity data (`identity/*.json`); everything else
references it.

## Reasoning
- Vision (who you're becoming) and Goals (what you're working toward) are *expressions of an
  identity*, not free-floating lists. Putting them inside Identity says so structurally.
- Identity is the anchor the rest of GIOK serves. The Life Score, the Morning Experience, the End
  of Day Audit — they all become more meaningful when they measure the day against *who Jake said
  he wants to be*, not a generic ideal.
- This crystallized a new law: **Every Workspace Is Self-Contained.** A workspace owns its data,
  sections, and logic and can evolve without redesigning the rest of GIOK. Identity owning
  `identity/*.json` while the dashboard merely reads it is Single Source of Truth applied at the
  workspace level.

## Lessons Learned
- **The product's spine is a person, not a pipeline.** Framing Identity as the foundation reframed
  GIOK from "productivity software" to "a life operating system" — and clarified what everything
  else is *for*.
- **Self-contained workspaces are how you grow wide without tangling.** Because Identity is
  isolated, adding it required touching nothing else — the exact property we'll need to add Health,
  Financial, Family, and the rest.
- Placeholders, honestly labeled, let the sidebar tell the whole story (all the future workspaces)
  without pretending they're built.

## Future Ideas
- A real Identity Score, and Tony detecting *drift* ("your recent days don't match your stated
  values").
- Identity-aware coaching: Tony coaching Jake toward the specific person Identity describes.
- Journaling that flows out of the End of Day Audit into the Identity timeline.

## Related Blueprint Documents
- [Identity.md](../Identity.md) — the Identity workspace in full.
- [02_Core_Principles.md](../02_Core_Principles.md) — "Every Workspace Is Self-Contained."
- [03_Workspaces.md](../03_Workspaces.md) — the hierarchy, with Vision & Goals now inside Identity.
- [07_Life_Score.md](../07_Life_Score.md) — how identity feeds the scoreboard.
