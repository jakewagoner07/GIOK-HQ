# Multi-Account Google Integration (Read-Only)

## One Tony, many mailboxes and calendars

*Project Diamond, Sprint D17. Tony reads more than one Google account through the SAME Calendar and
Gmail capabilities - business and personal, side by side - and combines them into one schedule and
one Executive Email Summary. Never a provider per account.*

Implementation:
- `tony-alpha/dashboard/core/google-oauth.ps1` - shared, now **account-aware** OAuth store.
- `tony-alpha/dashboard/providers/google-calendar-provider.ps1` - multi-account Calendar.
- `tony-alpha/dashboard/providers/gmail-provider.ps1` - multi-account Gmail.
- `tony-alpha/dashboard/core/email-intelligence.ps1` - the provider-neutral merge point for email.

## The rule: one provider, many accounts

There is still exactly **one Calendar provider and one Gmail provider**. Each serves *all* connected
Google accounts. Connecting a second account does not create a second provider, a second registry
entry, or a second briefing - it adds an account to the same store the one provider already reads.

## Per-account token storage

Each service keeps **one gitignored token file** holding **all** its accounts, keyed by account
email:

```
calendar.tokens.json / gmail.tokens.json
{ "meta": { "version": "2.0" },
  "accounts": [
    { "id": "jake@giokagency.com",      "access_token": "...", "refresh_token": "...", ... },
    { "id": "jakewagoner...@gmail.com",  "access_token": "...", "refresh_token": "...", ... } ] }
```

Tokens are never printed, committed, or logged. Each account has its own access/refresh tokens;
refreshing or losing one account never touches another.

## Migration (existing single-account users keep working)

The older format was a **flat** single-account file (`{ access_token, ... }`). On first read that is
transparently adopted as one account with the placeholder id `default`; the first live fetch resolves
its real email (Gmail profile / Calendar primary) and **re-keys** it, upgrading the file to the
account list. No re-consent, no manual rebuild - the existing connection simply continues and gains
the ability to add more accounts. (Verified live: Jake's single account migrated seamlessly, refresh
token intact.)

## Connecting, identifying, testing, disconnecting

- **Connect** adds *another* account. The browser uses `prompt=select_account`, so Jake picks which
  Google account each time; the provider resolves its email and stores it keyed by that email.
- **Identify** - every account is shown by its email in Settings (never by token).
- **Test** re-reads all accounts live and shows each account's state.
- **Disconnect** targets ONE account: it revokes that account's refresh token with Google and removes
  only that account's local tokens. Every other account is untouched.

## Source account preserved, merged only at the intelligence layer

Each provider fetches each account **read-only** and tags every normalized event/email with its
`sourceAccount`. The providers do not merge; the **provider-neutral intelligence layer** does:

- **Email** (`Get-ExecutiveEmailSummary`): dedupes the same message across accounts by RFC822
  **Message-ID** (fallback: per-mailbox id), keeping one copy and recording every account it landed
  in, then classifies and summarizes the combined set - one Executive Email Summary.
- **Calendar** (`Get-Calendar` merge step + `Get-CalendarInsights`): dedupes the same event across
  accounts/calendars by **iCalUID** (fallback: id), then computes one set of Calendar Insights. This
  is the "same event on two calendars" case - it appears once, with both source accounts remembered.
  (Bonus: this also collapses an event that a single account carries on several of its own calendars,
  which sharpened conflict detection.)

## Resilience: one bad account never breaks the rest

Every account is fetched in its own try/catch. If one account's authorization has expired (or a
single calendar is unreadable), that account is marked `needs-attention` and skipped; the others
still return data and the summary/briefing is produced from what worked. The contract carries a
per-account `accounts[]` list of states so Settings can show exactly which account needs attention.
(Verified live: with one account's token forced-expired, the other kept working and the summary was
still produced.)

## Executive Briefing / Context

Unchanged in shape - they consume the merged `calendar` and `email` signals exactly as before, so the
briefing naturally reads "22 meetings today" across both calendars and one email summary across both
inboxes. The Claude provider notes when data spans multiple accounts so Tony can say which account
something is on if asked, without ever exposing tokens or implementation details.

## Settings (no new dashboard)

The existing Google Calendar and Gmail cards now list **connected accounts** (each email + a state
pill + a per-account Disconnect button) with an **"Add a Google account"** button and **"Test all
accounts."** No new workspace, no new dashboard.

## Security / privacy (unchanged boundaries)

- **Read-only** still: `calendar.readonly` + `gmail.readonly` only; no write scope, no write call.
  Verified at the code level (all POSTs go only to OAuth token/revoke; data reads are GET).
- Per-account tokens stay in the gitignored token files; only `*.example.json` is committed.
- Diagnostics carry states/counts only - never a token, code, address, subject, or body.
- Message bodies are never fetched (Gmail metadata only).

## Google project note (audience)

To connect accounts **outside** a Google Workspace org (e.g. a personal Gmail alongside a giokagency
account), the OAuth consent screen must be **External** (Testing is fine) with each account added as a
**test user**. An **Internal** consent screen only allows accounts within the org (`403 org_internal`
otherwise). Read-only Gmail is a "sensitive" scope; External + Testing with test users is sufficient
for personal use - Production would require Google verification. Testing mode also expires refresh
tokens after ~7 days per account.

## The pattern generalizes

Because merging happens in the provider-neutral intelligence layer over a normalized shape that
already carries `sourceAccount`, a future Outlook / Microsoft 365 / Yahoo backend that normalizes to
the same shape joins the same merged summary automatically - across providers, not just accounts.

## Constraints honored

One Calendar provider, one Gmail provider; no duplicate providers per account; per-account gitignored
tokens; source preserved on every item; merge only at the intelligence layer; dedupe events and
emails; briefing combines all accounts; account identity visible in Settings; no new dashboard;
read-only throughout; Single Source of Truth, Executive Context, registries, privacy, and Project
Diamond preserved; existing single-account setup keeps working with no manual rebuild.

## Related
- [Google_Calendar_Provider.md](Google_Calendar_Provider.md) - the Calendar capability (now multi-account).
- [Gmail_Provider.md](Gmail_Provider.md) - the Gmail capability + Executive Email Summary (now multi-account).
- [Executive_Briefing.md](Executive_Briefing.md) - where the combined schedule and email summary appear.
- [Tony_Memory_With_Permission.md](Tony_Memory_With_Permission.md) - the consent model any future write capability will mirror.
