# Yahoo Mail Provider — a second communication backend behind Sam

**Epic 8.** Sam is formally **Head of Communications** — *she* ensures no important communication is
missed, **regardless of where it originated**. Yahoo Mail joins Gmail as a second **vendor backend**
behind the **one** provider-neutral communication signal. Sam never learns "Yahoo" or "Gmail"; she reads
the single normalized model and gives Tony **one combined report** that still remembers where each
message came from.

## Official Yahoo authentication (confirmed from Yahoo Help, July 2026)

Verified against Yahoo's official help pages — not from memory:

- **Protocol:** read-only **IMAP over SSL**. Incoming server **`imap.mail.yahoo.com`**, port **`993`**,
  **SSL required = Yes**. *(Source: [IMAP server settings for Yahoo Mail](https://help.yahoo.com/kb/imap-server-settings-yahoo-mail-sln4075.html).)*
- **Auth method:** a Yahoo **third-party App Password** — a randomly generated code created at Yahoo
  Account Security → **Create app password** (under *External connections*). A third-party app that does
  not use Yahoo's own sign-in page **cannot use the regular account password**; the app password is the
  documented method. *(Source: [Generate and manage 3rd-party app passwords](https://help.yahoo.com/kb/SLN15241.html).)*
- **OAuth:** Yahoo's mail-client help offers **no OAuth path** for third-party IMAP mail apps; the
  documented, appropriate, minimal-access method for a local desktop reader is **App Password + IMAP**.
  (Yahoo OAuth exists only for registered web apps via Yahoo Developer — heavier, web-oriented, and
  unnecessary here.) So GIOK uses **App Password + read-only IMAP**, not OAuth.
- **Security notes:** an app password stays valid even after the main password changes, and is revoked
  only by deleting it in Yahoo Account Security. No documented IMAP rate limits; standard fair-use.
- **What GIOK stores:** only the Yahoo email address + app password, in the **gitignored**
  `yahoo.config.json` (same private-local pattern as `gmail.config.json`). GIOK never prompts for or
  types the password — Jake pastes it into the local file, exactly like the Gmail client id/secret.

## Architecture (one signal, two backends, one summary)

```
Gmail backend (OAuth)  ─┐                              ┌─ Sam reads ONE normalized signal
  Get-Email  ───────────┤                              │  (never learns the vendor)
                        ├─ core/communications.ps1 ────┤
Yahoo backend (IMAP)  ─┘   Get-Communications:         └─ Tony gets ONE combined report,
  Get-YahooMessages       merge normalized messages       still tagged by account + provider
  (read-only EXAMINE)      -> ONE Get-ExecutiveEmailSummary
```

- **`providers/yahoo-provider.ps1`** — the Yahoo vendor backend. A minimal **read-only IMAP client**
  (pure .NET `TcpClient`+`SslStream`, no external packages) that `EXAMINE`s INBOX (read-only) and fetches
  **headers only** with `BODY.PEEK[HEADER.FIELDS (...)]` — so a message is **never marked seen** and no
  body is downloaded. It normalizes each message into the **same** provider-neutral shape Gmail produces
  and tags it `provider = 'yahoo'`. It contains **no summary logic** — only fetch + normalize.
- **`core/communications.ps1`** — the **provider-neutral aggregator**. `Get-Communications` collects
  normalized messages from every connected backend (`Get-Email` for Gmail, `Get-YahooMessages` for
  Yahoo), **merges them**, and runs the **existing** `Get-ExecutiveEmailSummary` **exactly once**. It
  registers the generic **`email`** live signal (moved here from the Gmail provider) and exposes
  `Get-CommunicationsStatus`. There is **no second Email Intelligence engine and no second Executive
  Email Summary** — merge happens only here, at the provider-neutral layer.
- **Sam** stays provider-neutral: `Get-WorkforceEmail` now reads the **combined** signal, so her one
  report spans all inboxes and her proposals (Epic 6) flow unchanged into the Executive Inbox.

### What is NOT touched
Email Intelligence (`Get-ExecutiveEmailSummary`) is unchanged. The Workforce Engine and Executive Inbox
are unchanged. Gmail keeps its own `Get-Email`/`Get-GmailStatus` (its only edits: tag messages
`provider='gmail'`, and hand the `email` signal registration to the aggregator). No new tab, no new
dashboard, no new store.

## Normalized model (Yahoo → the same shape as Gmail)

Each Yahoo message maps to the shared model, preserving provenance:
`id`, `threadId` (thread/conversation identity where available), `messageId` (RFC822 Message-ID, used to
dedupe across accounts/providers), `sourceAccount` (the Yahoo address), **`provider = 'yahoo'`**, `from`,
`fromName`, `subject` (**RFC 2047 decoded** — `=?UTF-8?Q?…?=` / `?B?` subjects are decoded to plain
text by the provider-neutral `ConvertFrom-MimeSubject`, shared with Gmail), `snippet` (empty in V1 —
metadata only), `date` (IMAP `INTERNALDATE`), `unread` (absence of the `\Seen` flag), `important`,
`fromMe`, `toMe`, `promo`, `bulk`, `invite`, `hasAttachments` (attachment metadata), `labels`. **Bodies
are never fetched** in daily mode — everything is classified from headers + flags, which the existing
engine already does. Sam's proposals carry the **provider + source account** in their evidence
(e.g. `[Yahoo - jake.wagoner@yahoo.com] From Mike: Policy documents needed`) — never a token or password.

## Sam's combined report
Sam gives Tony **one** communications read across every inbox, e.g. *"Sam reviewed three inboxes — two
messages need attention, one person is waiting for a reply, and the rest can wait."* Each surfaced item
keeps its **account + provider**, so Tony can say which calendar/inbox it came from. Sam may create
Executive Inbox proposals for a **communication follow-up, action item, clear deadline, explicit
commitment, or meeting invitation**, and **ignores** spam, promotions, newsletters, automated
notifications, duplicates, and anything already represented by an active Action Item or pending proposal
(the Epic 6 gate, unchanged).

## Daily vs. Historical
- **Daily Operations Mode** (default): `Get-YahooMessages` reads **new/unread + recent** mail (bounded,
  capped, read-only) and feeds the combined summary. This is what runs when Tony reviews communications.
- **Historical Search Mode**: `Search-YahooMail` / `Search-Communications` run **only when Jake
  explicitly asks** ("find the email from the adjuster in March"). It searches older mail read-only,
  returns evidence, and **never** auto-scans the full mailbox or creates a proposal without showing the
  evidence and requiring approval. It is not wired to any automatic trigger.

## Security
Credentials (`yahoo.config.json`) are **local and gitignored** — only `yahoo.config.example.json` is
tracked. **Never logged:** the app password, message contents, or unnecessary personal data. Diagnostics
carry only **provider name, states, counts, timing, and a safe error class** (`not-configured`,
`auth-failed`, `network-error`, `denied`). **Read-only always** — `EXAMINE` + `BODY.PEEK`, never
`STORE`/`APPEND`/`EXPUNGE`/`COPY`/`MOVE`/`DELETE`/flag changes. Minimum access: headers + flags only.

## What this epic does NOT do
No OAuth for Yahoo (not the documented path) · no Outlook/M365/SMS/voicemail/Slack/Teams/social (named
for the future, not built) · no Yahoo-specific logic inside Sam · no second intelligence engine or
summary · no writes of any kind · no new tab.

## Related
- [Gmail_Provider.md](Gmail_Provider.md) — the peer backend and the normalized-message pattern.
- [Workforce.md](Workforce.md) — Sam, Head of Communications (provider-neutral).
- [Workforce_Activation.md](Workforce_Activation.md) — how Sam's proposals reach the Executive Inbox.
- [Multi_Account_Google.md](Multi_Account_Google.md) — merge/dedupe at the intelligence layer (same principle).
