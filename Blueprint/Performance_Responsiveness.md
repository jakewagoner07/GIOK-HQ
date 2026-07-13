# Performance & Responsiveness (Epic 9)

*Make GIOK feel fast at startup and while switching tabs. Measure first, optimize second - no
architecture change unless the numbers demand it.*

Companion measurement: `scratchpad/perf-profile.ps1` (timings + component names only; no private
content). This document records the measured baseline, the ranked bottlenecks, and the plan the data
justifies.

## Baseline profile (measured on Jake's connected setup)

Headless STA profiler, read-only provider fetches. Network-dependent numbers vary run to run; the
*ranking* is stable.

| Operation | Time | Kind |
|---|---:|---|
| **Executive Inbox tab (Set-ActiveView)** | **48,341 ms** | provider (scan) on UI thread |
| **Executive Inbox scan (Invoke-WorkforceProposals)** | **50,151 ms** | provider (specialists re-fetch) |
| **Communications aggregation (Get-Communications)** | **35,092 ms** | network (Gmail+Yahoo) |
| **Yahoo fetch (Get-YahooMessages)** | **20,303 ms** | network (IMAP) |
| **Gmail fetch (Get-Email)** | **9,980 ms** | network (multi-account) |
| **Calendar fetch (Get-Calendar)** | **4,970 ms** | network |
| **Full briefing compute (Get-TonyExecutiveBriefing, no providers)** | **3,886 ms** | compute |
| **Module load (dot-source 38 files)** | **2,933 ms** | startup |
| Executive Context (no live signals) | 739 ms | compute |
| Priority Engine | 379 ms | compute |
| Tony pre-LLM prep (context + prompt) | 321 ms | compute |
| Tab: Action Items / End of Day Audit / Agents | ~267-271 ms | compute (JSON + render) |
| Get-TonyContext (memory/JSON base) | 247 ms | file I/O |
| Get-TopObservations | 149 ms | compute |
| Home first paint (deferred) | 78 ms | UI |
| Timeline / Workforce / Executive Management engines | 31-54 ms | compute |
| Most local tabs (Identity, Family, Health, Financial, Learning, ...) | 14-123 ms | compute |

Duplicate-work counters for **one** Home briefing build: Executive Context 1x, memory base 1x,
Communications 1x, Gmail 1x, Calendar 1x, CRM 0x - **no duplication inside a single Home build.**
The real duplication is **cross-action**: the Home briefing and the Executive Inbox scan each fetch
the same providers independently.

## Root causes (what the numbers prove)

1. **Provider network latency dominates everything.** Yahoo IMAP (~20s), Gmail multi-account (~10s),
   Calendar (~5s). Every slow path is slow *because it fetches providers*: Communications (35s), the
   Home briefing (~39s end-to-end), and the Inbox scan (~48-50s).
2. **Heavy reads run on the WPF dispatcher thread.** The deferred Home briefing (Epic-8 fix) paints
   Home in ~78 ms but then runs the **entire** provider+context build as one `BeginInvoke` task on
   the UI thread - so the UI is frozen for tens of seconds *after* Home appears. The Executive Inbox
   tab runs its scan synchronously on click (~48s freeze).
3. **No cross-action cache.** Home and the Inbox scan re-fetch the same calendar/mail independently;
   nothing reuses a recent read.
4. **Views rebuild on every selection.** Repeated nav rebuilds each view (no cache). Local views are
   fast enough (14-300 ms) that this is minor, but the heavier ones (Action Items, Audit, Agents at
   ~270 ms) and any future heavier view benefit from caching.
5. **Startup module load is ~2.9s** before the window can appear - the main obstacle to a sub-second
   first window.

Compute is NOT the problem: context assembly, priority, timeline, workforce, and management are all
well under a second combined; the pure Executive Context is 739 ms.

## The plan (each item justified by a measured cost)

