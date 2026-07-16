# The First Conversation

*Project Diamond, Sprint D1. One of the most important experiences in GIOK.*

> GIOK does not start with configuration. It starts with a **conversation.**

## Why conversation instead of configuration
Every other tool onboards you by making you *work* — forms, toggles, empty states, "set up your
profile." It asks you to serve the software before the software has done anything for you. That's
backwards, and it's cold.

GIOK is a life operating system with a **Chief of Staff** inside it. A real chief of staff doesn't
hand you a settings screen on day one. He sits down, asks about *you*, and listens. So GIOK's
first experience is Tony asking Jake who he is, what matters, and who he's becoming — **before**
the dashboard ever appears.

The goal is singular and emotional: **make the user feel understood before they see a single
widget.** Understanding first, tooling second. That is the whole philosophy.

## How it feels
Tony behaves like an executive coach and a trusted mentor:
- **One question at a time.** Never fifty questions on one screen. Ask, wait, listen, respond,
  move forward.
- **Natural, never robotic.** After each answer Tony acknowledges warmly, then continues.
- **Unhurried.** "No wrong answers. Take all the time you need." Progress is shown (Question N of
  7, a progress bar), and the user can go **Back**, **Save & Exit**, or **Resume Later** at any
  time — nothing is lost.

## What it asks (the shape, not the script)
Welcome, then **seven essential questions**: what to call you; the three most important areas of
your life; your biggest goal for the next 6-12 months; the biggest challenge in your way; the
commitments/non-negotiables Tony should protect; what a successful week looks like; and what Tony
should never assume or do without asking. Deeper discovery (five-years-out, the view from age 85,
how you define financial freedom, and the like) moves into future normal conversations - the first
run stays short and calm. See [Onboarding_Stability.md](Onboarding_Stability.md).

## What it produces
The conversation is not a survey that goes nowhere. Tony **distills the answers into Identity** —
the foundation of GIOK — reusing only existing Identity setters, never fabricating:
- **Core Values** ← the three most important areas of your life.
- **Goals** ← your biggest goal for the next 6-12 months (parsed into goal entries).
- **Mission** ← what a successful week looks like to you.
- **Identity Overview** ← a reflection Tony composes *from your own words* (your name, the challenge
  in your way, what to protect, and what never to assume without asking).

Deeper Identity fields (Vision, Legacy, Annual Theme) are left for future normal conversations, so
the first run stays short. The raw answers always remain in the conversation's own state file.

Crucially, this is **not duplication.** The conversation's working answers live in its own state
file; the *meaning* is written into `identity/*.json`, which Identity owns. The app reads Identity,
not the transcript. (See [Identity.md](Identity.md) and Single Source of Truth in
[02_Core_Principles.md](02_Core_Principles.md).)

## The close
When the last question is answered, Tony says:

> "Thank you. I know enough to begin helping. Let's build your operating system."

Only then does the **Home dashboard** open. The First Conversation is accessible only until it's
completed; afterward the dashboard is the landing page, and the conversation can be re-run any time
from **Settings → Restart First Conversation.**

## Architecture (why it's built to last)
- **Engine separate from UI.** The conversation steps, state, completion, and — importantly — the
  **response generator** live in `core/first-conversation.ps1`. The UI only renders from the
  engine.
- **The response generator is the seam.** Today it returns warm, human acknowledgments. A future
  AI replaces *only* that function — nothing else changes. Tony's responses are generated, never
  hardcoded, and Tony never fabricates the user's answers.
- **The interview is local only.** No cloud, no external AI, no APIs *during the seven questions*.

## Organizing the answers (Epic 13: optional, consented, off-thread)
The *interview* stays offline. After the last answer, Tony organizes what was shared into the
Understanding Model — and that one step may, **with explicit consent**, use Claude:
- A consent screen appears before anything leaves the machine: *"Tony can use Claude to organize what
  you shared... Nothing will be saved to Identity until you review and approve it"*, with **Use Claude**
  and **Keep Processing Local**. The answers never leave the computer unless the user picks Use Claude.
- Extraction runs **off the UI thread** and is deadline-bounded; the deterministic local engine is the
  **permanent** fallback for no-key, declined consent, timeout, or any failure. The review screen and
  approval flow are identical either way, with one honest line noting who organized it.
- See `Blueprint/Claude_Understanding_Driver.md`. Nothing about the interview, the close, or the
  "distill into Identity only after approval" contract changes.

## Why this matters
First impressions are identity-forming. A user who feels *understood* in their first minute trusts
the product with the rest of their life. That trust is GIOK's real asset — and it starts here, with
a conversation, not a form.
