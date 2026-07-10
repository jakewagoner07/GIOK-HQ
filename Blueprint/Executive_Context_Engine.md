# The Executive Context Engine

## Tony never answers in isolation

*Project Diamond, Sprint D10. Not a workspace, not a UI - a refinement of Tony's judgment.*

Implementation: `tony-alpha/dashboard/core/executive-context.ps1` -> `Get-TonyExecutiveContext`.

## Purpose

An executive chief of staff never answers a question cold. Before he speaks he already knows the
day, the hour, what's on your plate, whether you're on track, and where the long game sits - and he
lets that shape the answer. **Context is invisible. The user simply feels that Tony "gets it."**

Before D10, Tony Brain rebuilt a slice of context inline for every call, and the provider was handed
a pile of raw fields to reassemble. The Executive Context Engine makes situational awareness a
**single, first-class step**: assemble once, judge once, hand the provider a concise read.

## What it assembles

`Get-TonyExecutiveContext` gathers - by **reference**, never by copy - everything Tony should weigh:

- **Time:** current date, day of week, time, hour, part of day (morning/afternoon/evening/night), weekend flag
- **Place:** active workspace, active project (if one is set)
- **The day:** current Morning Briefing, most recent End of Day Audit, today's priorities, open work
- **The person:** Identity, Mission, Core Values, Vision, Annual Theme, active Goals
- **The signals:** the Observation Engine's top observations, recent conversation, recent document activity
- **The judgment:** the Decision Framework's evaluation of the current question

It then answers, silently, the questions an executive asks before speaking:

> What matters most today? · Is anything overdue? · Is Jake off-track? · Is Jake making progress? ·
> Is there a conflict between today's work and long-term goals? · Should I ask a clarifying
> question instead of assuming?

The result is one **Executive Context** object, plus a **concise executive summary** - a dense,
human, situational paragraph that captures the read in a few sentences.

## Architecture

```
Get-TonyExecutiveContext   (core/executive-context.ps1)  <-- the SINGLE source of situational awareness
  |-- Get-TonyContext       (memory engine: identity, actions, audits, briefing, registry, capture)
  |-- Get-MorningBrief / End of Day Audits / Action Items / Identity / Goals / Mission / Theme
  |-- Get-TopObservations   (Observation Engine)
  |-- Evaluate-TonyDecision (Decision Framework - judgment)
  |-- Get-RecentConversation
  -> assessment (the six internal questions) + executiveSummary

Invoke-TonyBrain  (core/tony-brain.ps1)
  -> calls Get-TonyExecutiveContext ONCE, reuses its base context for the reasoning engine
  -> passes the concise executiveSummary to the Provider Contract (context field)
  -> the Decision Framework result travels as guidance and keeps FINAL authority

Provider (claude-provider.ps1)
  -> Get-ClaudeUserContent relays the executive summary instead of rebuilding context from raw fields
```

## Data flow

1. A question arrives at `Invoke-TonyBrain`.
2. `Get-TonyExecutiveContext` assembles the situation once - referencing existing sources, running
   the Observation Engine and the Decision Framework as part of the read.
3. The reasoning engine reuses the **same** base context (no second assembly) to pick intent.
4. The request carries the **concise executive summary** as its context, plus the Decision
   Framework's guidance.
5. The provider answers from that summary; **the Decision Framework still has the final say** on
   alignment and conflicts (Family before Financial included).
6. The user notices better judgment - the machinery stays invisible.

## Why context is different from memory

**Memory is what Tony knows. Context is what's true right now.** Memory is durable and stored -
your identity, your goals, past decisions, the audit trail. Context is *live and assembled on
demand* - it is never stored, never a second copy. The Executive Context Engine holds **no state of
its own**: every field is a reference to a source of truth (Identity owns identity, Action Items own
tasks, the Audit owns the day). Two calls a minute apart can differ because the *world* differed -
the clock moved, a task got done, an observation changed - not because anything was cached.

This is why context honors Single Source of Truth while memory-as-a-copy would violate it: there is
nothing to keep in sync, because nothing is duplicated. Same reason there are **no hidden memories** -
the engine reads what already exists and throws the assembly away after the answer.

## Future expansion

The engine is the clean seam for deeper situational awareness: calendar and weather (once a provider
exists), a real projects model (the `project` field is already wired), a document-activity feed (the
`recentDocument` slot is reserved), and richer assessments. New signals plug into the single
assembler; the executive summary shape stays the stable contract everything downstream relies on. A
future model can even *inform* the summary - but the dimensions and value priorities stay Tony's.

## Constraints honored

No cloud, no new integrations, no new workspaces, no new settings, no registry changes, no duplicate
storage, no hidden memories. Pure read-and-assemble over the single source of truth.

## Related
- [Tony_Brain.md](Tony_Brain.md) - the orchestrator that consumes the engine.
- [Tony_Decision_Framework.md](Tony_Decision_Framework.md) - the judgment inside the context; retains final authority.
- [Tony_Observation_Engine.md](Tony_Observation_Engine.md) - the patterns fed into the context.
- [Tony_AI_Provider_Contract.md](Tony_AI_Provider_Contract.md) - receives the concise summary, not raw fields.