### Phase 2 & 5 - Move provider reads off the UI thread (justified: 35-50s UI-thread freezes)
Introduce a small **background-runspace helper** (`core/async-run.ps1`): run a read-only provider/
context build on a worker runspace that has the same modules loaded, then marshal ONLY the finished,
immutable result object back via `Dispatcher.BeginInvoke` to update the affected section. No WPF
object is touched off-thread. Home and the Inbox both show cached-or-placeholder content instantly;
navigation stays responsive while the worker runs; runspaces are tracked and disposed on window
close (no orphans/locks). Errors resolve to a calm degraded state.

### Phase 4 - Bounded in-memory signal cache (JUSTIFIED: providers are the cost, fetched by 2+ actions)
New `core/executive-cache.ps1`: one process-lifetime, **bounded** cache of expensive read-only
results (calendar, communications, CRM, and the assembled Executive Context signals). Not a database,
not persisted. Per-entry `fetchedAt` + TTL; `Get-CachedSignal` returns fresh instantly, returns the
last good value **marked stale** past TTL (and while a refresh runs), and triggers a single-flight
background refresh (no two concurrent refreshes of one source). Providers/Executive Context remain
the sole owners and the only code that actually reads the source - the cache only stores what they
return. Local-domain data (Life OS, Goals, Memory) is **invalidate-on-write**, never TTL'd.

Measured-justified starting TTLs (revisit against re-measured numbers, do not blindly apply all):
- Calendar 2 min · Communications (Gmail/Yahoo) 2 min · CRM 5 min (when connected) ·
  Life OS/Goals/Memory invalidate-on-write · Executive Context rebuilt from cached signals.

This alone removes the cross-action duplicate fetch (Home + Inbox share one recent read) and makes
the 2nd..Nth provider-dependent action effectively instant.

### Phase 3 - Per-view caching (justified: repeated nav rebuilds; heavier tabs ~270 ms)
Cache the rendered view **keyed by its owner's data-version**; reuse when unchanged, invalidate when
the owner writes. Cache view models/visuals only - never authoritative records, never editable input
state (views with live text input either opt out or cache only their static scaffold). Target:
unchanged tab switch effectively immediate.

### Phase 6 - Duplicate-work elimination (justified: Home vs Inbox independent fetches)
Route Home briefing, the Inbox scan, and Tony pre-LLM prep through the shared signal cache so one
user session fetches each provider at most once per TTL window. Confirm no double Gmail-summary and
no repeated specialist status checks within one action (baseline shows none inside Home; verify Inbox).

### Startup (module load 2.9s)
Measure whether load can be trimmed (e.g. deferring the heaviest provider modules until first use)
without breaking the dot-source contract. If a sub-second first window is not safely reachable given
the load cost, report the honest floor and the bottleneck rather than risk correctness.

## Targets (measure before/after; report honest results)
first window <1s · Home first paint <250 ms (already ~78 ms) · cached tab switch <150 ms ·
uncached local tab <500 ms (most already are) · no UI freeze >100 ms during provider refresh ·
cached pre-LLM prep <500 ms (already ~321 ms uncached).

## Invariants preserved
Single Source of Truth · owners-only writers · Executive Context architecture · Executive Inbox
approval gate · provider neutrality · mailbox/calendar/CRM strictly read-only · all local runtime
data untouched · all current tabs and functionality · no new user-facing features. The cache stores
only copies of what owners return and never becomes a second source of truth.

## Architecture note
The in-memory signal cache + background-runspace execution are the one **permanent architecture
addition** this epic introduces - and only because measurement proves 35-50s UI-thread freezes.
They will be recorded in the CTO Handoff. Everything else is localized optimization.

## Related
- [Executive_Context_Engine.md](Executive_Context_Engine.md) · [Executive_Briefing.md](Executive_Briefing.md)
  · [Executive_Inbox.md](Executive_Inbox.md) · [Workforce_Activation.md](Workforce_Activation.md)
  · [Communications](Yahoo_Provider.md) / [Gmail_Provider.md](Gmail_Provider.md)
