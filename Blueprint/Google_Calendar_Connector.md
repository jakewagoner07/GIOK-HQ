# The Google Calendar Connector (Write) - Epic 17

> GIOK's **first external side-effecting connector**. It gives the Executive Action Engine the
> ability to create, update, and cancel Google Calendar events - and nothing else in GIOK may write
> a calendar. The read-only [Google Calendar Provider](Google_Calendar_Provider.md) is a separate,
> already-live responsibility (scope `calendar.readonly`); this connector is the **write** path
> (scope `calendar.events`). They may share the same Google Cloud desktop client, but they are
> separate consents, separate token stores, and separate responsibilities.

## Why this connector exists (and why Calendar first)

Epics 15/15.1 built the Executive Action Engine as GIOK's **sole execution authority**, and Epic 16A
gave every create a stable pre-allocated id verified by exact identity. The permanent decision at the
end of 16A: *"External connectors (Calendar/Gmail) remain blocked until these guarantees are
exercised against a real side-effecting connector; the local handlers are their template."*

Calendar is the **safer first external write**: a create is **idempotent-keyable** (Google accepts a
client-specified event id) and **reversible** (cancel/delete). Gmail sends are irreversible and have
no natural idempotency key, so Gmail stays blocked until a send-specific contract exists.

## The one permanent flow (no parallel path)

```
Tony / Daily Plan
  -> pending Executive Inbox proposal            (Add-InboxProposal; proposing is not acting)
  -> explicit user approval                      (Approve-InboxItem; the ONLY trigger)
  -> immutable execution intent                  (persisted BEFORE any API call)
  -> Executive Action Engine                     (Invoke-ProposalExecution; sole executor)
  -> Google Calendar connector                   (the registered handler for calendar.* types)
  -> provider event id                           (client-specified deterministic id)
  -> independent read-back verification          (engine-gated; events.get by exact id)
  -> truthful succeeded or failed result
```

**No Calendar write may originate directly from** Tony, Claude, the Daily Plan, the Executive
Briefing, the Executive Inbox UI, a Calendar view, any reasoning provider, n8n, or any
connector-specific helper outside the Action Engine. The connector is a **registered handler**; it is
never called except by the engine's one execution path.

## Architecture and separation of concerns

Module: `tony-alpha/dashboard/core/connectors/google-calendar.ps1` (the connector). It reuses the
shared, provider-neutral OAuth mechanism in `core/google-oauth.ps1` and registers itself with the
engine via `Register-ActionHandler` plus a new **connector-verifier** registration.

Google Calendar API calls live **only** in the connector. They are never embedded in
`action-engine.ps1`, `executive-inbox.ps1`, `tony-ui.ps1`, or any reasoning module.

| Owned by the **Action Engine** | Owned by the **connector** |
|---|---|
| approval validation + **instance binding** | connector-specific payload validation |
| immutable execution intent | the approved Google Calendar request (insert/patch/delete) |
| idempotency (dedup by key) | safe provider result metadata (event id, safe status) |
| state transitions + timeout policy | read-back of the event by exact provider id |
| audit history + retention | reporting connector availability truthfully |
| the **requirement** to verify before success | |
| terminal success/failure | |
| restart recovery (re-verify persisted intent) | |

The connector **may not**: approve proposals, change execution state, mark itself succeeded, write
GIOK business stores, expose credentials, or log private calendar content.

## Supported actions (V1)

Provider-neutral action types routed to this one connector:

1. `calendar.create-event`
2. `calendar.create-focus-block`
3. `calendar.create-follow-up-block`
4. `calendar.protect-family-time`
5. `calendar.update-event`
6. `calendar.cancel-event`

The four create-* types share one create path; they differ only in default title/label and the
Executive Inbox copy. **Out of scope (later extensions):** attendee invitations, recurring-event
editing, conference/Meet links, cross-calendar moves, bulk operations. V1 never adds attendees and
never sends notifications (`sendUpdates=none`).

## Action payloads (provider-neutral contracts)

Create (`calendar.create-event` and the three block variants):
```
{ calendarId, title, start, end, timezone, description?, location?, sourceProposalId, sourceUid }
```
Update (`calendar.update-event`):
```
{ calendarId, eventId, expectedProviderVersion?, changes: { title?, start?, end?, timezone?, description?, location? } }
```
Cancel (`calendar.cancel-event`):
```
{ calendarId, eventId, expectedProviderVersion? }
```

