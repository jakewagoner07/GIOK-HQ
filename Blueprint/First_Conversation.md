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
  18, a progress bar), and the user can go **Back**, **Save & Exit**, or **Resume Later** at any
  time — nothing is lost.

## What it asks (the shape, not the script)
Welcome, then seventeen questions moving from the concrete to the profound: who you are, who you
hope to become, what matters most, what success looks like, your goals and challenges, your family
and work, what you're improving, how you define financial freedom and good health, the perfect
year, five years out, the view from age 85, what you'll be proud of, the promises you want to
keep, and anything else Tony should know.

## What it produces
The conversation is not a survey that goes nowhere. Tony **distills the answers into Identity** —
the foundation of GIOK:
- **Vision** ← who you hope to become / your perfect year / five years out.
- **Goals** ← your biggest goals (parsed into goal entries).
- **Mission** ← what success looks like to you.
- **Core Values** ← what matters most.
- **Annual Theme** (placeholder) ← what you're trying to improve.
- **Identity Overview** ← a reflection Tony composes *from your own words*.

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
- **Local only.** No cloud, no external AI, no APIs.

## Why this matters
First impressions are identity-forming. A user who feels *understood* in their first minute trusts
the product with the rest of their life. That trust is GIOK's real asset — and it starts here, with
a conversation, not a form.
