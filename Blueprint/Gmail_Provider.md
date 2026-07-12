# The Gmail Provider (Read-Only) - Executive Email Intelligence

> **Provider-neutral communications (Epic 8):** Gmail is now one **backend** among many behind Sam's
> single `email` signal. It exposes `Get-Email` / `Get-GmailStatus` and tags every normalized message
> `provider='gmail'`; the provider-neutral aggregator (`core/communications.ps1`) merges Gmail with
> **Yahoo** (and future backends) and runs the **one** Executive Email Summary. The `email` live-signal
> registration moved from here to the aggregator (one registrant). Gmail's own mechanics are unchanged.
> See [Yahoo_Provider.md](Yahoo_Provider.md).
>
> **Communications Polish:** subjects are **RFC 2047 decoded** (shared `ConvertFrom-MimeSubject`), and
> carrier/underwriting detection (`Test-EmailCarrier`) now strips benign footer boilerplate ("Privacy
> Policy" and siblings) before matching the `policy` hint — fixing a false positive (a OneDrive "memories"
> notice) without weakening real insurance-policy/underwriting recognition.
>
> **Multi-account (D17):** this one provider reads *all* connected Google accounts and merges them
> into one Executive Email Summary (dedupe by Message-ID). See
> [Multi_Account_Google.md](Multi_Account_Google.md). The description below covers the per-account
> mechanics; multi-account is layered on top without a second provider.

## Tony tells you what deserves your attention

*Project Diamond, Sprint D16. Tony's second Google integration - and the first proof that the
live-provider architecture generalizes. Built deliberately so Outlook, Microsoft 365, and Yahoo can
plug into the exact same shape later.*

Implementation:
- `tony-alpha/dashboard/providers/gmail-provider.ps1` - the Gmail backend (fetch + normalize).
- `tony-alpha/dashboard/core/email-intelligence.ps1` - the provider-neutral Executive Email
  Intelligence engine (classification + summary).
- `tony-alpha/dashboard/core/google-oauth.ps1` - the shared Google OAuth module (also used by future
  Google providers; Calendar migrates onto it next).

## Purpose

So Tony understands Jake's inbox well enough to say **what deserves his attention - and let
everything else wait.** Tony is **not an email client.** He never opens a mailbox UI, never lists
every message, never composes or sends. He produces an **Executive Email Summary**:

> You received 37 emails today. Four require your attention. One person is waiting for a response.
> One calendar invitation arrived. Everything else can wait.

**Tony owns the conversation; Gmail owns the data; the provider is an implementation detail.** Jake
never feels like he is operating the Gmail API.

## Read-only boundary

**This provider is READ ONLY.** It retrieves and understands email. It never composes, sends,
replies, forwards, labels, marks read/unread, archives, or deletes. The only scope requested is
`https://www.googleapis.com/auth/gmail.readonly`. Any write capability (draft, send, RSVP, archive)
is out of scope and would be its own future sprint with its own explicit, consent-gated approval -
mirroring Memory With Permission: Tony proposes, Jake approves, never automatic.

## The architecture: one brain, many mailboxes

The mission was to build Gmail *as if Outlook, Yahoo, and Microsoft 365 will plug into the exact same
architecture*. So the design is three layers, and only the bottom one is Gmail-specific:

1. **Shared Google OAuth** (`core/google-oauth.ps1`) - the installed-desktop-app flow (Authorization
   Code + PKCE S256 + 127.0.0.1 loopback + offline refresh + revoke + a UTF-8 REST GET), parameterized
   by a small config object and a per-provider token path. Single Source of Truth for Google auth.
   The same loopback + PKCE + offline-refresh pattern extends to non-Google mail by swapping
   endpoints and scope.
2. **Provider-neutral Email Intelligence** (`core/email-intelligence.ps1`) - turns a list of
   **normalized messages** into the Executive Email Summary. It knows nothing about Gmail. Any
   backend that produces the normalized shape feeds it unchanged.
3. **The Gmail backend** (`providers/gmail-provider.ps1`) - OAuth config + fetch today's inbox +
   **normalize** each message to the neutral shape + delegate to the intelligence engine. Registers
   as the generic **`email`** live signal (`backend = gmail`).

A future `outlook-provider.ps1` / `m365-provider.ps1` / `yahoo-provider.ps1` implements only step 3:
its own auth endpoints and its own normalizer, then registers as `email` with its own backend tag.
Steps 1-2, the Executive Context, the Executive Briefing, the Settings card pattern, and Tony Brain
all consume it without changes. Jake connects **one** mail account; whichever backend is connected
is *the* email signal.

### The normalized message (what every mail backend must produce)

`id, threadId, from, fromName, subject, snippet, date, unread, important, fromMe, toMe, promo
(marketing category or List-Unsubscribe), invite (carries a calendar invitation), labels`

## What Tony determines (honestly)

Classification is deterministic and uses signals we can actually observe - never an invented
relationship. In priority order:

- **Calendar invitations** - a Google Calendar invite sender, an `Invitation:`-style subject, or a
  `text/calendar` part. A look / RSVP, not a reply.
- **Important contacts / clients** - senders on Jake's own curated `importantContacts` /
  `clientDomains` list (in `gmail.config.json`). Absent a list, Tony does not guess who is a client.
- **Newsletters and promotions (low priority)** - Gmail `CATEGORY_PROMOTIONS/SOCIAL/FORUMS` or a
  `List-Unsubscribe` header. Deliberately **not** `CATEGORY_UPDATES`, where transactional carrier
  mail lands.
- **One-time codes / sign-in notices (low priority)** - verification/login/security codes and
  automated identity mail. Transient machine noise, never attention-worthy - even though they often
  say a code "expires" (which would otherwise trip the urgency heuristic).
