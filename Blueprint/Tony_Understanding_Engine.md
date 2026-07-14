# Tony Understanding Engine (Onboarding V2) - Epic 10

*Replace raw onboarding storage with an Understanding Engine that organizes the user's answers into
structured identity while preserving the user's original words. The 7-question interview is unchanged.
Nothing reaches Identity until Jake approves it.*

## The problem (what happens today)

`Complete-Conversation` (`core/first-conversation.ps1:194-210`) writes raw answer text **straight into
Identity** the moment the interview ends:

| Line | Today | Why it's wrong |
|---|---|---|
| :198 | `Set-IdentityValuesFromText -Text $areas` | the raw sentence becomes Values, split naively on `[\r\n;,]+` |
| :201 | `Set-IdentityGoalsFromText -Text $goal` | the raw sentence becomes Goals |
| :204 | `Set-IdentityMission -Statement $week` | the raw answer becomes the Mission statement verbatim |
| :206 | `Set-IdentityOverviewReflection` | prose reflection |

Three concrete defects:
1. **No understanding.** Raw text is copied in; a sentence like *"grow the agency and get healthy"* is
   split on commas only - it cannot become two goals unless the user happened to type a comma.
2. **No consent.** Identity is mutated before Jake sees anything. There is no review, no edit, no approval.
3. **Not atomic.** Each write is individually `try/catch`-wrapped, so a failure on write #3 leaves
   writes #1-2 applied - a half-written Identity with no rollback.

## Approach: a temporary Understanding Model, reviewed and approved, then written atomically

```
interview (unchanged)  ->  Understanding Model (temporary)  ->  "Here's what I understood"  ->  approve
   answers stay in            never touches Identity              review + edit per item        atomic write
   first_conversation.json                                                                      or full rollback
```

### 1. Engine: local baseline, Claude as optional enrichment  *(decision: hybrid)*

The interview today is explicitly offline ("no AI, no cloud, no APIs"), the Claude provider needs a
gitignored API key, and it has **no HTTP timeout** (`providers/claude-provider.ps1:355`) - which we may
not add, because this epic forbids provider changes. So the engine is layered:

- **Local deterministic extractor is the baseline** and always runs. Onboarding never depends on a
  network call, an API key, or a response that may never arrive.
- **Claude enriches only when configured**, is called *through the existing provider* (no provider
  change), never on the UI thread, and is strictly advisory: any failure, timeout, unconfigured state,
  or low-confidence answer falls back to the local result. The provider already returns
  `confidence 0.0` + an honest message when unconfigured (`claude-provider.ps1:419-422`), so this
  degrades cleanly.
- This preserves the existing `Get-TonyResponse` "swap for AI later" seam and the provider registry.

### 2. Confidence + bands: reuse the existing convention (do not invent one)

The codebase already has a uniform confidence pattern, and `core/conversational-capture.ps1:178`
already implements exactly the behaviour this epic asks for. We reuse it verbatim:

```
band = if ($clarify) { 'moderate' } elseif ($conf -ge 0.7) { 'high' } else { 'low' }
```

| Band | Meaning here | Behaviour |
|---|---|---|
| `high` (>= 0.7) | clearly supported by the answer | include in the model, shown for approval |
| `moderate` | ambiguous **or conflicting** | **ask one clarifying question; extract nothing** |
| `low` (< 0.7) | below threshold | **omit**; record in `omitted[]` so Tony can ask later |

Confidence is `[double]` 0.0-1.0, clamped and `[math]::Round(...,2)` - matching
`tony-provider-contract.ps1:82` and `workforce-engine.ps1:63`.

### 3. Never invent facts - including the honest empty case

Every item must be traceable to the user's own words. A category with no support stays **empty**.

Note the 7 questions ask about name, areas, goal, challenge, commitments, a successful week, and
boundaries - **none of them asks about Strengths**. So `strengths` will normally be empty, and that is
correct behaviour, not a bug. It only populates if the user volunteers a clear strength. This is the
sharpest test of "never invent facts".

Question -> category mapping (a question may feed more than one category; each item keeps its source):

| Question | Feeds |
|---|---|
| `q_name` | (name, used in the executive summary) |
| `q_areas` "three most important areas" | Priorities, Values |
| `q_goal` "biggest goal 6-12 months" | Goals (one sentence may yield several) |
| `q_challenge` "biggest challenge in your way" | Challenges |
| `q_protect` "commitments / non-negotiables" | Boundaries, Values |
| `q_week` "a successful week looks like" | Priorities |
| `q_boundaries` "never assume or do without asking" | Boundaries |
| *(none)* | **Strengths** - only if volunteered |

### 4. The Understanding Model (temporary, never a new store)

Held in the **existing** `first_conversation.json` under a `understanding` property - the conversation
store already owns the original responses, and this keeps resume working across a restart. It is
temporary: cleared once approved. No new file, no new database.

Item shape (every extracted item, all categories):

```
{ id, text, sourceQuestionId, sourceQuestion, sourceAnswer, reason, confidence, band, edited }
```
- `sourceQuestion` / `sourceAnswer` - the original question and the user's **original words**, verbatim.
- `reason` - why Tony extracted it (Tony's rationale, not the user's).
- `confidence` - internal score driving inclusion.

