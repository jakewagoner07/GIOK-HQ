# CRM Provider — Architecture (Design Only)

> **Status: DESIGN ONLY. No provider code exists yet.** This document settles *how* GIOK will read a
> CRM before any line of CRM code is written, so the implementation — when it comes — has nothing left
> to invent. It is the blueprint for the seam that [Randy](Randy_CRM_Manager.md) will one day read.
> Building the provider is a **separate, future sprint** and a **separate commit**.

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

## Future build phases (not now)

For sequencing when Jake approves implementation — each a separate sprint and commit:

1. **CRM Provider (read-only) + normalizer for GoHighLevel** — register the `crm` live signal; map GHL
   into the Normalized CRM Model; per-sub-account tokens (D17 pattern); Settings connect/test/disconnect.
2. **Randy specialist** — `Register-Specialist` consuming the normalized `crm` signal; standard report
   (`scope = crm`); activates when the provider is present, `unavailable` honestly when not (the
   Emma/Riley degradation pattern).
3. **Second CRM backend** (e.g., HubSpot) — proves agnosticism by adding only a backend + normalizer,
   with **zero changes to Randy**.
4. **Consent-gated CRM writes** — the first actions (e.g., log a note, create a follow-up), each behind
   explicit confirm-before-act. Only after read-only has earned trust.

## Related
- [Randy_CRM_Manager.md](Randy_CRM_Manager.md) — the specialist who reads this seam (constitutional).
- [Workforce.md](Workforce.md) — the org chart and bylaws.
- [Multi_Account_Google.md](Multi_Account_Google.md) — the per-account pattern the CRM provider reuses.
- [Gmail_Provider.md](Gmail_Provider.md) / [Google_Calendar_Provider.md](Google_Calendar_Provider.md) — the read-only live-provider precedent.
- [Executive_Context_Engine.md](Executive_Context_Engine.md) · [Tony_Decision_Framework.md](Tony_Decision_Framework.md) · [13_Project_Diamond.md](13_Project_Diamond.md) — the invariants preserved above.
