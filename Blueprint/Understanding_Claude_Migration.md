> **Superseded in part by Epic 12.** The Executive Reasoning Layer
> (`Blueprint/Executive_Reasoning_Layer.md`) now provides the routing, the validation gate, the
> guaranteed deterministic fallback and the truthful provenance this plan described building by hand.
> What remains of this document is the part Epic 12 deliberately did **not** do: the prompt contract,
> the strict-JSON parser, the bounded call, and the consent/disclosure decision. Concretely, the
> migration is now: **register a driver that `supports('understanding.extract')`** - everything around it
> already exists and is tested. Read this for the Claude-specific detail; read the Epic 12 Blueprint for
> the architecture it plugs into.

# Migration Plan: Claude as the Primary Extraction Layer (Epic 10 follow-up)

*Replace ONLY the extraction layer of the Understanding Engine with Claude, keeping the local
deterministic extractor as the always-available fallback. The Understanding Model, review screen,
approval flow, atomic transaction, Identity stores and SSOT are FROZEN - nothing in this plan
touches them.*

## Why (the honest ceiling of the deterministic extractor)

Three review cycles took the local extractor from "writes 'Honestly' into core values" to 50/50 clean
on a machine-checked adversarial suite. Every corruption class is now guarded: numeric commas, orphan
fragments, discourse markers, retractions, duplicates, phantom arrays, conflict false-positives. What
remains is the last 10% - paraphrase quality ("Idk work" as a priority for a user who typed "idk work
lol"; "My health and Health first now" as near-duplicate priorities), tone, and genuine semantic
inference (values beyond marker phrases; conflicts beyond the concept map). That tail is exactly what
word lists cannot close and exactly what an LLM does well. Further tuning has diminishing returns and
each new list is future maintenance debt - so per the extraction-quality mandate: stop tuning,
migrate the layer.

## What stays frozen (the contract the LLM must fit INTO)

- **The Understanding Model item shape** - `{id, text, sourceQuestionId, sourceQuestion,
  sourceAnswer, reason, confidence, band, clarify, edited}` - is already provider-agnostic.
- `New-UnderstandingModel` remains the single seam. Callers (`Complete-Conversation`, the review
  view, `Approve-UnderstandingModel`) do not change at all.
- The review screen stays mandatory. LLM output is a *proposal*, exactly like local output - nothing
  reaches Identity without Jake's approval and the existing atomic transaction.
- The conflict contract stays: keep-and-flag, never delete.

## Design

### 1. Engine selection
`New-UnderstandingModel` gains an internal dispatch:
```
claude configured?  -> try Claude extraction (bounded)  -> validate -> use, meta.engine='claude'
                                     |  any failure/timeout/invalid
not configured      ------------------------------------> local extractor, meta.engine='local'
```
`meta.engine` is always truthful. No new stores, no provider changes - the existing registered Claude
provider is *called*, never modified.

### 2. The prompt contract
One request per interview (all 7 answers), demanding STRICT JSON matching the model shape:
- every item MUST include `sourceQuestionId` (one of the 7 real ids) and `sourceAnswer` (the user's
  answer VERBATIM);
- `reason` explains the extraction in second person ("You named this as...");
- rules embedded verbatim from the epic: never invent facts; a category with no support stays empty
  (Strengths in particular); hedged statements go to `omitted[]`; conflicts keep the item and add
  `clarify`; preserve the user's numbers exactly.

### 3. The validation gate (the anti-hallucination layer, non-negotiable)
LLM output is REJECTED item-by-item unless:
- `sourceQuestionId` is a real question id AND `sourceAnswer` equals that question's actual answer
  byte-for-byte (Tony cannot cite words the user never said);
- every number/amount appearing in `text` also appears in the source answer;
- `confidence` clamps to [0,1]; sections are real arrays (reuse the existing shape guards);
- the whole-response JSON parses and every section is present.
Any rejection of the WHOLE response (parse failure, wrong shape) -> local fallback. Rejection of a
single item -> drop that item, keep the rest (the local extractor's result for that question is NOT
merged in - mixing engines inside one model muddies provenance).

### 4. Timeout and threading (the provider has NO HTTP timeout - unfixable here)
The call must never hang onboarding: run it in a bounded background runspace (the Epic 9 async
pattern; the worker infrastructure already exists) with a hard deadline (~12s). Deadline passed ->
local extractor wins, `meta.engine='local'`, and the orphaned call is abandoned harmlessly (its
runspace is disposed on completion; it writes nothing). The review screen renders whichever model won
- the UX is identical either way.

### 5. Privacy and consent (new, must be explicit)
Today onboarding is fully offline. Claude-primary means the 7 answers - deeply personal - leave the
machine when a key is configured. Requirements:
- a one-line disclosure on the review screen when `meta.engine='claude'` ("I organized this with the
  help of my AI engine") and in Settings;
- the interview itself never blocks on the network (extraction happens once, after the last answer);
- nothing is sent when no key is configured - the local engine remains the default experience.

### 6. Testing (the suite is the specification)
- The 50-conversation adversarial suite plus the 12 CTO conversations become the permanent golden
  set; the 9 machine-checked invariants (junk items, orphan thousands, duplicates, lost goals,
  descriptive-answer clarifications, lost amounts, retraction leaks, malformed items, summary
  hygiene) must pass for BOTH engines - the validation gate makes most of them structural for Claude.
- Side-by-side phase first: run both engines on the golden set, diff the models, eyeball summaries.
  Claude becomes the default only after it beats local on the eyeball pass with zero invariant
  violations.
- The fallback path is tested by simply not configuring a key - it is the same code local-only users
  run forever.

## Sequencing (one sprint)
1. Prompt + strict-JSON parser + validation gate (pure functions, testable offline with fixtures).
2. Bounded background call via the existing async pattern; dispatch in `New-UnderstandingModel`.
3. Consent line in the review view (one `New-Text`, engine-conditional).
4. Golden-set side-by-side run; flip the default; document results in this file.

## Out of scope
Provider changes (timeouts, retries), new stores, model-shape changes, review-UI redesign, acting on
`omitted[]`/"ask later" (separate feature), and any Identity-side changes.