Model shape:
```
understanding: {
  meta:   { version, builtAt, engine: 'local' | 'local+claude', threshold, approvedAt }
  goals[], values[], priorities[], challenges[], strengths[], boundaries[]
  executiveSummary: { text, reason, confidence, sources[] }
  clarifications[]  # conflicts / ambiguity -> Tony asks, assumes nothing
  omitted[]         # below threshold -> Tony may ask later
}
```

### 5. Conflict -> clarification, never assumption

When two answers pull in opposite directions (e.g. a boundary forbids what a goal requires, or the same
topic appears with opposing sentiment), the engine emits a **clarification** and extracts nothing for
that item - band `moderate`, exactly as `conversational-capture.ps1:227-229` already does.

### 6. Where approved understanding is written  *(decision: extend overview.json)*

| Extraction | Destination | Notes |
|---|---|---|
| Goals | `identity/goals.json` | via the **existing enriched schema**, unchanged |
| Values | `identity/values.json` | existing shape |
| Executive Summary | `identity/overview.json` -> `tonyReflection` | existing field |
| Priorities, Challenges, Strengths, Boundaries | `identity/overview.json` -> **new `understanding` block** | no new file |

**`goals.json` records keep their exact current schema - provenance must NOT be added to them.**
`ConvertTo-NormalizedGoal` (`identity.ps1:105-126`) rebuilds each goal from an explicit field whitelist,
so any extra field is silently **stripped**; `Update-Goal:186` then persists that stripped list back to
disk. Adding `sourceQuestion` to a goal would therefore be deleted permanently by the first unrelated
Life OS edit. All provenance for every category (including goals) lives in `overview.understanding`,
linked to goals by id/title. Old `overview.json` without the block is back-filled on read, mirroring the
Life OS Stage 1 precedent.

### 7. Atomic write with full rollback

`Save-IdentityFile` (`identity.ps1:42-47`) is a plain `Set-Content` - not atomic, no rollback. The epic
requires all-or-nothing across up to three files. We add a transaction helper **without changing
`Save-IdentityFile`'s contract** (other callers must not regress):

```
Invoke-IdentityTransaction -Writes @{ 'goals.json' = $o1; 'values.json' = $o2; 'overview.json' = $o3 }
```
1. **Snapshot** every target's current raw content (recording "did not exist" where applicable).
2. Serialize **all** objects to JSON *first* - a serialization error aborts before any file is touched.
3. Write each file.
4. On **any** failure: restore every snapshot (delete files that did not previously exist), return
   `$false`. Identity is left exactly as it was.

Read-only until approval; the only mutation is this one transaction.

## UX: "Here's what I understood."

A new immersive review view, shown after the last question and **before** anything is written:
- One section per category. Each item shows **Tony's interpretation** alongside the **original answer**,
  plus why he extracted it.
- Each item is **editable** (`New-AuditInput`), and an edited item is marked `edited` - an edit is the
  user's own words and bypasses confidence entirely.
- Clarifications are surfaced as questions, not guesses. Omitted items are not shown as facts.
- Buttons: **"Tony got it right"** (approve -> atomic write) and **"Edit"**.
- Only on approval do we write, then mark the conversation complete and go Home.

The view is rebuilt each time (never cached) - `Set-ActiveView`'s cache whitelist deliberately excludes
views with editable inputs (`tony-ui.ps1:2762-2770`), and we honour that.

## Architecture guarantees
- **Single Source of Truth preserved.** Conversation keeps the original responses; Identity stores the
  structured understanding; nothing is duplicated.
- **No provider changes**, no agent changes, no new runtime database, no new permanent store.
- **Read-only until approval.** Atomic write on approval; complete rollback on any failure.
- The 7-question interview, its resume/save behaviour, and its double-click generation guard are untouched.

## What changes (files)
- `core/understanding-engine.ps1` - **new**: extraction, model, conflict detection, transaction.
- `core/first-conversation.ps1` - `Complete-Conversation` no longer writes Identity; it builds the model.
- `ui/tony-ui.ps1` - new review view + route; the closing button targets review instead of Home.
- `core/identity.ps1` - add `understanding` back-fill on overview read (no behaviour change elsewhere).
- Docs: this file; Project Status; Product Roadmap.

## Preserved / not touched
Providers, agents, Workforce, Executive Context, storage layout, the async worker, startup performance,
and the 11 local runtime-data files. No new persistent application data. `task_b9ec97bb` untouched.

## Verification plan
- One sentence -> multiple goals (the headline test).
- Raw answers never copied verbatim into Goals unless the user explicitly edited them that way.
- Conflicting statements produce a clarification, never an assumption.
- Below-threshold items are omitted and recorded for a later question.
- Strengths stays empty when unsupported (never invented).
- Nothing written before approval; atomic write on approval; rollback verified by forcing a failure.
- Onboarding stability, resume across restart, save behaviour, startup performance.
- Full app launch, parse, secret scan, regression suite.
