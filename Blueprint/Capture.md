# Capture — Evolution Through Version 3

*Companion to [05_Capture_System.md](05_Capture_System.md), which defines the philosophy. This
document traces how Capture is actually built, version by version.*

> **Your brain is for thinking, not remembering.** Capture's job is to remove information from
> the mind and safely store it — instantly, with no decision required. Organize later.

## The permanent contract
- **Capture first, organize later.** No required fields, ever.
- **One inbox, one source of truth** (`capture.json`). Every channel writes here.
- **Nothing is auto-deleted, nothing is lost.** Items wait in the Inbox until processed.
- **Capture is separate from Action Items.** Different file, different lifecycle. A capture may
  *become* a task, but it is not one until converted.

## Version 1 — Foundation *(built in Sprint Juliet)*
The capture skeleton exists and works locally:
- **Capture window** — a dedicated window: free text + optional category (Note, Task, Idea,
  Reminder, Journal, Shopping, Home, Family, Business, Health, Financial, Learning). No required
  fields.
- **`+ Capture Something`** — a prominent primary action on Home; the Capture workspace/Inbox in
  the sidebar.
- **Command-bar capture** — `capture: <text>` drops straight into the Inbox.
- **`capture.json`** — source of truth. Each item stores: id, timestamp, text, category, status,
  createdFrom, processed, convertedTo, notes, tags.
- **Inbox + processing** — Mark Processed, Convert to Action Item (real), Convert to Goal /
  Reminder (placeholder destinations), Archive, Delete. The conversion *architecture* exists even
  where destinations are stubs.
- **Home surfaces** — Today's Captures, Unprocessed Captures, Recent Captures.

## Version 2 — Effortless & Everywhere
Capture becomes frictionless and begins to organize itself:
- **More channels into the same inbox:** voice (transcribed), email (forward/BCC), photo (with
  text extraction), clipboard, Android share.
- **Tony-assisted routing:** Tony reads each capture and *suggests* a type + destination + due
  date, with a reason. Jake confirms or corrects; Tony learns from corrections.
- **Real conversion destinations:** Goals and Reminders become first-class stores, so
  "Convert to Goal/Reminder" stops being a placeholder.
- **Smart inbox:** grouping, quick triage, and "process to zero" flows.

## Version 3 — Anywhere & Proactive
Capture is ambient and largely self-organizing:
- **Mobile-first capture:** lock-screen, widget, share-sheet, and **offline** capture that syncs
  later. Voice-first, one-handed, eyes-up (see [11_Mobile_Vision.md](11_Mobile_Vision.md)).
- **Earned auto-routing:** for high-confidence, low-risk categories (shopping, home, ideas), Tony
  files automatically and just tells Jake. Ambiguous or consequential items stay confirm-first
  (People First + AI Assists Humans).
- **Future surfaces:** watch and widget capture; camera-to-capture for receipts, whiteboards, and
  cards.
- **Capture feeds memory:** captures become a primary input to Tony's structured memory (see
  [Tony_Memory.md](Tony_Memory.md)) — people mentioned, ideas, preferences, patterns.

## Guardrails that never change
- Capture never blocks on network or AI — the item is saved first, enriched after.
- The inbox is honest: unrouted items are visibly waiting, never silently dropped.
- Routing is reversible; nothing is trapped.
- Capture writes to the single source of truth and is never duplicated across channels.

Capture is the front door of GIOK. If it stays frictionless and honest, everything downstream —
tasks, goals, memory, coaching — has something true to work with.
