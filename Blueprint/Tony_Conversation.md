# The Tony Conversation Experience

## Talking to your Chief of Staff

*Project Diamond, Sprint D7. Tony's primary interface becomes a conversation.*

Implementation: `tony-alpha/dashboard/core/tony-conversation.ps1` (history + greeting) and the
conversation window in `tony-alpha/dashboard/ui/tony-ui.ps1`.

## Why a conversation, not a search box

A search box asks for a query and returns a result. That framing is wrong for a Chief of Staff.
You don't *query* the person who runs your day — you **talk** to them. The interaction should feel
like messaging someone who already knows your priorities, remembers what you said an hour ago, and
answers in context.

So "Talk with Tony" is a dedicated window that behaves like a messaging thread:

- **Tony greets you** by name, aware of the time of day, where you are, and your top priority.
- **Your turns and Tony's turns** stack as chat bubbles, newest at the bottom, auto-scrolled.
- **A thinking indicator** shows Tony is working before he replies.
- **The typing area** accepts multi-line input (Enter sends, Shift+Enter for a new line).
- **New bubbles fade and slide in** — calm, deliberate motion, never flashy.

Two doors open it: clicking **Talk with Tony** in the toolbar, or pressing **Ctrl+K** anywhere.

## The conversation persists

Closing the window never erases the thread. Every turn is written to `conversation.json` and
reloaded when you come back, so the relationship has continuity — Tony picks up where you left off.
The file is **local and private**: it is gitignored and never leaves the machine. "Your brain is
for thinking, not remembering" applies to the conversation itself — GIOK remembers it so you don't
have to.

## What Tony knows in a conversation

Before Tony answers a general question, the conversation hands Tony Brain the context a chief of
staff would already have:

- **Current workspace** — where you are in GIOK right now.
- **Current project** — the active project (seam in place; projects arrive in a later sprint).
- **Recent conversation** — the last several turns, so replies build on what was just said.
- **Current priorities** — gathered by Tony Brain from the briefing and action items.

This flows through the existing architecture unchanged: the conversation calls `Invoke-TonyBrain`,
which runs the [Decision Framework](Tony_Decision_Framework.md) as guidance and then the
[Provider Contract](Tony_AI_Provider_Contract.md). The conversation is a new *surface*, not a new
brain — Tony's judgment and the model-agnostic seam are exactly as before.

## Quick commands still execute instantly

The quick-command bar remains for what it's good at: fast, unambiguous actions.

- `open <workspace>`, `add task: <text>`, `capture: <text>` — these **execute immediately**,
  whether typed in the command bar or in the conversation. Tony confirms the action in a bubble.
- A **general question** typed into the command bar is not a command — it **opens the conversation**
  and Tony answers there, instead of flashing a one-off line on the dashboard.

The rule: commands *do*, conversations *discuss*. Each interaction goes to the surface built for it.

## Future support

The conversation is the natural home for richer input as GIOK grows — **attachments, documents,
images, and voice**. The document pathway already exists: [Document Intelligence](Document_Intelligence.md)
reads a file for meaning and proposes changes for approval; a future version lets you drop a
document straight into the conversation. Each addition plugs into the same thread, the same history,
and the same brain — the experience deepens without being rebuilt.

## Constraints honored

Dark executive theme throughout. Beautiful, restrained animation. No cloud required — history is a
local JSON file, and with no provider key configured Tony answers honestly through the local stub.
Project Diamond intact: this is an *experience* made better, not a feature bolted on.

## Related
- [06_Tony.md](06_Tony.md) — Tony's personality, role, and boundaries.
- [Tony_Brain.md](Tony_Brain.md) — the reasoning the conversation calls into.
- [Tony_Decision_Framework.md](Tony_Decision_Framework.md) — the judgment applied before Tony replies.
- [Tony_AI_Provider_Contract.md](Tony_AI_Provider_Contract.md) — the model-agnostic seam behind every answer.
