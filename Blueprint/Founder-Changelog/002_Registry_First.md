# 002 — Registry First

**Date:** 2026-07-08
**Version:** Registry 1.1 → 2.0 (Architecture Reviews 001 & 002)

## Problem
The first registry was a flat list of agents. As soon as we tried to reason about the fleet —
who owns what, what's critical, what depends on what, what's healthy — the list wasn't enough.
And a deeper question loomed: where does *everything* in GIOK live? Agents, departments,
integrations, memory, skills, workflows — if each invented its own storage, GIOK would become a
pile of half-truths.

## Decision
Make the **registry the first database of GIOK**, and make "everything registers itself" a law.
Architecture Review 001 gave every agent a **stable ID** (`AG-###`), an owner/department, a
priority, dependencies, and a health score. Architecture Review 002 formalized the principle:
the registry is the single source of truth, and other entity types (departments, integrations,
memory, skills, workflows) get scaffolded registries and stable-ID schemes too.

## Reasoning
- **Single Source of Truth** is the load-bearing principle of the whole product. One
  authoritative place per fact; everything else *reads* from it. Views are renderers, never
  second homes for data.
- Stable IDs mean nothing is ever referenced by name alone — names change, IDs don't.
- "Registry First" forces discipline: build the registry entry before the feature. If it isn't in
  the registry, it doesn't exist to the system.
- These weren't abstract preferences — they're what let GIOK grow wide later (Capture, Identity,
  Audits) without the data turning into a tangle.

## Lessons Learned
- **The data caught our errors.** Once the dashboard computed the priority breakdown live from the
  registry, it exposed a hand-written summary that was wrong (High 6 vs the real 7). A live single
  source of truth doesn't just store data — it *audits* the humans editing it.
- **Trust metadata is a feature.** Adding `verified_against_scheduler: false` and provisional
  flags on owner/priority made the registry honest about its own confidence. Uncertainty, labeled,
  is more valuable than false certainty.

## Future Ideas
- Every future workspace owns its own registry/source-of-truth files and never duplicates another's
  (which became the "Every Workspace Is Self-Contained" principle).
- Live status ingestion so `last_run`/`status` come from the real scheduler instead of `unknown`.

## Related Blueprint Documents
- [02_Core_Principles.md](../02_Core_Principles.md) — Single Source of Truth, Registry First,
  Never Duplicate Data, Every Workspace Is Self-Contained.
- [12_Future_Architecture.md](../12_Future_Architecture.md) — how future layers attach to the core.
