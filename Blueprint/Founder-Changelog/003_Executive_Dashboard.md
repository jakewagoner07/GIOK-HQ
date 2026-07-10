# 003 — The Executive Dashboard

**Date:** 2026-07-08 → 2026-07-09
**Version:** 0.4 → 0.6 Alpha (Sprints Alpha, Bravo, Charlie, Delta, Golf, Hotel)

## Problem
A registry in a repo is a tool for a developer, not a command center for an operator. Jake needed
something he'd actually *open every morning* — a real application that felt like his headquarters,
not an admin panel. And it had to prove GIOK could exist as a product at all, not just a folder.

## Decision
Build a real desktop application and evolve it, sprint by sprint, into a premium executive
command center:
- **Alpha** — the first working desktop app (PowerShell + WPF, since no Node/Python was installed).
- **Bravo** — a silent launch (no console window) so it felt native.
- **Charlie** — hub navigation across Agents, Issues, Action Items, Weekly Review, Roadmap.
- **Delta** — the GIOK **theme system** (branding as a swappable layer) and GIOK branding.
- **Golf** — the **dark executive theme** as default, plus the first "Ask Tony" command bar.
- **Hotel** — **multi-window Mission Control** for second-monitor situational awareness.

## Reasoning
- **The core stays UI-agnostic; the UI is just a renderer.** The app reads the registry and the
  JSON files live — a desktop shell, and later a web/mobile client, are all just renderers of the
  same truth. That decision (made before the first pixel) is why every later feature was additive,
  not a rewrite.
- **Branding is a layer, never a dependency.** The theme system means functionality never relies
  on branding; a `theme.json` swap re-skins the whole app (dark by default, light possible later).
- **Premium feel is a product feature, not vanity.** GIOK should feel like a sharp chief of staff's
  cockpit, calm and dark, so Jake *wants* to open it. A tool that's a chore to look at won't get
  used, and an unused command center helps no one.
- Mission Control exists because awareness shouldn't require clicking through tabs — leave it on a
  second screen and *feel* the state of the operation.

## Lessons Learned
- **Constraints picked the stack.** No Node, no Python → PowerShell + WPF. The constraint turned
  out to be a gift: zero-install, native windows, and headless PNG rendering for verification.
- **A "hang" is usually a masked exception.** A headless render that hung was actually a modal
  error dialog blocking forever. We hardened the startup so screenshot-mode errors print instead of
  block — a whole class of silent failure, gone.
- **Encoding is not cosmetic.** Emoji and smart punctuation literals broke Windows PowerShell 5.1
  parsing. The fix — build non-ASCII at runtime (`ConvertFromUtf32`, `\u` escapes, `\p{Pd}`) — kept
  the source portable and is now a standing rule.
- **Read-only snapshots protect the single source of truth.** Popped-out windows render snapshots,
  never editable second copies, so a second monitor can never fork the truth.

## Future Ideas
- The command bar as the seed of a real conversational Tony.
- Desktop-icon launch → the on-ramp to a future web and mobile GIOK.

## Related Blueprint Documents
- [08_Mission_Control.md](../08_Mission_Control.md) — the situation room.
- [10_Design_System.md](../10_Design_System.md) — dark theme, color, components.
- [11_Mobile_Vision.md](../11_Mobile_Vision.md) — where the renderer goes next.
