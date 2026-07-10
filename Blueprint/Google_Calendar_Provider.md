# The Google Calendar Provider (Read-Only)

## Tony understands your schedule

*Project Diamond, Sprint D14. Tony's first Google integration - and the pattern for Gmail and every
Google provider that follows.*

Implementation: `tony-alpha/dashboard/providers/google-calendar-provider.ps1`, on the reusable
live-provider registry `core/live-providers.ps1`.

## Purpose

So Tony can understand Jake's real schedule and use it in daily planning. Jake asks Tony about his
day - "What's on my calendar today?", "When's my next appointment?", "Do I have time for a one-hour
prospecting block tomorrow?" - and Tony answers from live calendar data, in his own voice. **Tony
owns the conversation; Google Calendar owns the data; the provider is an implementation detail.**
Jake never feels like he's operating the Google Calendar API.

## Read-only boundary

**This provider is READ ONLY.** It retrieves and explains calendar information. It never creates,
edits, moves, accepts, declines, or deletes events. The only scope requested is
`https://www.googleapis.com/auth/calendar.readonly`. Write access is out of scope and would require
a **separate, explicit approval** in a future sprint (see below).

## OAuth architecture

Google OAuth 2.0 for an **installed desktop app**:

- **Authorization Code flow with PKCE** (S256 code challenge).
- **System browser** for Google sign-in and consent - Tony never sees the password.
- **Loopback redirect** - a `127.0.0.1:<free-port>` socket captures the one-time code, responds with
  a "you can close this window" page, and closes.
- **Offline access** (`access_type=offline`, `prompt=consent`) so a **refresh token** keeps the
  connection alive without re-signing-in each time.
- **Minimum read-only scope** only; never write.
- **No service account** - this is a personal user's calendar.
- The desktop-app client id/secret live in a **gitignored** `calendar.config.json` (for installed
  apps the secret is not truly confidential; it stays local regardless). Tokens live in a gitignored
  `calendar.tokens.json`.

## Provider contract

`Get-Calendar` returns structured information (or an honest failure - never a guess):

- **Provider status**, **connected account email** (the primary calendar id), **timezone**,
  **calendars available**, and a **timestamp** / **error state**.
- **Events** (deduped across calendars, cancelled ones skipped), each with: event id, calendar id,
  title, start, end, all-day flag, location, description summary, organizer, attendee count, the
  user's response status, meeting link (when present), and current/upcoming/completed state.
- **Next event**, **today's event count**, **tomorrow's event count**, **free-time windows**, and
  **scheduling conflicts**.

It implements the reusable `relevant` / `query` / `status` contract and registers with the
live-provider registry, so **Tony Brain consumes it generically** - the Brain never names "calendar"
or takes a direct dependency on this file.

## Data flow

1. Jake asks a schedule question in Talk with Tony (or anywhere the Brain runs).
2. Tony Brain calls `Get-RelevantLiveSignals`; the Calendar Provider says "relevant" and is queried.
   A non-calendar question queries nothing - no wasted network, no background monitoring.
3. `Get-Calendar` fetches an ~8-day window across the selected calendars (read only), builds the
   structured contract, and computes next event, counts, free windows, and conflicts locally.
4. The structured data flows into the request context; the AI provider **answers the calendar
   question first, naturally and specifically (dates/times only from the data - never invented),
   then adds brief executive guidance if it fits** ("your clearest block is 7:30-9:30 AM, so I'd
   protect that for prospecting"). Ambiguous wording gets one concise clarifying question.

## Calendar Intelligence (D15)

`Get-CalendarInsights` turns the fetched events into *the day at a glance* - pure, deterministic
logic included in the `Get-Calendar` contract as `insights`:

- **First meeting** and **last meeting** (today's earliest start / latest end).
- **Total meetings** today (timed events; **all-day events are not counted** - they don't consume
  focus time).
- **Free focus blocks** (from `Get-GCalFreeWindows`) and the **longest** one.
- **Busy minutes** today, and a **meeting-heavy** flag (>= 4 meetings).
- **Meeting-heavy days** across the fetched window (which upcoming days are >= 4 meetings).

These feed **Tony's Executive Briefing**: a calm "Today's Schedule" line ("2 meetings today,
starting with the Miller renewal call at 10:00 AM; the last wraps up by 3:00 PM") plus one piece of
guidance (protect the clearest focus block, or - on a meeting-heavy day - protect the gaps for
recovery). The briefing consumes this signal **only when Calendar is connected** (a sanctioned
"briefing requests a calendar signal" trigger) - it is never fetched on a disconnected or unrelated
render.

## Executive Context

Calendar is an **optional live signal**, passed into the Executive Context (a one-line note in the
summary) exactly like weather - never auto-fetched on every screen render. It is fetched only when:
the question is calendar-relevant, a future briefing explicitly requests it, the user clicks Refresh,
or a future scheduler asks. When present it can influence daily priorities, workload assessment,
available focus blocks, meeting prep, and Family-before-Financial conflicts - but only when actual
calendar data clearly supports it.

## Security and privacy

- **Read-only** scope; no write, ever, this sprint.
- `calendar.config.json` (client id/secret) and `calendar.tokens.json` (access + refresh tokens) are
  **gitignored, local, and never printed, committed, or logged**. Only `calendar.config.example.json`
  (placeholders) is committed.
- Diagnostics log **states and counts only** - never a token, code, or payload.
- Tony never exposes OAuth internals, tokens, client secrets, provider implementation, or raw API
  data to the user.
- Disconnect **revokes the refresh token** with Google and deletes the local token file.

## Failure behavior

Honest, always - and it never guesses or falls back to sample events:

- Not connected -> "Google Calendar is not connected yet."
- Expired auth -> "Your Google authorization expired and needs to be renewed."
- 403 -> "I can reach Google Calendar, but the request was denied."
- Network down -> "I couldn't retrieve the calendar because the network is unavailable."

## Future write capabilities (separate approval required)

Creating, editing, moving, or responding to events is deliberately **not** in this sprint. Any write
capability will be its own sprint with its own consent: a broader scope, an explicit permission
model (like Memory With Permission), and a clear confirmation before any change - Tony proposes, Jake
approves.

## How this becomes the pattern for Gmail and other Google providers

Gmail, Google Drive, and more follow this exact shape: a Desktop-app OAuth client with a
minimum-necessary read-only scope, PKCE + loopback + offline refresh, a gitignored config/token pair,
the `relevant`/`query`/`status` contract, registration with the live-provider registry, a structured
contract Tony explains, and a Settings card with Connect / Test / Disconnect. Add the provider; the
Brain, Executive Context, and Settings consume it without changes.

## Constraints honored

No calendar writes, no Gmail, no GoHighLevel, no cloud sync, no service accounts for a personal
calendar, no duplicate event storage, no hidden background monitoring, no automatic actions, no
registry redesign.

## Related
- [Weather_Provider.md](Weather_Provider.md) - the same live-provider architecture, one layer simpler.
- [Tony_Brain.md](Tony_Brain.md) - consumes calendar generically via the registry.
- [Executive_Context_Engine.md](Executive_Context_Engine.md) - takes calendar as an optional signal.
- [Tony_Memory_With_Permission.md](Tony_Memory_With_Permission.md) - the consent model any future write capability will mirror.
