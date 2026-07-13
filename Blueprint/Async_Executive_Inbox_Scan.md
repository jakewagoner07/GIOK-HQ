# Async Executive Inbox Scan (Performance Follow-Up)

*Move the existing Workforce proposal scan off the WPF UI thread so opening or refreshing the
Executive Inbox stays responsive - without weakening a single approval-gate guarantee.*

Follow-on to [Performance_Responsiveness.md](Performance_Responsiveness.md) (CTO review finding #3).
No new feature, tab, provider, store, or architecture - it reuses the Epic-9 worker runspace and the
existing Workforce producers.

## The problem (measured)
Provider latency is now cached, so the ~48s cold Inbox scan is ~6s warm. But `Invoke-WorkforceProposals`
still runs **entirely on the dispatcher**: it generates candidates (heavy, read-only) *and* writes the
surviving proposals (`Add-InboxProposal`) on the UI thread. Clicking Executive Inbox can still feel
frozen for the compute.

## The one idea: split analysis from commit
`Invoke-WorkforceProposals` already has two phases. We separate them (reusing the exact logic, no
duplication):

1. **`Get-WorkforceProposalCandidates`** (READ-ONLY) - build the Executive Context, run the specialist
   producers (Sam/Ava/Riley/Emma/Randy/Mason), return the raw candidate list. This is the ~6s part and
   it **writes nothing**. Safe to run on the background worker.
2. **`Add-WorkforceProposalCandidates`** (WRITES) - the EXACT existing gate (confidence floor,
   in-scan dup, already-pending, already-in-owner, per-scan cap) followed by `Add-InboxProposal` for
   survivors. Runs **only on the UI/owner thread**, sequentially.
3. **`Invoke-WorkforceProposals`** becomes a thin wrapper `= Get-... | Add-...`, so every existing
   caller and the synchronous/headless path are byte-for-byte unchanged.

**Write-safety model (the hard rule):** proposal writes **never** happen on a background runspace. The
worker only *analyzes* (read-only, proven by an mtime audit) and returns immutable candidate data; the
existing inbox owner commits on the UI thread. Because approvals and commits both run on the single
dispatcher, there is no concurrent inbox writer and no cross-thread write race. The dedup gate runs at
**commit time** against the current inbox, so idempotency holds even if state changed while analyzing.

## The flow (matches the recommended flow exactly)
1. Open Executive Inbox / click "Check for new proposals".
2. **Existing pending proposals render immediately** (no blocking scan before the render).
3. A small non-blocking **"Checking for new proposals..."** line shows while a scan runs.
4. `Get-WorkforceProposalCandidates` runs **off the dispatcher** on the Epic-9 worker (shared signal
   cache reused, so a warm briefing makes this fast).
5. Candidates return to the UI thread via the `DispatcherTimer` completion (Epic-9 `Start-AsyncWork`).
6. `Add-WorkforceProposalCandidates` commits survivors on the UI thread - sequential, deterministic,
   same dedup + caps as before.
7. The view **refreshes only if Executive Inbox is still active**.
8. If Jake navigated away, candidates are still committed safely (owner thread), but **no stale UI
   element is touched** (active-view check before refresh).
9. If the app closes mid-scan, `Stop-AsyncWorkers` disposes the worker; the scan aborts **before** any
   commit, so nothing is half-written (next open re-scans idempotently).
10. **Single-flight / coalesce:** a `$script:InboxScanning` flag - repeated opens/clicks while a scan is
    running are ignored (only one scan at a time).

## Safety invariants (unchanged)
Executive Inbox stays pending-only; specialists only *propose*; Jake approves/edits/rejects; owning
modules remain the only domain writers; no auto-approval; **deterministic dedup + scan caps preserved**
(same gate, just moved to commit time); Single Source of Truth held; **no simultaneous scans**; no lost
or duplicated proposals on navigate-away/close; all local runtime data untouched. Diagnostics stay
component/timing/count/error-class only - never a title or key (which can embed a subject line).

## GetNewClosure discipline
The completion callback captures locals only; every shared-state read/write (`InboxScanning`,
`InboxMsg`, active-view, refresh) goes through a **function**, because inside a `GetNewClosure` body
`$script:*` resolves to the closure's own empty scope (the Epic-8/9 lesson). Functions are unaffected.

## Verification
Existing proposals display immediately; opening stays responsive; navigation works while scanning;
rapid clicks start ONE scan; the scan creates the SAME proposals as before; a second scan is idempotent;
navigate-away mid-scan = safe commit, no stale UI; close mid-scan = no orphan runspace / no corruption;
inbox-file lock degrades to a calm message; writes remain sequential; approve/edit/reject, Workforce
Activation, and Conversational Capture all still work; full app launch; parse; secret scan; git integrity.

## Related
- [Executive_Inbox.md](Executive_Inbox.md) · [Workforce_Activation.md](Workforce_Activation.md)
  · [Performance_Responsiveness.md](Performance_Responsiveness.md)
