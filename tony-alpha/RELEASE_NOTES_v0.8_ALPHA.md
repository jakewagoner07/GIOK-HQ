# GIOK — Release Notes · v0.8 Alpha

**"Sunday Night Usability" build.** The goal of this release was not new features — it was to make
GIOK something Jake can genuinely begin using **every day**. Focus: obvious, beautiful, simple,
time-saving, and better with Tony.

Launch via the **GIOK** desktop icon. Local-first, dark executive UI, no cloud, no external AI.

---

## What's in GIOK today
A complete daily operating rhythm, built across Project Diamond and the prior sprints:

- **Tony's First Conversation** — GIOK starts with a conversation, not configuration. One question
  at a time; answers distilled into Identity.
- **Morning Experience** — the premium "first minute": greeting, a quote, why-this-today, the day's
  principle and focus, and **Begin My Day**.
- **Home / Morning Briefing** — Tony's executive briefing answering "What should I focus on today?"
- **Identity** — the foundation: Vision, Goals, Core Values, Mission, Legacy, Annual Theme, Journal,
  Timeline (Vision & Goals live here).
- **Capture** — capture anything in seconds (window, `capture:` command, Home button); Inbox +
  processing into Action Items / Goal / Reminder.
- **Action Items** — interactive tasks (check, add, delete, archive) backed by JSON.
- **End of Day Audit** — the signature evening ritual: scores, wins, incomplete-item triage,
  non-negotiable streaks, reflection, Tony's summary, and history.
- **Mission Control** — a dense second-monitor overview; opens in its own window.
- **"Ask Tony" command bar** (Ctrl+K), **multi-window** popouts, and a **theme system**.

---

## New in v0.8 (this build)

### Usability & navigation
- **Sidebar reorganized for daily use.** Daily tools grouped at top — Home, End of Day Audit,
  **Capture (now in the sidebar)**, **Action Items (now in the sidebar)**, Identity, Mission
  Control, AI Workforce, Tony.
- **"COMING SOON" group.** Not-yet-built workspaces (Non-Negotiables, Family, Health, Financial,
  Agency, Home Projects, Learning) are dimmed under a clear divider, so nothing feels broken.
- **Fixed the duplicate "Home" label** — the second is now clearly **Home Projects**.

### Polish
- **Immersive onboarding & morning.** The utility toolbar is hidden on **First Conversation** and
  **Morning Experience** for a cleaner, focused screen.
- **First Conversation flow** reads more naturally — Tony's acknowledgment no longer repeats his
  name label before each question.
- **Version bumped to 0.8 Alpha** across the app.

### Fixes
- Cleaned up dead/confusing logic in the End of Day Audit win-removal path (and it now stamps
  `savedAt`).
- Consistent placeholder labeling and dark-theme contrast across screens.

### Docs
- Added **TESTING_CHECKLIST.md** (run it Sunday night), **KNOWN_ISSUES.md** (honest limitations),
  and these release notes.

---

## Explicitly not in this release (by direction)
Cloud, mobile, Gmail, Calendar, GHL, voice, and new workspaces. Deferred on purpose to keep the
focus on daily usability.

## How to start
1. Double-click the **GIOK** desktop icon.
2. Complete **Tony's First Conversation** (it's the landing screen on first run).
3. From then on, GIOK opens to your **Morning Experience → Home**. End each day with the **End of
   Day Audit**.

Run `TESTING_CHECKLIST.md` to confirm everything works on the machine before relying on it.
