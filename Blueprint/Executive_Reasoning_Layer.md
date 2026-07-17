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
   **discarded whole** - never partially merged - and the router moves on (`invalid-output`). Local
   results pass the same gate - no privileged path. The anti-hallucination rules live here; for
   `understanding.extract` the shipped gate enforces: every item cites a real question and quotes the
   user's answer **verbatim**; every **number** in an item's text (integers, comma amounts, decimals,
   percentages, times) appears in the cited answer; the text shares at least one significant token
   (4-char stem) with the cited answer, so a truthful citation cannot carry an unrelated invention;
   user-edited items are exempt (their words ARE the ground truth); and a result larger than 200 items
   is rejected outright - never silently truncated, because a trimmed result pretending to be complete
   is a quiet lie. **Unmigrated tasks fail closed**: their validators reject unconditionally
   (`'task not migrated'`), so a provider claiming broad support cannot smuggle junk through a task the
   kernel cannot yet police - the floor's honest `no-provider` is the only possible answer there.
4. **No ambient authority.** The layer **cannot write**. It returns proposals. Identity is still written
   only by `Approve-UnderstandingModel` inside `Invoke-IdentityTransaction`; the Inbox is still written
   only by its owner; the approval flow is still the only consent gate. A future model that decides to
   "helpfully" save something *cannot* - there is no path.
   **The honest limit of this guarantee:** it constrains the *layer and its outputs*, not driver code
   itself. Drivers are **trusted, in-process PowerShell** - they are not sandboxed, and nothing can stop
   trusted code in the same process from performing arbitrary OS actions. The kernel prevents unsafe
   *output* from escaping; it does not (and cannot) confine what a driver's code does while running.
   Registering a driver is therefore a code-review event, not a configuration event.
   **Payload isolation:** drivers also never see the caller's object or each other's copies. The kernel
   snapshots the payload once at entry and hands every dispatch - each accelerator, the validator's
   grounding source, and the floor - its own fresh clone, so a driver that mutates its copy and then
   fails cannot poison the fallback, a later validation, another provider, or the caller.
5. **Bounded.** `constraints.maxMs` is carried on every request and is the caller's contract with the
   scheduler. **As of Epic 13 it is ENFORCED** for a `bounded` provider: its portable work runs in a
   background runspace and the kernel waits at most `maxMs`. On deadline the work is **abandoned** - the
   kernel never reads its result and reaps the runspace asynchronously - and the floor answers with
   `fallbackReason='timeout'`. A late completion is discarded (its `requestId` will not match). This is
   *abandonment, not cancellation*: `claude-provider.ps1` has **no HTTP timeout**, so the request may
   still finish on the runspace; we simply never read it. Non-bounded providers and the floor run inline,
   exactly as before.
   Re-entrancy IS bounded today: a driver may call back into the kernel a few levels deep (nested
   reasoning is a legitimate future pattern), but at depth 8 the kernel answers `reentrancy-limit`
   instead of overflowing the stack.

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

## The migration this unlocked (DONE - Epic 13)
`Blueprint/Understanding_Claude_Migration.md` became one line of this design, now shipped as
`Blueprint/Claude_Understanding_Driver.md`: a Claude driver that `supports('understanding.extract')`,
registered into the kernel. The router does the rest - validation gate, floor fallback, truthful
provenance. Epic 13 also added the pieces this sprint deferred: real `maxMs` enforcement (guarantee 5,
above), a strict-JSON prompt/parse contract with a tighter Claude-only grounding gate layered over the
kernel validator, and an explicit consent gate (the driver reports itself unavailable until the user
consents, so an unconsented attempt is never even routed to it). Every other task follows the same
path, one at a time, each behind its own validator.

## The second migration (DONE - Epic 14)
`briefing.compose` - the task this sprint declared but left fail-closed - is now **migrated**, exactly
the way `understanding.extract` was: `core/reasoning-local.ps1` registers a real `briefing.compose`
validator + floor delegate (it leaves the fail-closed list), the same Epic 13 Claude driver gains
`briefing.compose` support, and Tony's **Daily Executive Plan** (`Blueprint/Daily_Executive_Plan.md`)
is the one real client that reasons *through* the layer. No new task id, no new provider path, no
second registry - the kernel remains the only router, validator, fallback, timeout, and attribution
authority. The `briefing.compose` gate is the same "facts by machine" discipline: valid shape, allowed
sections only, every plan item's `sourceType`+`sourceId` grounds to a supplied Executive Context source
(no invented goals, appointments, deadlines, names, amounts, or commitments), no fabricated action
type, no provider may claim an action occurred, anything that would write is `requiresApproval`, and
**one unsafe item rejects the whole result** -> the local floor.

Epic 14 also added, additively, a **task-aware availability check**: alongside `isAvailable()`, a
provider may expose `isAvailableForTask(taskId)` (`Test-ProviderAvailableForTask` in the kernel), so
availability - and therefore consent - is decided **per task at routing time, before any data is
sent**. Executive-reasoning consent (for `briefing.compose`) is its own flag, distinct from onboarding's
`understanding.extract` consent; a driver that is consented for extraction but not for daily planning is
simply *not a candidate* for `briefing.compose`, and the floor answers. The check is additive - a
provider without it keeps its plain `isAvailable()` gate unchanged. Every remaining task still follows
the same path, one at a time, each behind its own validator.
