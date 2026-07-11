# GIOK — CTO Handoff

*Read this first when picking up GIOK development in a fresh chat. It carries the intent, the rules,
and the exact stopping point so nothing is lost. Pair it with `GIOK_Project_Status.md` (state) and
`Product_Roadmap.md` (what's next).*

---

## What GIOK is

GIOK is a **desktop operating system for a disciplined life and business**, built for Jake Wagoner
(licensed insurance agent, GIOK Agency, Ogden, UT). Living inside it is **Tony**, Jake's **AI Chief
of Staff**. The product exists to answer one question every day: **"What should Jake focus on
today?"** — and to help him become *better, not busy*.

It is a Windows PowerShell 5.1 + .NET WPF desktop app (no Node/Python). The first working product,
`tony-alpha/`, is a dark executive command center: Home with an Executive Briefing, Identity, Action
Items, Capture, End of Day Audit, Mission Control, a Talk-with-Tony conversation window, live
providers, and permission-based memory.

## Jake's product philosophy

Three lines are the soul of the product. If a feature contradicts any of them, it is wrong, no
matter how clever:

> **People Matter More Than Money.**
> **Your brain is for thinking, not remembering.**
> **GIOK helps you become better, not busy.**

Corollaries Jake holds to: **Family before Financial**; the ten-year test (a plan should still make
sense in ten years); **quality over quantity** — perfect experiences, don't pile on features; honesty
over polish (never fake data or hide failures).

## Project Diamond rules

Project Diamond is the quality standard. Nothing ships unless it is **useful, beautiful, simple,
fast, time-saving, and something Jake would use every day.** Practically:

- **Refine experiences, not feature counts.** Many D-sprints were behavioral refinements, not new
  screens.
- **Every sprint gets a Blueprint doc** explaining *why*, indexed in `Blueprint/00_README.md`.
- **Single Source of Truth.** No duplicate storage; engines *reference* sources, never copy them.
- **Honesty is a feature.** Unknown is said as unknown; failures explain themselves; no placeholders.
- **The blueprint wins over convenience.** Decisions are settled in `Blueprint/` first, code second.

## Tony's role

Tony is a **Chief of Staff, not a chatbot**. He is **broadly capable but purposefully grounded**:
he answers any question well (weather, history, math, general knowledge), **answer first, ground
second**, and never makes Jake feel he asked the wrong question. He reads the situation before
responding (Executive Context), weighs it against Jake's life (Decision Framework — *judgment*, not
intelligence, with Family before Financial), notices patterns kindly (Observation Engine), remembers
only with permission (Memory Manager), and explains live data in his own voice (providers are
implementation details). **AI is an implementation detail; Tony never reveals the model, prompts,
architecture, provider, or tokens.**

## Permanent architecture decisions

These are settled and should not be re-litigated without a blueprint change:

1. **Layering:** theme → core (data/logic) → providers → ui. UI has no business logic; core does no
   rendering. Dot-sourced by `dashboard.ps1` in dependency order.
2. **The AI is behind a contract.** `tony-provider-contract.ps1` is a model-agnostic request/response.
   Tony Brain never names a model; only the provider file (`claude-provider.ps1`) knows it.
3. **Judgment is separate from intelligence.** The Decision Framework runs *before* any provider and
   keeps **final authority**; the model informs, Tony judges.
4. **One Executive Context, assembled on demand, never stored.** It references sources and holds no
   state; two calls differ because the world differed, not because anything was cached.
5. **Two registries.** AI-provider registry (reasoning) and live-provider registry (information) are
   distinct. Live providers implement `relevant`/`query`/`status` and register; **Tony Brain consumes
   them generically — no per-provider dependency in the Brain.**
6. **Permanent memory is permission-gated.** `memory-manager.ps1` is the *only* writer; nothing else
   writes memory; detection proposes, the user approves.
7. **Native UTF-8 end to end.** Provider decodes responses as UTF-8; storage round-trips Unicode; no
   ASCII-rewriting "cleanup" layers.
8. **PS 5.1 reality:** no-BOM `.ps1` files are read as ANSI, so **source stays pure ASCII** — build
   non-ASCII at runtime (`[char]0xXXXX`, `\uXXXX` regex). No ternary; `$Input` is reserved.
