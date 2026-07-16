# Claude Understanding Driver - Epic 13

*The first real external reasoning driver. It plugs into the Executive Reasoning Layer (Epic 12) and
serves exactly one task - `understanding.extract` - by asking Claude to organize the seven onboarding
answers into the existing Understanding Model. Everything the kernel already guarantees stays true:
the deterministic local engine is the permanent floor, nothing reaches Identity without Jake's review
and approval, and provenance never lies. This epic adds three things Epic 12 deliberately did not:
an explicit consent gate, a strict-JSON prompt/parse contract, and real deadline enforcement.*

## The one architecture, unchanged

```
onboarding answers
  -> explicit consent          (new: Use Claude / Keep Processing Local)
  -> Executive Reasoning Layer  (Epic 12 kernel, unchanged shape)
  -> Claude driver attempt      (new: bounded, only if configured AND consented)
  -> kernel validation          (Epic 12 gate, unchanged; Claude also passes a tighter driver gate)
  -> existing Understanding Model
  -> review screen              (identical for Claude and local; adds one honest disclosure line)
  -> user approval
  -> atomic Identity transaction (Epic 10, unchanged)
```

Nothing in this list is new except the four labelled `(new)`. The Understanding Model shape, the review
view, `Approve-UnderstandingModel`, `Invoke-IdentityTransaction`, the seven questions, SSOT - all frozen.

## Consent is the driver's availability

The cleanest place to enforce "no answer leaves the machine without consent" is the kernel's own
routing. `Resolve-ReasoningProviders` only considers a driver that reports `isAvailable() = true`. So:

```
claude-understanding.isAvailable()  =  Claude is configured  AND  consent granted for THIS attempt
```

- **Consent declined, or not configured, or not asked** -> `isAvailable = false` -> the kernel never
  invokes the driver -> the floor answers -> `meta.engine = 'local'`. **The answers are never even
  passed to the driver**, because an unavailable driver is not a candidate. Privacy is structural, not
  a promise inside the call.
- **Consent granted + configured** -> the driver is a candidate -> the kernel invokes it (bounded).

Consent is **per extraction attempt**. It is a script-scoped flag set immediately before extraction and
cleared immediately after - it does not persist. A user may *explicitly* ask to remember the choice;
only then is a `rememberExtractionConsent` flag written to the existing gitignored Claude config, and it
is read back on the next attempt. **Consent is never remembered silently** - the default is ask-every-time.

Consent text (the disclosure), shown before any answer can leave the machine:

> "Tony can use Claude to organize what you shared. Your onboarding answers will be sent to the
> configured AI provider for interpretation. Nothing will be saved to Identity until you review and
> approve it."
>
> **[ Use Claude ]   [ Keep Processing Local ]**

"Keep Processing Local" is not a downgrade and is not framed as one - it is the same review screen and
the same model shape, produced by the deterministic engine that has always run offline.

## The driver contract

One driver, registered into the Epic 12 registry:

```
id:           claude-understanding
supports:     understanding.extract   (ONLY - no other task this epic)
isAvailable:  configured AND consented-for-this-attempt
invoke:       build prompt -> call Claude (bounded) -> parse strict JSON -> map to Understanding Model
priority:     10   (preferred over the floor's 1000 when available)
isFloor:      false
bounded:      true (opts into kernel deadline enforcement)
```

Hard rules, all enforced in code and tested:

- Returns the **existing** Understanding Model shape - no new fields, no new stores.
- Performs **no domain writes**. It returns a proposal; the layer cannot write (Epic 12 guarantee 4).
- Does **not** bypass the kernel - it is invoked *by* the kernel and its output passes the kernel's
  validator like any other provider (no privileged path).
- **Cannot mark items `edited = true`.** An edit is the user's own words; a provider asserting it is a
  forgery. The existing validator already rejects `edited=true` in provider output; the driver also
  refuses to emit it.
- Does **not** set final `engine` attribution. The kernel stamps `engine`/`providerName`; a driver
  cannot forge provenance (Epic 12, scar tissue from the `local+claude` stub).

## The Claude prompt / JSON contract

One request per interview - all seven answers in, strict JSON out. **Claude returns a JSON object and
nothing else**: no markdown fences, no prose before or after. The parser rejects anything that is not a
clean object (with a single tolerant salvage: if the text is a fenced block or has leading/trailing
prose, the parser extracts the outermost `{...}` span and parses that; if THAT fails, it is a whole-
response rejection -> floor).

