# The Workforce Engine

## Tony manages specialists; Tony never becomes one

*Project Diamond, Sprint D20. The management layer that lets Tony delegate analysis to specialist
agents while remaining the single Executive Chief of Staff and the only executive decision maker.*

Implementation: `tony-alpha/dashboard/core/workforce-engine.ps1` (framework) and
`core/workforce-specialists.ps1` (the initial analysts), consumed by Tony Brain and presented by the
Claude provider in Tony's voice.

## The rule

Tony **manages** specialists. Specialists **analyze and recommend** - they never act, never store
anything, never talk to Jake directly, and cannot bypass Tony. Every report flows into Tony's merge
and only Tony's single synthesis reaches Jake. The Decision Framework keeps final authority over the
merged recommendation (Family before Financial, People before Money).

## The specialist interface (every specialist, the same shape)

A specialist is a registered object:

| Field | Meaning |
|---|---|
| `name` | e.g. "Email Analyst" |
| `purpose` | what it is for |
| `capabilities` | what it can do (string list) |
| `relevant(task)` | is this specialist relevant to the question? |
| `analyze(request)` | produce a **standard report** |
| `status()` | availability + detail |

A **standard report** (`New-SpecialistReport`) is identical across specialists:
`specialist · purpose · input · output · confidence · evidence · status · recommendedActions ·
assessment · scope · generatedAt`. Evidence items are `{ source, sourceId, detail }` - the same
source/source-id provenance the rest of GIOK uses.

## The workforce model (registry, like live providers)

```
Register-Specialist / Get-Specialists / Get-WorkforceRoster   -- the roster
Get-RelevantSpecialists(task)                                 -- who is relevant
Invoke-Specialist(name, request)                              -- assign one, get its report
Test-ReportAcceptable(report)                                 -- Tony rejects poor reports
Merge-SpecialistReports(reports, task, context)               -- Tony's synthesis (final authority)
Invoke-Workforce(task, context)                               -- delegate to all relevant + merge
Test-WorkforceRelevant(text)                                  -- should Tony delegate at all?
```

The registry mirrors the live-provider registry: specialists register; the engine consumes them
generically. Adding a specialist requires **no redesign** - it registers and Tony can use it.

## Delegation flow

```
Jake: "What happened overnight?"
  -> Tony Brain: Test-WorkforceRelevant -> yes, delegate
  -> Get-RelevantSpecialists -> Email Analyst, Calendar Analyst, Timeline Analyst, ...
  -> each Invoke-Specialist -> a standard report (using EXISTING provider output)
  -> Test-ReportAcceptable -> drop unavailable / low-confidence-without-evidence
  -> Merge-SpecialistReports -> one recommendation + evidence + conflicts + confidence
     (Decision Framework runs here and keeps final authority)
  -> claude-provider: Tony presents ONE recommendation, transparently naming the
     specialists used and the key evidence, in his own voice.
```

Only delegated (status / review / "what happened" / "catch me up") questions convene the workforce;
ordinary questions are answered by Tony directly - the conversation path is otherwise unchanged.

## Tony's decision rules

Tony (the merge) decides: **whether** to delegate (`Test-WorkforceRelevant`), **which** specialists
(`relevant`), **whether confidence is sufficient** (`Test-ReportAcceptable`, aggregate confidence),
**whether another specialist should verify** (`needsVerification` when a report is low-confidence),
and **whether Jake should see raw results** (`showRawToJake` on a conflict or low confidence). When
two specialists give opposing assessments on the same scope, the conflict is recorded and surfaced
for Jake to decide - Tony never hides a disagreement.

## Initial specialists (existing outputs only - no duplicate logic)

| Specialist | Uses | On this build |
|---|---|---|
| **Email Analyst** | `Get-Email` / the email signal | active |
| **Calendar Analyst** | `Get-Calendar` / the calendar signal | active |
| **Document Analyst** | Document Intelligence (`Invoke-DocumentIntelligence`) | active when a document is queued |
| **Priority Analyst** | the Executive Priority Engine (`Get-ExecutivePriorities`, D18) | activates when that engine is in the build |
| **Timeline Analyst** | the Executive Timeline (`Get-ExecutiveTimeline`, D19) | activates when that engine is in the build |

Each analyst **reads an existing provider output** (preferring the single Executive Context, falling
back to the provider function only when connected) - it never re-implements provider logic. The
Priority and Timeline analysts **wrap** the D18/D19 engines: when those engines are present they light
up; until then they report honestly that the capability is not in the build (never fabricated). This
is how the framework stays future-compatible with no redesign.

## Transparency (Jake always knows)

Tony's answer names **which specialists** were consulted, cites the **evidence** they reviewed (with
source provenance), and gives the **reasoning** for the conclusion. Low-confidence findings are
presented as leads, not certainties; conflicts are flagged; and Tony offers the raw specialist detail
when it matters. Nothing is invented - the provider is instructed to use only the merged findings.

## Future specialists (no redesign)

The same interface accepts future analysts without changing the engine: GoHighLevel Analyst, Finance
Analyst, CRM Analyst, Social Media Analyst, Health Analyst, Research Analyst, Travel Analyst, Phone
Analyst, Meeting Analyst. Each will register the same shape, read its own (future) provider output,
and merge into Tony's one recommendation.

## Single Source of Truth / privacy

- **No new database, no duplicate storage, no independent agent memory.** Specialists read existing
  provider outputs and the single Executive Context; they store nothing.
- **No duplicated provider logic** - analysts call the existing provider/engine functions.
- **No automatic actions** - specialists only analyze and recommend; Tony proposes, Jake decides.
- **Specialists cannot bypass Tony** - they return reports to the engine; only Tony's merged
  synthesis reaches Jake. The Executive Briefing is unchanged; the workforce is a conversational
  capability of the Brain.

## Constraints honored

Project Diamond, Single Source of Truth, Executive Context, Decision Framework (final authority), and
the Executive Briefing are all preserved; existing providers are not redesigned; storage is not
duplicated; no independent agent memories; Tony remains the only executive decision maker; the
framework supports future specialists without redesign.

## Related
- [Executive_Context_Engine.md](Executive_Context_Engine.md) - the single context specialists read.
- [Tony_Decision_Framework.md](Tony_Decision_Framework.md) - keeps final authority over the merge.
- [Tony_Brain.md](Tony_Brain.md) - convenes the workforce for delegated questions.
- [Gmail_Provider.md](Gmail_Provider.md) / [Google_Calendar_Provider.md](Google_Calendar_Provider.md) - outputs the analysts read.
- [Executive_Priority_Engine.md](Executive_Priority_Engine.md) / [Executive_Timeline.md](Executive_Timeline.md) - wrapped by the Priority / Timeline analysts when present.