9. **Tony manages specialists; Tony never becomes one (D20 Workforce Engine).** Specialists register
   the standard interface (`workforce-engine.ps1`), analyze existing provider outputs only (no
   duplicate logic, no new storage, no independent agent memory), and return standard reports. They
   never act, never reach Jake directly, and cannot bypass Tony — only Tony's merged synthesis is
   presented, with transparency (specialists used, evidence, reasoning) and the Decision Framework as
   final authority. Future specialists plug in with no redesign. The **org chart and bylaws are
   constitutional** — see `Blueprint/Workforce.md` (Tony, Sam, Ava, Emma, Riley, Mason, **Randy** +
   future hires), which also settles two permanent rules: the **Executive Awareness Principle** ("Tony
   never silently ignores meaningful information; he reduces complexity without reducing awareness")
   and the **Rule of Progressive Delegation** ("Tony delegates to the fewest specialists necessary to
   confidently answer the question").
10. **Specialists are built around disciplines, not vendors (Epic 3, `Randy_CRM_Manager.md`).** Randy
   the CRM Manager understands **CRM as a discipline** (leads, pipeline, renewals, underwriting,
   requirements, policies, follow-ups) — **not GoHighLevel**. A CRM is a data source, not an identity;
   a new CRM (HubSpot, Salesforce, Zoho, Pipedrive, custom) is a **provider backend + normalizer**,
   never a redesign of the specialist. The CRM reads through the existing live-provider registry as the
   `crm` signal into the one Executive Context (no CRM store, no mirror DB — Single Source of Truth),
   and Randy consumes only the **normalized CRM model**. Provider architecture is designed in
   `Blueprint/CRM_Provider.md` (**design only; no CRM code yet** — read-only first, writes are a later
   consent-gated sprint).

## Security / privacy rules

- **Never commit secrets.** API keys, OAuth client secrets, access/refresh tokens, authorization
  codes, and personal data stay in **gitignored local files**. Only `*.example.json` placeholders are
  tracked.
- **Private-by-default local files:** `claude.config.json`, `calendar.config.json`,
  `calendar.tokens.json`, `conversation.json`, `tony_memory.json`, `memory-export-*.json`,
  `weather.config.json`, `logs/`. All gitignored.
- **Diagnostics logs contain no tokens, keys, codes, or user message text** — states, counts, timing,
  and error classes only.
- **Google Calendar is READ-ONLY** this phase (`calendar.readonly`). Any write capability is a
  separate, consent-gated sprint (mirror Memory With Permission: Tony proposes, Jake approves).
- **No cloud sync, no service accounts for personal data, no hidden background monitoring, no
  automatic actions.** Live data is fetched only when relevant / on Refresh / on explicit request.
- **Before every push:** scan staged content for `sk-ant`, `GOCSPX`, `ya29.`, token values, and
  config files; confirm private files gitignored and absent from the remote.

## Current Git state

- **Branch:** `feature/dashboard-alpha` (all work lives here; **never merge into `main`**).
- **PR #1** open against `main`, **not merged** — it accumulates the whole build.
- **HEAD:** `2a2d42a` *Build Read-Only Google Calendar Provider*; local = remote.
- **Working tree:** clean except one intentional untracked file, `Founder/Tony_Feedback.md`.
- **Workflow every sprint:** build → commit locally → **push only when Jake explicitly says so** →
  keep on `feature/dashboard-alpha` → leave PR #1 open. After a push, confirm branch status, commit
  hash, remote sync, PR inclusion, clean tree, and secret-safety.

## Exact current stopping point

Sprint **D14 (Read-Only Google Calendar Provider)** is **committed and pushed**. The provider's full
architecture (OAuth 2.0 desktop + PKCE + loopback + offline refresh + read-only fetch + structured
contract + Settings Connect/Test/Disconnect) is implemented and tested *except the live connection*,
which needs Jake's Google Cloud OAuth client and browser consent (it cannot and must not be
fabricated in a build environment). **Manual steps for Jake are in `Google_Calendar_Provider.md` and
`GIOK_Project_Status.md`.** Nothing is mid-edit; the tree is clean.

## Recommended next steps

1. **Jake completes Google OAuth setup** (Cloud project → enable Calendar API → OAuth consent →
   Desktop client → paste into `calendar.config.json` → Settings → Connect). Then validate live.
2. **D15 — Calendar go-live + calendar-aware Executive Briefing** (on-demand, not per render).
3. **D16 — Gmail read-only provider** (same OAuth/registry/Settings pattern).
4. Begin **Phase 3 (Executive Automation):** a local scheduler to pre-compose the morning briefing.

See `Product_Roadmap.md` for the prioritized plan and the reasoning behind the order.

## Instructions for the next CTO chat

1. **Read, in order:** this file → `GIOK_Project_Status.md` → `Product_Roadmap.md` → the relevant
   subsystem Blueprint docs (`00_README.md` indexes them).
2. **Work on `feature/dashboard-alpha` only.** Do not merge to `main`. Do not push unless Jake says
   to. Leave PR #1 open.
3. **Follow Project Diamond:** blueprint the *why*, keep Single Source of Truth, be honest, refine
   experiences.
4. **Respect the PS 5.1 rules** (ASCII source, no ternary, `[char]` for non-ASCII) and **use the Edit
   tool** for `.ps1` files — never raw `WriteAllText` (AV-lock risk).
5. **Never commit secrets;** run the pre-push secret scan; keep Calendar read-only.
6. **End each sprint** with a commit (message = the sprint name), a Blueprint doc, and an update to
   `GIOK_Project_Status.md` and `Product_Roadmap.md`.
7. **Verify before claiming done** — render headless screenshots and/or run a harness test; report
   faithfully (failures included).
