# Tony's Brain — Architecture

*Project Diamond, Sprint D2. Architecture only — no external AI, no APIs, no cloud.*

Tony's Brain is the reasoning core that a future AI plugs into. It is built **before** any model
is connected, so that connecting one later changes as little as possible. The brain lives in
`tony-alpha/dashboard/core/tony-brain.ps1` and is composed of five engines behind one hard rule.

> **The hard rule: Tony never knows which AI model is being used.** The brain speaks only to a
> provider *abstraction*. Only the provider layer knows the model, keys, or endpoint. Swap the
> provider and Tony is unchanged.

## The five engines

### 1. Memory Engine — `Get-TonyContext`
Assembles **one unified context object** by reading, live, from every relevant GIOK source:
- **Identity** (vision, goals, mission, values, overview)
- **Action Items** (open + total)
- **End of Day Audits** (recent history)
- **Morning Briefing** (the day's model)
- **Registry / AI Workforce** (version, agent count, verification)
- **Capture** (inbox stats)

It **references** each source through that module's accessors — it never duplicates or caches a
second copy (Single Source of Truth; Diamond Rule 3). The context is the single thing a provider
would be handed to reason with.

### 2. Conversation Engine — `Get-TonyPersona`, `Format-TonyVoice`
Defines Tony's voice: **friendly, professional, warm, executive, concise, encouraging — never
robotic.** It produces the persona (including a system-prompt-style summary) that a provider is
told to sound like, and lightly shapes raw responses so Tony's voice stays consistent regardless
of which model generated the words.

### 3. Reasoning Engine — `Get-TonyDecision`
Decides **what Tony should do**, using local heuristics (no AI). It returns a decision of one type:
- **answer** — respond to a question
- **ask** — ask a clarifying question (too little to act on)
- **recommend** — offer guidance
- **create-action** — turn intent into an action item
- **navigate** — open a workspace
- **none** — nothing to do

This is deliberately simple today; a future AI can inform or replace the heuristic, but the
*decision types* are the stable contract.

### 4. Action Engine — `Invoke-Tony*`
Placeholder actions Tony can take: **Open Workspace, Create Task, Save Note, Navigate**, and a
**Future Integration** stub. Each **describes** the action (type + params) and performs **no side
effects** — the UI/caller executes it. This keeps the brain pure and testable, and means every
action Tony proposes is explicit and reviewable (Diamond Rule 8: every action has a purpose).

### 5. AI Provider Interface — `Register-TonyProvider`, `Invoke-TonyProvider`
The **only** layer that knows a model. A provider is an object implementing a contract:
`{ name, description, invoke(param $Request) -> [string] }`. Future providers register here:
**Claude, OpenAI, Gemini, Local LLM** — none are implemented today. A **`local-stub`** provider
stands in: it honors the contract but uses no AI, returning honest, deterministic placeholders so
the whole brain is testable now.

The brain calls `Invoke-TonyProvider`, which routes to the *active* provider. The brain code never
names a model — it asks "the provider" to respond. That is how the hard rule is enforced in code.

## The orchestrator — `Invoke-TonyBrain`
One entry point ties the engines together:

```
remember (Memory)  ->  reason (Reasoning)  ->  respond via provider (in Tony's voice, Conversation)  ->  describe actions (Action)
```

It returns `{ input, decision, message, actions, provider }`. Note it reports which **provider**
answered, never which **model**.

## Why it's built this way (the ten-year view)
- **Model-agnostic.** GIOK isn't married to any AI vendor. When a better model appears, it plugs
  in behind the provider interface with zero changes to Tony.
- **Testable without AI.** The `local-stub` means the reasoning, memory, and action layers can be
  built and verified today.
- **Honest and controllable.** The brain proposes; it doesn't secretly act. Every action is a
  described intent the user/UI decides to execute — *AI explains, never controls*
  ([13_Project_Diamond.md](13_Project_Diamond.md), Founder Promise).
- **Single source of truth.** Memory reads the real data; it never becomes a rival copy.

## What connecting AI will (and won't) change
- **Will change:** implement a real provider (e.g., Claude) and `Set-TonyActiveProvider`. That is
  the *only* required change to give Tony a model.
- **Won't change:** the Memory, Reasoning, Conversation, and Action engines, or anything in the
  rest of GIOK. The seam was designed for exactly this.

## Related
- [06_Tony.md](06_Tony.md) — who Tony is (personality, boundaries, trust).
- [First_Conversation.md](First_Conversation.md) — the response generator that shares this
  swap-in philosophy.
- [02_Core_Principles.md](02_Core_Principles.md) & [13_Project_Diamond.md](13_Project_Diamond.md) —
  the principles the brain upholds.