**Validation (before the intent is persisted, so a malformed payload writes nothing) rejects:**
missing title for creates; invalid start/end; end <= start; invalid/unknown timezone; missing
eventId for update/cancel; unsupported fields; empty change set; malformed calendarId; any attempt to
change immutable provider identity (eventId/calendarId in `changes`); and **ambiguous local times
during a daylight-saving transition** unless the offset is explicit. Timezone is **never guessed** -
an absent or unrecognized IANA timezone is a validation failure, not a default.

## OAuth, scopes, and credentials

Installed **desktop app** OAuth 2.0, exactly as the read provider: Authorization Code + **PKCE
(S256)**, a `127.0.0.1` **loopback** redirect, **offline access** (refresh token), least-privilege
scope, revoke on disconnect. The system browser handles sign-in and consent; GIOK never sees the
password. This is the current Google-supported method for installed apps (the OOB flow is retired;
loopback is the replacement).

- **Scope (least privilege):** `https://www.googleapis.com/auth/calendar.events` - create/update/
  delete of events only. **Not** the broader `calendar` scope; **not** `calendar.readonly` (that is
  the read provider's scope). Writing requires this **separate, explicit consent**, distinct from the
  read connection and distinct from Claude reasoning consent.
- **Client credentials:** reuse the same gitignored desktop-app client in
  `providers/calendar.config.json` (`clientId`/`clientSecret`). For an installed app the secret is
  not truly confidential, but it stays local and gitignored regardless. Only
  `calendar.config.example.json` is committed.
- **Tokens:** write-scoped tokens live in their **own** gitignored file
  `tony-alpha/calendar.write.tokens.json` (account-keyed, same shape as `calendar.tokens.json`).
  Keeping write tokens separate from the read tokens makes the write consent independently
  connectable, testable, and revocable, and guarantees a read token can never be used to write.

### Files (local, gitignored)
| File | Contents | Committed? |
|---|---|---|
| `providers/calendar.config.json` | desktop client id/secret (shared read+write) | no - gitignored |
| `providers/calendar.config.example.json` | safe placeholders | yes |
| `tony-alpha/calendar.tokens.json` | read-scope per-account tokens | no - gitignored |
| `tony-alpha/calendar.write.tokens.json` | **write-scope** per-account tokens | no - gitignored |

### Connect / disconnect / revoke / rotate
- **Connect:** Settings -> Google Calendar (Write) -> Connect. Runs the loopback consent for the
  `calendar.events` scope; on success stores the write tokens keyed by the account email.
- **Disconnect:** revokes the refresh token with Google and deletes only that account's write tokens.
  The read connection is untouched.
- **Expired/revoked:** the connector reports `authorization expired` / `permission denied` truthfully
  and calmly; an expired refresh token requires a reconnect. Availability is reported honestly - a
  disconnected or expired write connection means calendar actions are simply unavailable, never
  silently skipped or faked.
- **Rotate credentials:** disconnect (revokes + deletes tokens), replace the client id/secret in the
  gitignored `calendar.config.json`, reconnect. Rotating never requires a code change or a commit.

### Consent separation
Calendar write consent is a distinct event from (a) the Calendar read connection and (b) Claude
reasoning consent. Connecting Calendar for reads or enabling Claude for the Daily Plan never grants
write access. **No calendar data is sent to Claude merely because Calendar is connected.**

## Provider-safe idempotency

Google Calendar accepts a **client-specified event id** on insert (base32hex: lowercase `a-v` and
digits `0-9`, length 5-1024, unique per calendar). GIOK derives a **deterministic** event id from the
execution idempotency key:

```
clientEventId = 'giok' + lowercase-hex( MD5( executionIdempotencyKey ) )     # all chars in [0-9a-v]
```

The execution idempotency key already binds the durable proposal `uid` + content fingerprint (Epic
16A), so the same approved proposal always yields the **same** event id, and two distinct proposals
(even with identical content, reusing an inbox id) yield **different** ids.

Persisted in the **intent, before any API call**: GIOK execution id, proposal uid, the connector
idempotency key, the intended `calendarId`, the **deterministic client event id**, the normalized
`start`/`end`/`timezone`, and the exact verification facts. Because the id is client-specified and
deterministic:

- **Repeated approval, repeated direct invocation, timeout, crash, provider retry, restart recovery**
  all insert with the **same** id. A duplicate insert returns **409 (already exists)**, which the
  connector treats as "already created" and confirms by read-back - **never a second event**.
- The **event title is never identity**; title+date matching is never proof; success is never
  inferred from a search when the exact provider id can be read back.

For **update/cancel**: the exact provider `eventId` is used, and `expectedProviderVersion` (the
event's `etag`/`updated`/`sequence` captured when the proposal was made) is checked by read-back
before applying - a stale update is **rejected**, never silently overwriting a newer external change.

## Execution and verification

**Create:** persist intent -> `events.insert` with the deterministic id -> persist the returned
provider event id immediately -> **read the event back by exact id** (`events.get`) -> compare the
approved facts (title/start/end/timezone) -> the **engine** marks succeeded only after verification.

**Update:** persist intended changes + provider event id -> read back and check
`expectedProviderVersion` -> `events.patch` -> read the event back -> verify the exact intended fields
-> succeed/fail truthfully.

**Cancel:** persist provider event id -> `events.delete` (or patch `status=cancelled`) -> read back
and confirm the event is absent (404) or `status=cancelled` -> succeed/fail truthfully.

Verification **never relies only on the HTTP request returning success**. A connector result claiming
success without a verified provider read-back **fails**. This is enforced by a new engine intent mode
`connector`: `Test-ExecutionIntentApplied` for that mode calls the registered **connector verifier**,
which performs the independent read-back; a missing verifier or a verifier that cannot confirm the
exact event is a hard failure. The engine owns the requirement; the connector owns the read.

## Crash and timeout safety

| Window | Behavior |
|---|---|
| **A** intent persisted, request never sent | recovery reads the provider state; the event is absent -> **failed/retriable**; startup recovery never blindly re-sends |
| **B** provider created, response lost | recovery finds the exact deterministic event id and verifies approved facts -> **succeeded**; no duplicate |
| **C** provider updated, response lost | recovery reads the exact event id and verifies the intended changes -> **succeeded** if they landed |
| **D** provider cancelled, response lost | recovery verifies the cancelled/deleted state -> **succeeded** |
| **E** timeout while the request continues | the caller gets a truthful timeout/non-terminal state; a late completion cannot update a **newer** execution (guarded by execution id + idempotency key); restart reconciliation resolves the exact id safely |

We **do not** claim that abandoning a local worker cancels the in-flight HTTP request. The connector
uses a bounded `-TimeoutSec`; if it times out, the execution is left non-terminal and reconciled by
the exact provider id on the next run - never re-sent blindly.

## Approval-instance binding (closes NB-1)

Before any external action, approval binds to the **specific proposal instance**, not only its
content. The approval metadata carries `uid`, `id`, `fingerprint`, `type`, `approvedBy`, `approvedAt`,
and the engine binds them: a reused approval object presented with a **different uid** is **rejected**;
editing a proposal invalidates the prior approval (content fingerprint changes); a direct caller may
not reuse one instance's approval to execute another. This is a **permanent Action Engine guarantee
for external connectors** (and it strengthens local actions too).

## Privacy and audit

The execution log stores only what is necessary to reconstruct and verify an external action. It
**never** stores OAuth tokens, authorization headers, full API responses, attendee email addresses,
unnecessary private descriptions, or prompts/Claude responses. Safe audit fields: execution id,
proposal uid, action type, connector id, a **safe representation of the calendar id**, the provider
event id, state transitions, timestamps, a **safe provider error class**, the verification outcome,
and redacted result metadata. The execution-log private-content policy is updated to cover external
payloads before any are recorded: event titles/descriptions are **redacted** from audit detail; only
the deterministic (non-sensitive) event id and safe calendar representation are kept.

## Permanent decisions (Epic 17)

- **Google Calendar writes occur only through the Action Engine.** No parallel path exists.
- **Approval binds to the exact proposal instance** (uid + id + content fingerprint), not content
  alone.
- **Create actions use provider-safe idempotency** - a deterministic client-specified event id -
  never title/delta inference.
- **Success requires an exact provider event-id read-back.** An HTTP 200 without verified provider
  state is a failure.
- **Recovery reconciles by exact provider id; it never blindly repeats a write.**
- **Calendar precedes Gmail** as the first external connector (idempotent + reversible first).
- **Gmail remains blocked** until a send-specific idempotency/verify contract exists.
- **Least-privilege write scope** `calendar.events`, on a separate consent and a separate token store
  from the read provider; no calendar data flows to Claude merely because Calendar is connected.

## Related
- [Executive_Action_Engine.md](Executive_Action_Engine.md) - the sole execution authority this plugs into.
- [Google_Calendar_Provider.md](Google_Calendar_Provider.md) - the read-only sibling (separate scope/consent).
- [Multi_Account_Google.md](Multi_Account_Google.md) - the account-keyed OAuth store this reuses.
- [Daily_Executive_Plan.md](Daily_Executive_Plan.md) - where calendar write *recommendations* become pending proposals (never writes).
