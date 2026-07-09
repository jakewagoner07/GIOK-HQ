# Tony's AI Provider Contract

*Project Diamond, Sprint D3. Architecture only — no APIs, no network, no external AI.*

The AI Provider Contract is the **permanent language** Tony uses to talk to any AI model. It sits
in the middle of the chain and is deliberately model-agnostic:

```
Tony  ->  Tony Brain  ->  AI Provider Contract  ->  Provider  ->  Model
```

Everything above the contract (Tony, the Brain) speaks *only* the contract. Everything below it
(the Provider, the Model) is swappable. This one seam is what lets GIOK adopt any AI — now or in
ten years — without changing Tony.

Implementation: `tony-alpha/dashboard/core/tony-provider-contract.ps1`.

## Why Tony never talks directly to models
- **Model-agnostic by design.** If Tony called a specific model's API, GIOK would be married to
  that vendor forever. Instead Tony builds a **Request** in a fixed shape and hands it to "the
  provider." Which model runs — Claude, OpenAI, Gemini, a local LLM — is knowledge that lives
  *only* in the provider layer.
- **Stability.** Models change constantly (new versions, new APIs, deprecations). The contract
  does not. Tony's Brain is written once against the contract and left alone.
- **Honesty & control.** The Brain proposes; it doesn't secretly act. The Response is a described
  set of suggestions the UI decides to execute. *AI explains, never controls*
  ([13_Project_Diamond.md](13_Project_Diamond.md)).
- **Portability & privacy.** Because the request is assembled from GIOK's own single source of
  truth and serialized as plain JSON, the user's data stays theirs, and a local provider can run
  with nothing leaving the machine.

## The Request
One object, versioned, carrying what any model needs to reason well:

`contractVersion · timestamp · userQuestion · context (compact summary) · identity · goals ·
mission · currentWorkspace · openTasks · todaysPriorities · conversationHistory · tonyPersona ·
reasoningHint · requestedAction`

The Request is **transient** — assembled for one call from the single source of truth. The
detailed fields (identity, goals, tasks) carry the data; `context` is a compact summary, so the
message never duplicates data (Diamond Rule 3).

## The Response
Every provider returns exactly this shape:

`contractVersion · answer · suggestedActions · suggestedTasks · suggestedNavigation · confidence ·
needsClarification · reasoningSummary · providerName`

Note **`providerName`**, never a model name. The Brain learns which *provider* answered, never
which *model*.

## Validation
The contract validates before and after the call:
- **Required fields** — `contractVersion`; a request needs a `userQuestion` or a `requestedAction`;
  a response needs an `answer` (or `needsClarification`) and a `providerName`.
- **Empty requests** — a request with nothing to act on is rejected.
- **Missing context** — allowed, but warned (a model reasons better with context).
- **Version compatibility** — same major version required; a mismatched contract is rejected
  rather than silently misread.

## Serializers
JSON only — `ConvertTo/From-TonyRequestJson` and `ConvertTo/From-TonyResponseJson`. These exist so
a future provider can transport the contract however it needs (local process, file, or — later — a
network call the *provider* makes). **The contract itself never touches the network.**

## How a new provider plugs in
A provider is an object implementing `{ name, description, invoke(param $Request) -> Response }`.
To add one:
1. Implement `invoke` to translate the Contract Request into that model's API, call it, and map the
   result back into a Contract Response.
2. `Register-TonyProvider` it, and `Set-TonyActiveProvider` to select it.

That's the whole integration. Today a **`local-stub`** provider implements the contract with no AI,
so the Brain is fully testable now.

## What changing providers should NOT change
Switching from the stub to Claude, or Claude to a local LLM, must change **nothing** except the
provider:
- **Not** Tony's persona, voice, or boundaries.
- **Not** the Brain's Memory, Reasoning, or Action engines.
- **Not** the Request/Response shapes (only their *contents* differ).
- **Not** any other part of GIOK.

If swapping a provider forces a change anywhere else, the contract has been violated.

## Settings (future — no UI change now)
The provider selection Settings will eventually offer (documented in
`Get-TonyProviderCatalog`, none implemented):
- **Auto** — default; picks the best available provider.
- **Claude** · **OpenAI** · **Gemini** · **Local AI** — future.
- **Future Providers** — the plug-in slot for anything else.

No Settings UI is built in this sprint; the vocabulary is defined so the UI can be added later
without changing the contract.

## Related
- [Tony_Brain.md](Tony_Brain.md) — the five engines that produce and consume this contract.
- [06_Tony.md](06_Tony.md) — who Tony is, independent of any model.
- [13_Project_Diamond.md](13_Project_Diamond.md) — AI explains, never controls; the ten-year rule.
