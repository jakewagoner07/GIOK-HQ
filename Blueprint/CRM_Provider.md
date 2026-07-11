# CRM Provider — Architecture

> **Status: IMPLEMENTED (read-only), Epic 3 Phase 3.** The design below is now built: a read-only
> **GoHighLevel** backend + normalizer (`providers/gohighlevel-provider.ps1`), the provider-neutral
> book-of-business intelligence layer (`core/crm-intelligence.ps1`), and Randy's specialist
> (in `core/workforce-specialists.ps1`). GoHighLevel is the **first** backend behind the generic `crm`
> signal; a second CRM is a new backend + normalizer with **no change to Randy**. Writes remain a
> later, consent-gated sprint. See **As Built** at the end for the exact endpoints, auth, and honest
> availability.

This design exists to guarantee one thing: that GIOK can read a CRM **without violating any of GIOK's
five permanent invariants** — Project Diamond, the Executive Context, the Decision Framework, Single
Source of Truth, and the Workforce Engine. Each is addressed explicitly below.

---

## The shape of the seam

GIOK already has the exact architecture a CRM needs; the CRM plugs into it with **zero new
mechanisms**. Two existing registries do all the work:

1. **Live-Provider Registry** (`core/live-providers.ps1`) — where a CRM *backend* registers as an
   information source. A provider is an object with `name`, `description`, `relevant(text)`,
   `query(options)`, `status(live)`. The Brain gathers relevant signals generically
   (`Get-RelevantLiveSignals`) with **no per-provider dependency**. Weather, Calendar, and Gmail live
   here today; **CRM becomes the `crm` signal** the same way `email` did.
2. **Workforce Engine** (`core/workforce-engine.ps1` + `workforce-specialists.ps1`) — where **Randy**
   registers as a *specialist* (`Register-Specialist` with `relevant` / `analyze` / `status`) and
   returns the standard report. Randy consumes the normalized `crm` signal; she never touches a CRM
   API.

The result is a clean two-layer split that is the heart of Randy's CRM-agnosticism:

```
  Layer 1 — PROVIDER (per-vendor, changes with the CRM)
    CRM backend (GoHighLevel today; HubSpot/Salesforce/Zoho/Pipedrive/Custom later)
        |  read-only fetch (OAuth or API key)
        v
    Normalizer  ->  maps vendor payload into the NORMALIZED CRM MODEL (below)
        |  registers as the `crm` live provider (relevant/query/status)
        v
    core/live-providers.ps1   ->   the generic `crm` signal

  Layer 2 — SPECIALIST (vendor-neutral, never changes)
    Executive Context folds in the `crm` signal (assembled on demand, never stored)
        |
        v
    Randy (CRM Analyst)  ->  reads normalized nouns only, analyze() -> STANDARD REPORT (scope=crm)
        |
        v
    Tony merges (Workforce Engine)  ->  Decision Framework (final authority)  ->  ONE recommendation  ->  Jake
```

**Randy lives entirely in Layer 2 and never sees Layer 1's vendor.** Swapping GoHighLevel for
Salesforce replaces the backend + normalizer in Layer 1 and changes nothing in Layer 2. *That* is why
Randy is CRM-agnostic.

---

## The Normalized CRM Model (the contract)

The single most important artifact of this design. Every CRM backend must map its vendor data into
these nouns; Randy reasons only on these nouns. This is the vocabulary of a book of business, not of
any product. (Shapes are indicative; the implementation sprint finalizes fields.)

- **Lead** — `{ id, name, source, stage, createdAt, lastContactedAt, owner, status }`
- **Contact / Client** — `{ id, name, type(lead|client), since, lastTouchAt, tags, policyIds[] }`
- **Opportunity (pipeline item)** — `{ id, contactId, title, stage, value, status, openedAt, expectedClose, lastActivityAt }`
- **Policy** — `{ id, contactId, product, carrier, status(active|pending|lapsed), effectiveDate, renewalDate }`
- **Renewal** — `{ policyId, contactId, renewalDate, window, status }` *(derivable from Policy)*
- **Requirement** — `{ id, contactId, policyId, kind(signature|doc|payment|info), description, status(open|cleared), dueAt }`
- **FollowUp / Task** — `{ id, contactId, dueAt, description, status(open|done), overdue }`
- **Appointment** — `{ id, contactId, start, end, title }` *(surfaced to Tony/Ava; Randy never creates one)*