Requested shape:

```json
{
  "goals": [ <item>, ... ], "values": [...], "priorities": [...],
  "challenges": [...], "strengths": [...], "boundaries": [...],
  "summary": "one concise grounded paragraph",
  "clarifications": [ "a question Tony should ask", ... ],
  "omitted": [ { "text": "...", "reason": "below the bar / hedged" }, ... ]
}
```

Every extracted item MUST carry:

```json
{ "text": "...", "sourceQuestionId": "q_goal", "sourceQuestion": "...",
  "sourceAnswer": "<the user's answer VERBATIM>", "reason": "You named this as...",
  "confidence": 0.0-1.0, "band": "high|low", "edited": false }
```

Prompt rules embedded verbatim (organize, never invent):

- Every fact must be supported by the supplied answers. Preserve all user-provided numbers, dates,
  names, companies, and commitments **exactly**.
- Do **not** create new dates, dollar amounts, targets, diagnoses, relationships, or facts.
- Split compound goals only when clearly distinct. Compress long answers intelligently.
- Values are **principles**, not priorities.
- Prefer omission over unsupported inference.
- Do **not** diagnose personality, mental health, medical conditions, leadership style, or risk tolerance.
- Executive summary: concise, natural, grounded.
- Output the JSON object only - no markdown, no prose outside it.

`sourceQuestionId` must be one of the seven real ids (`q_name, q_areas, q_goal, q_challenge, q_protect,
q_week, q_boundaries`). The model id lives only in the Claude config; Tony never sees it.

## Validation - the machine validates FACTS, the human validates MEANING (Epic 13A)

> **Recalibrated in Epic 13A** after live verification and a CTO architecture review. The original design
> added a Claude-only *multi-anchor / token-fraction* rule to reject a fabrication that borrows "one
> generic word." Live runs proved it also rejected reasonable paraphrases of terse answers ("Protect
> evenings at home" from "Home by six most nights"), and with whole-result rejection that dropped every
> real Claude extraction to local - a net-negative feature (data sent, latency paid, local result
> returned). The token-fraction rule and a paraphrase are mathematically indistinguishable (both share
> one concept word), so no wording threshold can separate them. The decision: **stop asking the machine
> to judge wording.** Semantic compression is the reason Claude exists; the mandatory review screen is
> where the user approves meaning.

**The principle:** the machine enforces facts, deterministically and whole-result; the human enforces
meaning, on the review screen where every interpretation sits beside its verbatim original with Edit and
Remove, and nothing writes until atomic approval.

Claude output passes **two** gates and must satisfy both. Both enforce FACTS only.

1. **The kernel validator (`reasoning-local.ps1`, universal - guards the floor too, no privileged path):**
   - every item cites a real question and quotes the answer **verbatim**;
   - every **number/amount/percent/time** in the text appears in the cited answer;
   - every **proper noun** (person, company, city, organization, month) in the text appears in the cited
     answer - the new deterministic fact gate; honest compression does not introduce novel names;
   - the **absurdity floor**: the text shares at least one significant token with the cited answer, so an
     item about something the answer never mentioned ("Buy a yacht" from "I want 500 policies") is
     rejected. This is a tripwire for fabrication, **not** a paraphrase-quality threshold;
   - `edited=true` (forged provenance) is rejected; over 200 items is rejected.
2. **The Claude driver's whole-result gate (`Test-ClaudeExtractionGrounded`)** applies the **same fact
   conditions** before the driver returns, so a single fact violation rejects the WHOLE Claude result and
   the kernel falls to the floor (`meta.engine='local'`). Plus size/length caps and deterministic dedup.
   - **What was REMOVED:** the multi-anchor / token-fraction wording rule. A reasonable paraphrase now
     passes; a one-generic-word wording choice is now the human's call on the review screen.

**Whole-result rejection is reserved for a provider that LIED** - a fabricated fact, a forged flag, a
malformed or absurd result. It is no longer triggered by wording distance. Claude and local output are
still never combined; there is no partial merge.

Partial Claude output is never combined with local output. Mixing engines inside one model muddies
provenance, and provenance that lies is worse than none.

## Bounded execution (real `maxMs` enforcement)

Epic 12 left `maxMs` as plumbing. Epic 13 enforces it, because the one real provider has **no HTTP
timeout** and onboarding must never hang.

