# Tony's Decision Framework

## The judgment layer

*Project Diamond, Sprint D5. This is not AI. It is Tony's judgment.*

Implementation: `tony-alpha/dashboard/core/tony-decision-framework.ps1` — one function,
`Evaluate-TonyDecision`.

## Why judgment is different from intelligence
**Intelligence answers the question. Judgment decides whether the answer is good for *this*
person, *this* life, right now.** A brilliant model can produce a flawless plan to work every
weekend for a year — and be completely wrong for Jake, because it costs him the family and health
that are the whole point. Intelligence is horsepower; judgment is the steering.

An AI, no matter how capable, does not inherently know that Family Time is non-negotiable, that
People Matter More Than Money, or that a plan should still make sense in ten years. Those are
*values*, and applying them is *judgment*. Tony must have judgment of his own — independent of any
model — so that whatever a provider generates is measured against the life the user is actually
building.

## Why Tony evaluates before responding
Tony runs the decision framework **before** any AI provider is asked. He evaluates the question
against the user's life and hands the result to the provider as **guidance**. This means:
- The AI never gets the last word unfiltered — Tony has already weighed it against identity,
  goals, and non-negotiables.
- The provider is *steered*: it receives Tony's alignment score, conflicts, and clarifying
  questions, and is expected to honor them.
- **Tony always makes the final recommendation.** The model informs; Tony judges.

## What it evaluates
`Evaluate-TonyDecision` takes the full picture — Identity, Vision, Goals, Mission, Core Values,
Annual Theme, Non-Negotiables, Family, Health, Financial, Current Workspace, Current Question, Open
Tasks, Recent Audits — and scores nine dimensions:

- **Identity Alignment** — does this fit who they're becoming?
- **Vision Alignment** — does it point at the long game?
- **Goal Alignment** — does it advance a stated goal?
- **Family Impact** — will it cost or invest in family? *(weighted high — People First)*
- **Health Impact** — does it protect or spend health?
- **Financial Impact** — informational only; GIOK never moves money.
- **Relationship Impact** — does it strengthen or neglect people?
- **Time Savings** — does it create leverage, or more manual work?
- **Project Diamond Compliance** — does it honor the standard and the ten-year rule?

## What it returns
- **Alignment Score** (0–100, weighted toward People First)
- **Conflicts** — dimensions that clash with the user's priorities (e.g. "Family Impact: may cost
  family time — protect it")
- **Recommendations** — Tony's read: move forward, proceed with a caveat, or pause
- **Suggested Clarifying Questions** — what Tony should ask before acting
- **Priority** — High / Medium / Low (urgency + alignment)
- **Confidence** — deliberately modest; this is a heuristic layer, not omniscience

## How it fits the architecture
```
Tony Brain
  -> Memory Engine (gather context)
  -> Reasoning Engine (decide intent)
  -> DECISION FRAMEWORK (judge alignment)   <-- runs before the provider
  -> Provider Contract (guidance attached, v1.1)
  -> Provider -> Model
  -> Tony makes the final recommendation
```
The framework's result travels in the contract's new optional `guidance` field, so any provider
receives it without a breaking change.

## How future reasoning improvements plug in
The framework is intentionally a **deterministic heuristic today** — transparent, testable, and
value-aligned even with no AI. It is a clean seam for improvement:
- A future model can **inform** the dimension scores (better nuance) while the *dimensions,
  weights, and value priorities stay Tony's* — so smarter reasoning never quietly overrides the
  user's non-negotiables.
- New dimensions (e.g. spiritual, community) can be added without touching the rest of GIOK.
- The output shape (alignment / conflicts / recommendations / clarifying questions / priority /
  confidence) is the stable contract everything downstream relies on.

Judgment is what turns a smart assistant into a trusted chief of staff. Tony evaluates first — so
that being *right* always beats being merely *clever*.

## Related
- [Tony_Brain.md](Tony_Brain.md) — where the framework runs.
- [Tony_AI_Provider_Contract.md](Tony_AI_Provider_Contract.md) — the `guidance` field (v1.1).
- [13_Project_Diamond.md](13_Project_Diamond.md) — the standard the framework enforces.