Every normalized object retains a **stable vendor record id** as `sourceId` so Randy's evidence is
traceable and Single Source of Truth holds (GIOK points at the CRM record; it never copies it).

The provider also returns a small **status/health envelope** (`{ ok, connected, accountCount,
fetchedAt, counts, note }`) mirroring how the Calendar/Gmail signals report themselves, so Randy can
degrade honestly.

---

## How each invariant is preserved

**Project Diamond.** Read-only first (writes are a later, consent-gated sprint, mirroring
Calendar/Gmail). Honest by construction: no CRM connected → `unavailable`, never a fabricated
pipeline. Calm, not noisy: the provider normalizes; Randy summarizes; Tony delivers one line — depth
without weight. Nothing ships until it is something Jake would use every day.

**Executive Context (assembled on demand, never stored).** CRM is **one more signal**, folded into the
single Executive Context exactly like `weather`/`calendar`/`email`. The registry holds **no CRM data**
— it fetches on relevance and returns; two reads differ because the book of business changed, not
because anything was cached. No CRM state lives in GIOK.

**Decision Framework (final authority).** Randy **proposes**; Tony **merges**; the Decision Framework
**decides**, with Family-before-Financial weighting intact. A high-value renewal or a fat pipeline
opportunity is an *input*, never an override — it can never outrank a family non-negotiable. Randy has
no path to final authority by design.

**Single Source of Truth.** **The CRM is the source of record; GIOK never becomes a second one.** No
mirror database, no synced copy, no local CRM store. GIOK references CRM records by id and reads them
live. The normalizer *translates*, it does not *persist*. This is the rule that most constrains the
build and it is non-negotiable.

**Workforce Engine.** Randy is an **additive** hire: she registers the standard specialist interface
and returns the standard report (`scope = crm`); the engine is not modified to admit her. Her report
merges with any other specialist's because they all share one report shape. Conflicts (CRM vs.
calendar vs. inbox) are surfaced by Tony, never hidden.

---

## Multi-account / sub-account (design-ahead)

GoHighLevel has **locations / sub-accounts**, and an agency may run more than one. This mirrors the
**Multi-Account Google (D17)** pattern exactly: **one CRM provider reads many accounts**, per-account
tokens stored separately, each normalized record tagged with its **source account**, and everything
**merged only at the intelligence layer** (Randy / the Executive Context) — never duplicated providers
per account. The D17 account-aware token store is the template; the CRM provider follows it rather
than inventing a new one.

## Security & privacy (design-ahead)

- **Credentials are gitignored, never committed.** A future `crm.config.json` (client id/secret or API
  key) and `crm.tokens.json` (per-account tokens) join the private-files list; only a
  `crm.config.example.json` placeholder is tracked. The pre-push secret scan gains CRM token patterns.
- **Read-only scope** requested from the CRM; every write path is a separate consent-gated sprint that
  mirrors Memory-With-Permission (Tony proposes, Jake approves).
- **Client PII is minimized in transit through GIOK.** Randy's evidence carries record ids and the
  least detail needed; diagnostics log **states, counts, and ids — never client lists, contact
  details, or message text**. No PII in URLs or query strings.
- **No cloud sync, no background monitoring.** CRM data is fetched only when a question makes it
  relevant, or on explicit refresh — the same discipline as every other live provider.

---

## Build phases

1. **CRM Provider (read-only) + normalizer for GoHighLevel** — **DONE (Epic 3 Phase 3).** Registers the
   `crm` live signal; maps GHL into the Normalized CRM Model; multi-location (D17 pattern);
   status/test.
2. **Randy specialist** — **DONE (Epic 3 Phase 3).** `Register-Specialist` consuming the normalized
   `crm` signal; standard report (`scope = crm`); activates when the provider is connected,
   `unavailable`/`no-data` honestly when not (the Emma/Riley degradation pattern).
3. **Second CRM backend** (e.g., HubSpot) — future; proves agnosticism by adding only a backend +
   normalizer, with **zero changes to Randy**.
4. **Consent-gated CRM writes** — future; the first actions (e.g., log a note, create a follow-up), each
   behind explicit confirm-before-act. Only after read-only has earned trust.

---

## As Built (Epic 3 Phase 3)

