# Executive Reasoning Layer - Epic 12 (architecture)

*One place where all of Tony's reasoning is requested, routed, validated and attributed - so any future
provider (Claude, GPT, Gemini, a local model, or the deterministic engine we already have) can be
swapped in without the rest of GIOK noticing. No provider calls, no keys, no HTTP, no networking in this
sprint. The application behaves exactly as it does today.*

## The frame: this is a kernel, not a feature

| OS concept | GIOK equivalent |
|---|---|
| **syscall** | a **reasoning task** (`understanding.extract`, `briefing.compose`, ...) - a stable name + typed input/output |
| **driver** | a **reasoning provider** (local heuristic engine; later Claude/GPT/Gemini) |
| **kernel** | the **Reasoning Layer** - routes a task to a capable provider, validates the result, attributes it |
| **capability negotiation** | a provider declares *which tasks it supports* and whether it is *available right now* |
| **the CPU that always works** | the **deterministic engine** - the permanent offline floor. Accelerators are optional |
| **MMU / privilege boundary** | the **validation gate** - no provider output reaches a store without passing task-specific checks |
| **no ambient authority** | the layer **never writes**. It returns proposals; owners + the approval flow + the atomic transaction do the writing |

An application developer asks "how do I call Claude here?". An OS architect asks "what is the stable
call, who may serve it, what happens when the server lies or dies, and who is allowed to write?" This
sprint answers the second question and refuses to answer the first.

## What already exists (this is NOT greenfield)

`core/tony-provider-contract.ps1` already declares itself *the permanent, model-agnostic language Tony
uses to talk to any provider* - request/response builders, validators, no network. `core/tony-brain.ps1`
already has a provider registry (`Register-TonyProvider`), a resolve policy, a dispatcher
(`Invoke-TonyProvider`) and a `local-stub` fallback.

**So Epic 12 must generalize what is there, not build a second registry beside it.** Three things that
architecture cannot do today, which a general reasoning kernel requires:

1. **One implicit task.** The contract's request is `userQuestion -> answer`. There is no way to express
   "extract an Understanding Model from these 7 answers" or for a provider to say *"I can do
   `understanding.extract` but not `briefing.compose`."* Capability is not negotiable.
2. **No validation gate.** Whatever a provider returns is what Tony says. For chat that is survivable;
   for structured reasoning that writes Identity it is not.
