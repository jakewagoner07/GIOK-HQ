# Onboarding Stability and Length

*A focused fix, not a redesign. Make Tony's First Conversation shorter, calmer, resumable, and
stable - without touching the rest of GIOK.*

Companion to [First_Conversation.md](First_Conversation.md) (the philosophy). This document is the
design contract for the stability + length fix; code follows it.

## Problems observed
1. **Too long.** Welcome + **17** questions = 18 steps. It asks about everything at once.
2. **Crashes while answering.** A save that hits a locked/contended file throws, and the click
   handlers have no protection, so the app dies mid-interview.
3. **Thank You screen freezes.** "Let's build your operating system" runs `Complete-Conversation`
   (several synchronous identity writes) and then builds **Home**, which synchronously assembles the
   full Executive Context *and* fetches the live calendar + combined email (Gmail + Yahoo IMAP) - all
   on the UI thread. The window cannot repaint, so the closing screen appears frozen.
4. **Brief freeze after reopening.** The same heavy Home build blocks the first paint.

## Root causes (precise)
- **RC1 - Length.** `Get-ConversationSteps` hard-codes 17 questions.
- **RC2 - Unguarded, non-atomic saves.** `Save-ConversationState` does a single `Set-Content` under
  `$ErrorActionPreference='Stop'`. A transient lock (AV, OneDrive sync, a prior write still closing)
  throws straight through the WPF click handler -> crash. The write is also non-atomic, so an
  interruption can leave a partial file.
- **RC3 - Silent restart on read failure.** `Get-ConversationState` catches any read/parse error and
  returns a **blank** state (`currentStep=0`, no answers). A transient read failure (or a partial
  file from RC2) therefore looks like a brand-new conversation - onboarding appears to restart and
  the in-progress view loses its place. This violates "never restart unless explicitly chosen."
- **RC4 - Heavy work on the UI dispatcher at the completion boundary.** `Complete-Conversation` +
  `Set-ActiveView 'Home'` build the Executive Briefing (full context assembly + live calendar/email
  fetch) synchronously. That is the Thank You freeze and the post-onboarding startup freeze.
- **RC5 - No double-submit guard.** Next/Finish/Back and the closing button are `MouseLeftButtonUp`
  handlers on Borders. A rapid double-click enqueues two handlers; the second runs after the first
  has already refreshed the view (repointing the shared input/step references), so it advances a
  second time - **skipping a question and blanking its answer**.

## The fix (scope: onboarding only)

### 1. Reduce to a calm 7 (welcome + 7 questions)
Replace the 17 with the essential set. Welcome is not counted; the indicator reads **"Question N of
7"** and the bar tracks questions only.

1. `q_name` - What should Tony call you?
2. `q_areas` - What are the three most important areas of your life right now?
3. `q_goal` - What is your biggest goal for the next 6-12 months?
4. `q_challenge` - What is the biggest challenge currently getting in your way?
5. `q_protect` - What commitments or non-negotiables should Tony protect?
6. `q_week` - What does a successful week look like for you?
7. `q_boundaries` - What should Tony never assume or do without asking?

Deeper discovery (five-years-out, age-85 legacy, financial-freedom definition, etc.) moves into
future normal conversations - not the first run.

**Distillation into Identity (reuse existing setters only; never fabricate):**
- `q_areas` -> Core Values (`Set-IdentityValuesFromText`).
- `q_goal` -> Goals (`Set-IdentityGoalsFromText`).
- `q_week` -> Mission (`Set-IdentityMission`) - the working definition of a good week.
- `q_name`, `q_challenge`, `q_protect`, `q_boundaries` -> composed into the **Identity Overview
  reflection** (`Set-IdentityOverviewReflection`) from Jake's own words, so Tony has them immediately
  without inventing structured records. The raw answers always remain in the conversation state file
  (single source for the transcript). No theme/profile-name change; no auto-created non-negotiables.

This keeps Tony useful immediately (name, values, a goal, a mission, and a short reflection) while
leaving structured capture of non-negotiables/boundaries to the normal, approval-gated flow later.