- **Carrier / underwriting updates** - insurance vocabulary (underwriting, policy, premium, claim,
  renewal, binder, commission, E&O, ...) or a configured carrier domain. High value for an agent.
  Checked *before* the bulk demotion below, so a carrier notice sent via an ESP still surfaces.
- **Bulk / mailing-list / ESP senders (low priority)** - standard bulk headers (`List-Id`,
  `Feedback-ID`, `Precedence: bulk`, `Auto-Submitted`, and ESP markers like Amazon SES / SendGrid /
  Mailgun). Catches marketing and newsletters that carry no `List-Unsubscribe` UI yet clearly expect
  no reply. A person on a known list still surfaces via the important-contacts path.
- **Urgent** - conservative time-sensitive language (urgent, ASAP, action required, past due,
  deadline, ...), but only from a real person or addressed directly to Jake - not automated blasts.
- **Likely needs a reply** - a real person wrote directly to Jake and it is still unread.
- **Everything else** - read or informational; nothing needed now.

**Alias resolution ("addressed to me").** A GIOK Workspace mailbox often aggregates mail sent to
several of Jake's addresses (personal Gmail, other aliases). A message counts as "to me" when the
`To`/`Cc` contains the connected account, the per-message `Delivered-To` (which names the address
that actually received it), or any alias Jake lists in `myAddresses`. Without this, mail to an alias
would never register as a direct message and the "needs a reply" path could not fire.

**needs attention** = the high-priority set (needs-reply + carrier/underwriting + important-contact +
urgent). Invitations are counted and surfaced separately ("arrived"). The summary also lists at most
**five** items that actually deserve a look - never the whole inbox.

## Data flow

1. Jake asks about email ("anything important in my inbox?", "who emailed me?") or opens Home.
2. Tony Brain calls `Get-RelevantLiveSignals`; the Email Provider says "relevant" and is queried.
   A non-email question queries nothing - no wasted network, no background monitoring.
3. `Get-Email` fetches **today's inbox** (read only): an exact count of messages received since local
   midnight, then metadata for the most recent N (default 60; if the day is bigger, it says so and
   analyzes the most recent - no silent truncation). It normalizes each message and hands them to
   `Get-ExecutiveEmailSummary`.
4. The structured summary flows into the request context. The AI provider gives a short Executive
   Email Summary - what matters, who is waiting, any invitations - then reassures Jake the rest can
   wait. It never lists every email and never invents senders, subjects, or counts.

## The Executive Briefing

The summary folds into Tony's morning letter as a calm **"Today's Email"** line plus one piece of
guidance ("Clear the 3 that need you, then let the rest wait"). Like Calendar, the briefing consumes
this signal **only when Gmail is connected** (a sanctioned "briefing requests an email signal"
trigger) - never fetched on a disconnected or unrelated render.

## Executive Context

Email is an **optional live signal**, passed into the Executive Context (a one-line note in the
summary) exactly like weather and calendar - never auto-fetched on every screen render. It is fetched
only when the question is email-relevant, the briefing explicitly requests it (connected only), the
user clicks Refresh, or a future scheduler asks.

## Security and privacy

- **Read-only** scope (`gmail.readonly`); no send, reply, label, archive, or delete, ever, this
  phase.
- `gmail.config.json` (client id/secret + optional triage lists) and `gmail.tokens.json` (access +
  refresh tokens) are **gitignored, local, and never printed, committed, or logged.** Only
  `gmail.config.example.json` (placeholders) is committed.
- Diagnostics log **states and counts only** - never a token, code, subject, sender, or body.
- Tony never exposes OAuth internals, tokens, client secrets, provider implementation, or raw
  message content beyond the summary he was given.
- Disconnect **revokes the refresh token** with Google and deletes the local token file.
- Message **bodies are never fetched** - only metadata (headers, labels, snippet), which is enough to
  triage and lighter to retrieve.

## Failure behavior

Honest, always - it never guesses or invents messages:

- Not connected -> "Gmail is not connected yet."
- Expired auth -> "Your Google authorization expired and needs to be renewed."
- 403 -> "I can reach Gmail, but the request was denied."
- Network down -> "I couldn't retrieve email because the network is unavailable."

## Setup (Jake, one time)

Reuse the same Google Cloud project as Calendar: **enable the Gmail API**, keep the OAuth consent
screen, create (or reuse) a **Desktop-app** OAuth client, and paste its id/secret into
`providers/gmail.config.json`. Optionally list `importantContacts` / `clientDomains` /
`carrierDomains` there for sharper triage. Then Settings -> Gmail -> **Connect Gmail** (sign-in and
consent happen in the browser; Tony never sees the password). While the OAuth app is in "Testing,"
Google expires the refresh token after ~7 days; publish to Production for durable personal use.

## Constraints honored

No email client, no composing/sending/replying, no labeling or deleting, no summarizing every email,
no new dashboard, no automatic actions, no hidden background monitoring, no cloud sync, no service
accounts for a personal mailbox, no registry redesign. Single Source of Truth: shared OAuth, shared
email intelligence, one generic `email` signal.

## Related
- [Google_Calendar_Provider.md](Google_Calendar_Provider.md) - the sibling read-only Google provider;
  the pattern this generalizes. Calendar migrates onto the shared `google-oauth.ps1` next.
- [Weather_Provider.md](Weather_Provider.md) - the original live-provider architecture.
- [Executive_Briefing.md](Executive_Briefing.md) - where the Executive Email Summary appears.
- [Executive_Context_Engine.md](Executive_Context_Engine.md) - takes email as an optional signal.
- [Tony_Memory_With_Permission.md](Tony_Memory_With_Permission.md) - the consent model any future
  email write capability will mirror.