3. **A resolve policy that is right for chat and wrong for structured work.** `Resolve-TonyProvider`
   deliberately routes to a real provider *even when unconfigured*, so it can answer honestly ("not
   connected") rather than show a placeholder. Exactly right for conversation. **Fatal for
   `understanding.extract`**, where the correct answer to "no provider configured" is not a sentence -
   it is *the deterministic engine's real output*.
   Also: `& $p.invoke $Request` (tony-brain.ps1) is dispatched with **no try/catch** - a provider that
   throws takes down the caller. A kernel may not have that property.

**Relationship, stated once:** the conversational path is the **legacy special case** - it is the single
task `conversation.answer`, served by the existing registry. Epic 12 does **not** rewire it (behavior is
preserved). The Blueprint records that it folds in later as one task + one adapter, at which point the
two registries become one. Until then, `tony-brain`'s registry is untouched.

## The contract

### A task is a name plus a shape
```
task id                  input                         output (proposal)
understanding.extract    7 conversation answers        Understanding Model items
goals.refine             a goal + context              refined goal proposal
briefing.compose         Executive Context             briefing model
capture.classify         raw captured text             capture candidate
inbox.propose            a signal/message              Executive Inbox proposal
lifeos.reason            a Life OS domain + context    domain observations
coaching.advise          context + question            coaching proposal (future)
conversation.answer      user question + context       Tony's reply (LEGACY: served by tony-brain today)
```
Task ids are **stable strings** - the ABI. Adding a task is additive; renaming one is a breaking change.

### Request / Result
```
ReasoningRequest : { taskId, input, context, constraints{ maxMs, requireGrounding }, requestId, createdAt }
ReasoningResult  : { taskId, ok, output, confidence, engine, providerName, reasonCode, clarifications[], degraded }
```
- `engine` / `providerName` are **always truthful**. This is a hard rule with scar tissue behind it:
  Epic 10 shipped a stub that stamped `engine='local+claude'` while doing zero enrichment. Provenance
  that lies is worse than no provenance. The layer stamps attribution itself; a provider cannot forge it.
- `degraded = $true` means "you asked for an accelerator, you got the floor" - visible, never silent.
- `reasonCode` says why (`ok`, `no-provider`, `unavailable`, `timeout`, `invalid-output`, `provider-error`).

### A provider is a driver
```
{ name, description, supports(taskId) -> bool, isAvailable() -> bool, invoke(request) -> result, priority }
```
Deliberately shaped to match the existing provider object (`name`, `description`, `isConfigured`,
`invoke`) so the two can converge later without a rewrite. `supports` is the new capability negotiation;
`isAvailable` replaces `isConfigured` with a broader question ("can you serve *right now*").

## The five kernel guarantees

1. **Total.** `Invoke-Reasoning` never throws. Every provider call is wrapped; a driver that panics
   degrades to the floor and is reported, never propagated. (The existing unprotected dispatch is the
   counter-example.)
2. **A floor that always answers.** The deterministic engine registers for **every** task and is always
   available. There is no state of the world in which a reasoning task has no answer. Offline, no key,
   provider on fire - GIOK still reasons, exactly as it does today.
3. **Nothing unvalidated escapes.** Every task declares a validator. A provider result that fails is
   **discarded** and the floor's result is used (`reasonCode='invalid-output'`). Local results pass the
   same gate - no privileged path. This is where the anti-hallucination rules live (e.g. for
   `understanding.extract`: every item must quote the user's real answer verbatim, and every number in
   the text must exist in the source).
4. **No ambient authority.** The layer **cannot write**. It returns proposals. Identity is still written
   only by `Approve-UnderstandingModel` inside `Invoke-IdentityTransaction`; the Inbox is still written
   only by its owner; the approval flow is still the only consent gate. A future model that decides to
   "helpfully" save something *cannot* - there is no path.
5. **Bounded.** `constraints.maxMs` is carried on every request and is the caller's contract with the
   scheduler. This sprint implements the plumbing only (the floor is instant); the deadline is enforced
   when a provider that can block is introduced - deliberately, because the one real provider we have
   (`claude-provider.ps1`) has **no HTTP timeout**, so the bound must live on our side of the line.

## Routing policy (the scheduler)

```
Invoke-Reasoning(request):
    candidates = providers where supports(taskId) and isAvailable(), ordered by priority
    for p in candidates:
        r = guarded_invoke(p, request)            # never throws
        if r.ok and validate(taskId, r):  return stamp(r, engine=p.name, degraded=false)
        record(reasonCode); continue              # try the next driver
    r = guarded_invoke(floor, request)            # the deterministic engine
    return stamp(r, engine='local', degraded=(candidates was non-empty))
```
Note the difference from `Resolve-TonyProvider` and why it is correct here: for a **structured** task,
an unconfigured accelerator is simply *not a candidate* - we do not route to it so it can apologise. The
floor answers. For `conversation.answer`, the existing honest-apology behaviour stays where it is, in
tony-brain, unchanged.

## What this sprint ships

- `core/reasoning-layer.ps1` - the kernel: task registry + validators, provider registry, router,
  guarded dispatch, provenance stamping. No providers. No network.
- `core/reasoning-local.ps1` - the **floor**: one provider that supports every task by delegating to the
  deterministic engines that already exist (`New-UnderstandingModel`, etc.). It adds no intelligence; it
  is the existing behaviour, wearing the driver interface.
- **One real client, to prove the seam:** `Initialize-UnderstandingModel` obtains its model *through the
  layer* instead of calling `New-UnderstandingModel` directly. The layer routes to the floor, which
  calls the same function, and `meta.engine` (already `'local'` today) becomes the layer's provenance
  stamp. **Output is byte-identical** - verified against the 102-conversation adversarial suite.

Why wire a client at all? Because an unused abstraction is unproven, and this codebase has already been
burned once by scaffolding that was never exercised (the enrichment stub). One real caller keeps the
kernel honest and makes the next migration a driver swap rather than a redesign.

## What this sprint does NOT do
No Claude/GPT/Gemini adapter. No API keys, no HTTP, no networking, no retries, no cost/rate policy. No
migration of `conversation.answer`, capture, inbox, briefing or Life OS onto the layer - those are
future, one task at a time, each behind its own validator. No new store: the layer is **stateless**. No
change to SSOT, onboarding, approval, atomic transactions, the Understanding Model, Executive Context,
the Personalizable Workspace, or the Executive Inbox.

## Preserved
Everything. The one behavioural claim of this sprint is *nothing changes*, and it is verified rather
than asserted: the full Understanding suites (102 adversarial conversations, core guarantees, atomic
write + rollback, review UI, resume), Home/Goals/Life OS/Inbox/Workforce renders, and a clean launch.

## Verification plan
Byte-identical Understanding Model output through the layer vs. direct (102 conversations). Floor
answers every registered task. Guarded dispatch survives a provider that throws, returns junk, or
returns null - each degrading to the floor with the correct `reasonCode`. Validation gate rejects a
result that fabricates or drops the source answer. Provenance never lies (`engine` reflects who actually
served). The layer writes nothing (no file touched by any reasoning call). Parse, secret scan, git
integrity, full launch.

## The migration this unlocks (not this sprint)
`Blueprint/Understanding_Claude_Migration.md` becomes one line of this design: register a Claude driver
that `supports('understanding.extract')`, and the router does the rest - validation gate, floor
fallback, truthful provenance and consent already exist. Same for every other task, one at a time.