### 2. Durable persistence (fix crashes + silent restart)
- **Atomic save with rolling backup.** `Save-ConversationState` writes to a temp file, keeps the
  previous good file as `.bak`, then atomically replaces the target. Retries a few times with a
  short backoff on `IOException`. Returns `$true/$false` instead of throwing - **a save failure can
  never crash the interview**; the UI shows a calm inline message and the user can retry.
- **Safe load, no accidental restart.** `Get-ConversationState` retries the read, falls back to
  `.bak` if the primary is unreadable, validates shape, and **clamps** `currentStep`. It only ever
  returns a fresh blank state when there is genuinely no prior file - a transient read error never
  silently resets a real conversation.
- **Save after every completed answer** (already on Next; retained) so progress is never more than
  one answer behind.

### 3. Resume at the next unanswered question
`currentStep` is saved after each answer, so reopening lands exactly where Jake left off. On launch,
the landing view is still "First Conversation" until `completed` is true; resume reads the clamped
`currentStep`. Closing after Q2 reopens at Q3. Nothing is duplicated because answers are keyed by
step id (`Add-Member -Force` overwrites the same key).

### 4. One advance per click (double-submit guard)
A monotonic **navigation generation** counter. Each render snapshots the current generation; every
advancing handler (Next/Finish/Back/closing) is built to check `if (gen != current) return` and then
bump the generation before doing work. The stale second handler from a double-click sees a bumped
generation and no-ops. Deterministic, single-threaded-dispatcher-safe, no reliance on control
disable state.

### 5. Keep the UI responsive: defer heavy provider loading until Home is visible
- The First Conversation view itself already touches **no** providers and builds **no** Executive
  Context - preserved and asserted.
- The completion boundary becomes instant: the closing handler completes the conversation (safe
  saves) and navigates to Home; **Home paints immediately** with a light "Preparing your briefing..."
  placeholder, then the Executive Briefing (full context + live calendar/email fetch) is built on a
  background dispatcher tick and swapped in. Heavy providers load **after** Home is on screen.
- **Headless parity.** In `-Screenshot` mode there is no message loop, so a `HeadlessRender` flag
  makes the briefing build synchronously (screenshots keep rendering the real card). Interactive
  launches get the deferred, non-blocking build.

This single change fixes both the Thank You freeze and the post-onboarding startup freeze, and it
measurably improves first paint on every Home load - without altering Home's content or layout.

## Invariants (must hold)
- No new features beyond onboarding stability + question reduction; no redesign of the rest of GIOK.
- Single Source of Truth preserved: conversation state in `first_conversation.json`; distilled
  meaning in `identity/*.json` (Identity owns it); no duplicate stores.
- Never fabricate answers, goals, dates, or values; distillation uses only Jake's words via existing
  setters.
- Never restart onboarding unless Jake explicitly chooses **Settings -> Restart First Conversation**.
- No Gmail/Yahoo/Calendar/CRM/Workforce/Priority/Timeline/Executive-Context work during onboarding.
- The tracked-runtime-store hygiene issue is **out of scope** here (tracked separately).

## Verification
Fresh first launch shows exactly 7 questions with a correct "Question N of 7" indicator; save after
each answer; close after Q2 and reopen at Q3 with no duplication; rapid double-click neither
duplicates nor crashes nor skips; a simulated temporary file lock shows a friendly message instead
of crashing; completing the interview reaches a responsive Thank You screen that transitions cleanly
to Home; restarting after completion does not rerun onboarding; Restart First Conversation works only
when explicitly selected; heavy providers do not load during onboarding; startup is measurably
faster; and every existing subsystem still works. All onboarding-state tests run against an isolated
temp state file - Jake's real `first_conversation.json` is never touched.

## Related
- [First_Conversation.md](First_Conversation.md) - the philosophy this preserves.
- [Identity.md](Identity.md) - the owner of the distilled meaning.
- [04_Home.md](04_Home.md) - the view whose first paint is now deferred-and-responsive.