- A `bounded` driver's work runs in a **background runspace**, not on the caller's thread. The kernel's
  guarded dispatch starts it, then `WaitOne(maxMs)`.
- **Completed in time** -> read the result, validate, use it.
- **Deadline expired** -> **abandon** the work (stop + dispose the runspace asynchronously), do not read
  its result, and immediately fall to the floor with `fallbackReason = 'timeout'` (`reasonCode='timeout'`).
- **A late result is discarded.** The kernel tags each bounded dispatch with the request's `requestId`;
  a completion whose id does not match the awaited id is dropped. There is no path for a stale Claude
  model to overwrite a floor model that already won.
- **Honest about cancellation.** The underlying `Invoke-WebRequest` cannot truly be cancelled mid-flight
  on PS 5.1, so we do not claim cancellation - we claim **abandonment**: the HTTP call may still complete
  on the runspace, but its result is never read and the runspace is torn down. Documented as such.
- **Cleanup.** Bounded runspaces are tracked and disposed; closing the app tears them down (no orphan
  runspaces), mirroring `Stop-AsyncWorkers`.
- Every provider failure class - 401, 403, 429, 500, malformed response, network failure, timeout -
  degrades calmly to the floor with a truthful `fallbackReason`.

The UI never blocks: onboarding runs the whole extraction (kernel + bounded driver) off the WPF thread
via the existing async pattern, and the deadline bounds even that worker. Navigating away or closing
during extraction does not update a stale view (guarded by the active-view/requestId check).

## Configuration and security

- Reuse the **existing** gitignored `providers/claude.config.json` (and `ANTHROPIC_API_KEY`) via
  `Get-ClaudeConfig`. No second secrets store. Only `claude.config.example.json` is tracked.
- Never commit API keys. Never log secrets, onboarding content, prompts, Claude responses, or Identity
  data. No request/response bodies in diagnostics.
- Diagnostics carry only: provider id, task id, request id, status, duration, safe error class, item
  counts, fallback reason. (Same discipline as the Yahoo/communications diagnostics.)

## What this epic does NOT do

No migration of any other reasoning task (goals.refine, briefing.compose, capture.classify,
inbox.propose, lifeos.reason, coaching.advise stay unmigrated and fail closed). No provider retries,
cost/rate policy, or streaming. No change to the Understanding Model shape, the review UI's structure,
the approval flow, the atomic transaction, or SSOT. No new persistent store beyond the one optional
`rememberExtractionConsent` flag inside the existing Claude config. The 11 runtime-data files are
untouched. `task_b9ec97bb` is not addressed.

## Honest posture (documented, not hidden)

- Claude is primary **only when configured and consented**; otherwise the local engine runs, exactly as
  it always has.
- Local extraction is the **permanent** offline / privacy / failure floor - not a temporary shim.
- `maxMs` is now enforced by **abandonment**, not true cancellation.
- External drivers are **trusted in-process code, not sandboxed** (Epic 12 guarantee 4's honest limit).
  Registering a driver is a code-review event.
- **Nothing is saved until Jake approves it** on the review screen.
- Validation may reject Claude and fall back locally - and that is a success, not a failure.

## Files

- **new** `core/reasoning-consent.ps1` - per-attempt consent state; remember-opt-in read/write against
  the existing Claude config; never silent.
- **new** `core/reasoning-claude.ps1` - the driver: prompt builder, strict-JSON parser, tighter grounding
  gate, dedup, bounded-work payload; registers `claude-understanding`.
- `core/reasoning-layer.ps1` - deadline enforcement in guarded dispatch (bounded runspace, abandon,
  stale-result discard, cleanup). No other behavioural change.
- `core/understanding-engine.ps1` / `core/first-conversation.ps1` - carry `fallbackReason` /
  `meta.engine` truthfully to the review screen; no model-shape change.
- `ui/tony-ui.ps1` - the consent screen, the extraction orchestration (off-thread, deadline-bounded,
  stale-view-guarded), and one disclosure line on the review screen.
- `tony-alpha/dashboard/tests/reasoning/` - the two hygiene fixes plus the permanent Claude-driver suite.
- Docs listed in the epic.

## Commit stages
1. Blueprint, consent, and driver contract.
2. Claude driver and prompt/response parser.
3. Kernel deadline enforcement and stale-result protection.
4. UI orchestration and review integration.
5. Permanent tests, live verification, and documentation.