**Authentication — HighLevel Private Integration Token (PIT).** A static bearer token created in the
HighLevel UI (Settings > Private Integrations), stored ONLY in the gitignored
`providers/crm.config.json`, sent as `Authorization: Bearer <token>` with the required
`Version: 2021-07-28` header against base `https://services.leadconnectorhq.com`. *Tradeoff:* a
Marketplace **OAuth 2.0** app is the alternative, but it requires publishing an app and running a
redirect/refresh flow — unnecessary surface for a single internal read-only user. A PIT is the safest
supported approach for Jake's current account: one revocable credential, least-privilege read scopes,
no redirect. (If Jake later needs multi-agency delegation, OAuth can be added behind the same
provider contract without touching Randy.)

**Minimum read-only scopes:** `contacts.readonly`, `opportunities.readonly`, `calendars.readonly`,
`calendars/events.readonly`, `locations.readonly`.

**Endpoints used (all HTTP GET — read-only by construction; the HTTP helper refuses any non-GET):**

| Purpose | Endpoint | Note |
|---|---|---|
| Probe / location name | `GET /locations/{locationId}` | test-connection + label |
| Pipeline stage identity | `GET /opportunities/pipelines?locationId=` | camelCase `locationId` |
| Pipeline + tasks | `GET /opportunities/search?location_id=&status=open&getTasks=true` | **underscore** `location_id` |
| Leads / contacts | `GET /contacts/?locationId=` | fully-specified in the v2 spec |
| Appointments (optional) | `GET /calendars/events?locationId=&startTime=&endTime=&calendarId\|userId` | epoch-ms window |

*Note on contacts:* HighLevel marks `GET /contacts/` deprecated in favor of `POST /contacts/search`,
but the current official OpenAPI spec leaves the search request body **undefined** (`properties: {}`).
Per the "official docs are the source of truth" rule, the provider uses the fully-specified
`GET /contacts/` and will migrate when the search body is documented. (This is the one deprecation
tradeoff; it is read-only either way.)

**Honestly unavailable via GoHighLevel's standard API** (reported as `available:false` with a reason,
never fabricated): **policies, renewals, and outstanding requirements** — GHL has no native insurance
objects. **Underwriting** IS surfaced, but only as *real pipeline-stage identity* (an opportunity in a
stage whose name matches the configured underwriting keywords) — derived from Jake's own pipeline, not
invented. **Appointments** are unavailable unless a calendarId/userId is configured (HighLevel requires
one to read events); Ava's Google Calendar already covers the primary schedule.

**Follow-ups** are sourced from **opportunity-linked tasks** (`getTasks=true`) — a bounded read that
needs no extra calls and builds no task mirror. A full cross-book task sweep is intentionally not done
(rate-limit friendliness + no mirror); this is the honest, current scope.

**Lead signals come from Opportunities, never raw contacts (corrected during live validation).** A
"lead" in CRM terms is an **opportunity in a pipeline** — not a row in the address book. Aging leads,
stalled deals, underwriting, and revenue-at-risk are all derived from **opportunities** (which carry
pipeline stage + activity timestamps). Raw contacts are treated only as a **book-size count**, never as
"leads needing follow-up" — otherwise every contact in an automated drip sequence or long-dead lead
would be flagged as urgent (false alarm). *Aging lead* = an **open opportunity created within
`recentLeadDays`** that has gone cold (48h–`stalledOpportunityDays`); *stalled* = an open opportunity
with no activity for `stalledOpportunityDays`+.

**When the pipeline is empty, Randy says so — she never manufactures an all-clear or a false alarm.**
If GoHighLevel returns zero opportunity records, Randy reports *"No open opportunities in the pipeline
right now (N contacts in the book); pipeline position, stalled deals, and renewals cannot be
assessed,"* at **informational** assessment and **0.5 confidence** — honest limited visibility.
*(Observed live on Jake's account: 9 pipelines / 126 stages but 0 opportunity records — his leads are
tracked as contacts, not opportunity objects. Contact counts are capped/sampled at the most recent 500
and reported as "N+".)*

## Related
- [Randy_CRM_Manager.md](Randy_CRM_Manager.md) — the specialist who reads this seam (constitutional).
- [Workforce.md](Workforce.md) — the org chart and bylaws.
- [Multi_Account_Google.md](Multi_Account_Google.md) — the per-account pattern the CRM provider reuses.
- [Gmail_Provider.md](Gmail_Provider.md) / [Google_Calendar_Provider.md](Google_Calendar_Provider.md) — the read-only live-provider precedent.
- [Executive_Context_Engine.md](Executive_Context_Engine.md) · [Tony_Decision_Framework.md](Tony_Decision_Framework.md) · [13_Project_Diamond.md](13_Project_Diamond.md) — the invariants preserved above.
