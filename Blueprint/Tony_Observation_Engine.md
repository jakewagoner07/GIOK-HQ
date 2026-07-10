# Tony's Observation Engine

## Tony begins to notice

*Project Diamond, Sprint D9. Tony starts noticing patterns in Jake's life.*

Implementation: `tony-alpha/dashboard/core/tony-observations.ps1`, surfaced as Observation Cards
on the Home dashboard.

## Observations, not reminders

A reminder pokes you. A notification interrupts you. An **observation** is what a trusted chief of
staff offers quietly, over coffee: *"I've noticed something — can I share it?"* Tony's Observation
Engine is deliberately the third kind. It never pings, never nags, never demands action. It
watches the patterns in Jake's own data and, when something is worth naming, says so — kindly.

## What Tony reads

The engine reads the existing sources — referenced, never duplicated:

- End of Day Audits (scores, non-negotiables, wins, reflections, tasks moved to tomorrow)
- Action Items · Journal · Identity · Goals · Mission · Annual Theme · Morning Briefings

## What Tony looks for

Repeated postponements · positive habits · negative habits · momentum · balance · time
allocation · **family vs work** · consistency · progress · recurring obstacles.

Each pattern is a small deterministic detector. A detector stays silent unless the signal is
really there, and every detector is written to **notice the good as readily as the hard** — the
non-negotiables that held, the goal within reach, the wins that got named.

## The rules (non-negotiable)

- **Never criticize. Never shame.** A missed habit is a gentle question, not a verdict.
- **Celebrate wins.** Positive patterns are surfaced, not just problems.
- **Offer guidance**, never orders.
- **Always explain why it matters.** Every card carries a "Why this matters" — an observation
  without its reason is just noise.

## Confidence — and why low confidence becomes a question

Every observation carries an internal confidence: **High**, **Medium**, or **Low**, scaled by how
much history backs the pattern (one audit day is thinner evidence than a two-week streak).

**Low-confidence observations are always presented as questions, never statements.** If Tony isn't
sure, he wonders aloud — *"Is it waiting on something, or would a single next step get it moving?"*
— rather than asserting something he can't yet stand behind. This keeps Tony honest and keeps Jake
in charge of the interpretation. (Enforced in `New-Observation`: `Confidence = Low` forces
`tone = question`.)

## Family before Financial

The balance detector watches family scores against work and financial scores. When work runs
clearly ahead, Tony names it — and grounds the "why" in the rule that governs everything: *family
comes before financial.* He acknowledges what went right first (family time protected), then asks
whether the margin is worth guarding again. Never a scold; always a nudge toward the life the
business is meant to serve.

## Tony's language

*"I noticed…"* · *"It looks like…"* · *"I've been seeing…"* · *"You've been doing a great job…"* ·
*"Can I share something I've observed?"* Warm, human, specific — never robotic.

## The dashboard: Observation Cards

Home shows **at most 3 active observations**, **highest impact first** (`Get-TopObservations
-Max 3`). Impact weighs the importance of the area (family and consistency rank high) against the
strength of the signal. Three is a deliberate ceiling: a chief of staff surfaces the vital few, not
a wall of noticing. Each card shows the category (tone-colored), a confidence pill, the
observation in Tony's voice, and why it matters.

## How this grows

Today the detectors are transparent heuristics over one day of audit history; they get sharper as
history accumulates (a one-day "nice work" becomes a High-confidence streak; a task moved twice
becomes a named recurring obstacle). The output shape — headline, message, why, confidence, tone,
impact — is the stable contract, so richer detection (or a future model informing the scores) plugs
in without changing the cards or the rules.

## Constraints honored

No reminders, no notifications, no writes, no new integrations. Pure read-and-notice over the
single source of truth, in Tony's warm executive voice.

## Related
- [Tony_Decision_Framework.md](Tony_Decision_Framework.md) — the same value-weighted judgment, applied to a question instead of a pattern.
- [Tony_Helpful_First.md](Tony_Helpful_First.md) — the personality that keeps observations kind.
- [Continuous_Improvement.md](Continuous_Improvement.md) — the Audit loop the engine reads from.
- [13_Project_Diamond.md](13_Project_Diamond.md) — noticing, done as an experience worth having.
