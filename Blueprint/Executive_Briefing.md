# The Executive Briefing

## The reason to open GIOK every morning

*Project Diamond, Sprint D11. Not another dashboard - Tony beginning the day as a chief of staff.*

Implementation: `tony-alpha/dashboard/core/executive-briefing.ps1` -> `Get-TonyExecutiveBriefing`,
rendered as the centerpiece of Home (`New-ExecutiveBriefingCard`).

## Purpose

The first thing Jake should see each morning is not a wall of widgets - it's a short, personal
**letter from Tony**. Calm, confident, encouraging, honest, executive, and personal. It tells him
what today is really about, what to protect, and one thing worth noticing - and then it gets out of
the way. The Executive Briefing is meant to be *the* reason to open GIOK: the moment a disciplined
day begins.

## The six sections

1. **Greeting** - time-of-day aware and natural ("Good morning, Jake.").
2. **Today's Executive Summary** - at most three sentences: what matters, the biggest opportunity,
   the biggest risk. No fluff, never alarmist.
3. **Today's Top Three Priorities** - ranked, and each one explains *why* it matters (grounded in a
   real goal when the words line up, otherwise in the annual theme or an honest rank-based reason).
4. **Tony's Observation** - exactly **one**, chosen from the Observation Engine (a celebration, a
   pattern, a gentle concern), with why it matters.
5. **Today's Focus** - a single sentence, shaped by the moment ("...because you protected your
   morning focus before the day filled up.").
6. **One Encouragement** - short, human, never cheesy - a quiet sign-off from Tony.

## Architecture

```
Get-TonyExecutiveBriefing   (core/executive-briefing.ps1)
  -> consumes Get-TonyExecutiveContext ONCE (the single situational-awareness object)
  -> composes the six sections from it - creating NO new context, storing NOTHING
  -> returns a letter MODEL (data only)

New-ExecutiveBriefingCard   (ui/tony-ui.ps1)
  -> renders the model as a letter: greeting, summary, top three, one observation, focus, sign-off
  -> becomes the primary card of Home; everything else supports it
```

The briefing is **prepared before the UI renders**: Home calls `Get-TonyExecutiveBriefing`, which
assembles the situation, then hands a finished model to the card. The card is pure presentation.

## Data flow

1. Home renders and asks for the briefing (passing the current time and the profile name).
2. `Get-TonyExecutiveBriefing` calls the **Executive Context Engine** once - which already folds in
   the Decision Framework, the Observation Engine, Identity, Mission, Goals, Annual Theme, current
   priorities, the Morning Briefing, and the End of Day Audit.
3. The briefing composes six calm sections from that single context - choosing one observation,
   ranking three priorities with reasons, and shaping the focus to the time of day.
4. The card renders the letter. Nothing is written; nothing is cached.

## Design philosophy

- **A letter, not a list.** It reads top-to-bottom in Tony's voice. The point is judgment, not
  data density.
- **Never overwhelming.** At most three priorities, exactly one observation, a three-sentence
  summary. *Never present more than the user can realistically act on.*
- **Never shame, never guilt.** The "risk" sentence is honest but gentle; the observation comes
  from an engine that only celebrates or guides. Tony coaches; he never scolds.
- **Calm and personal.** Time-of-day greeting, a focus tuned to the moment, a human sign-off. It
  should feel like it was written for Jake, this morning.
- **Everything else supports it.** On Home, the briefing is the centerpiece; the separate
  observations row is retired here (its one important item now lives in the letter), keeping the
  screen calm.

## Why it holds Single Source of Truth

The briefing **creates no state**. It consumes the one Executive Context object (which itself only
references sources) and composes text on demand. Two briefings a few hours apart differ because the
*day* differed - the clock moved, the focus shifted - not because anything was stored. No duplicate
storage, no hidden memories, no automatic writes.

## Future enhancements

- **Evening / weekly variants** - the same engine can compose an End-of-Day reflection or a Sunday
  week-ahead letter from the same context.
- **Calendar and weather** - once a provider exists, the summary can weave in the day's first
  commitment or the weather that shapes it.
- **Learned tone** - the greeting and encouragement can adapt to how Jake actually responds over
  time, still deterministic and value-aligned.
- **"Prepared while you slept"** - a future scheduled pass could pre-compose the morning letter so
  it's ready the instant GIOK opens.

## Constraints honored

No new integrations, no cloud, no registry changes, no duplicate storage, no hidden memories, no
automatic writes. Pure read-and-compose over the single source of truth.

## Related
- [Executive_Context_Engine.md](Executive_Context_Engine.md) - the single context the briefing consumes.
- [Tony_Observation_Engine.md](Tony_Observation_Engine.md) - supplies the one observation.
- [Tony_Decision_Framework.md](Tony_Decision_Framework.md) - the judgment folded into the context.
- [04_Home.md](04_Home.md) - the executive home the briefing now anchors.
- [13_Project_Diamond.md](13_Project_Diamond.md) - perfect the experience; this is the morning experience.
