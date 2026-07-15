# Executive Reasoning Layer — test suite

Permanent, repeatable tests for the reasoning kernel (`core/reasoning-layer.ps1`)
and its deterministic floor (`core/reasoning-local.ps1`).

These tests were built while hardening the kernel against real bypasses found in
CTO review. They are not illustrative — **every hostile archetype in
`hostile-providers.tests.ps1` either defeated the kernel or seriously challenged
it.** Three of them (`edited-abuser`, `gate-switcher`, `context-mutator`) got a
fabrication *accepted* before the fix that this suite now locks in.

## How to run it

From this folder:

```powershell
.\Run-ReasoningTests.ps1
```

From anywhere:

```powershell
& 'C:\path\to\GIOK-HQ\tony-alpha\dashboard\tests\reasoning\Run-ReasoningTests.ps1'
```

If your shell blocks scripts (`running scripts is disabled on this system`), run
it the way the runner runs its own children:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File .\Run-ReasoningTests.ps1
```

Useful switches:

```powershell
.\Run-ReasoningTests.ps1 -Filter hostile   # only files matching *hostile*
.\Run-ReasoningTests.ps1 -Verbose          # stream every assertion, not just the summary
```

Any single file also runs on its own:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File .\hostile-providers.tests.ps1
```

**Exit code is 0 only if everything passed**, so the runner can be used from a
hook or CI without parsing the text. The whole suite takes roughly 30 seconds.

## What is in here

| File | What it protects |
| --- | --- |
| `hostile-providers.tests.ps1` | The canonical battery: all 23 hostile provider archetypes |
| `kernel-routing.tests.ps1` | Task ABI, request envelope, priority ordering, provenance, no-ambient-authority |
| `validator-failclosed.tests.ps1` | The privilege boundary: unmigrated tasks, structural checks, item grounding rules |
| `isolation.tests.ps1` | Payload / constraints / context cloning; drivers never share state |
| `limits.tests.ps1` | Re-entrancy guard and the result-size cap |
| `identity-transaction.tests.ps1` | The atomic identity write (all-or-nothing, roll back on failure) |
| `_harness.ps1` | Shared fixtures, assertions, and the sandbox. Not a test file. |

## The hostile archetypes

Preserved in `hostile-providers.tests.ps1`, in this order:

1. throwing provider
2. null provider
3. unsupported-task provider (plus: unavailable provider, throwing capability probes)
4. claims-everything / greedy provider
5. malformed result
6. missing required fields (plus: well-formed but sectionless)
7. fabricated `sourceAnswer`
8. fabricated number
9. fabricated person
10. fabricated company
11. fabricated date
12. unrelated interpretation with a real citation
13. **edited-abuser** — forges `edited=true` to skip the grounding gate
14. **gate-switcher** — rewrites `constraints` to turn the validator's own gate off
15. **context-mutator** — poisons the caller's context object
16. nested payload mutator
17. array clearer
18. mutate-then-null
19. mutate-then-throw
20. mutate-then-valid-looking result
21. excessive-result flood
22. recursive provider
23. **the valid accelerator that must pass**

Number 23 is not filler. Without it, every other test here would be satisfied by
a kernel that simply rejects everything. It is what makes the gate a gate rather
than a wall.

## Rules these tests follow

- **Never touch real data.** `_harness.ps1` overrides `Get-IdentityDir` to a
  throwaway `%TEMP%` folder, and `Assert-Sandboxed` refuses to run a single test
  if that override did not take. This matters: `identity.ps1` resolves the
  identity folder from `$PSScriptRoot`, which points at Jake's live runtime JSON.
- **No network, no API keys, no provider calls.** The kernel has no networking in
  it, and neither does this suite.
- **Process isolation.** Each test file runs in its own PowerShell process,
  because the provider registry is process-global state and a hostile driver
  registered by one file must not leak into the next.
- **Windows PowerShell 5.1, STA.** Same host the app runs under.

## Adding a new archetype

When a provider archetype defeats the kernel, add it to
`hostile-providers.tests.ps1` **in the same commit as the fix**. The fix and its
proof ship together, or the fix is just a claim.

Use `Assert-True` for anything that must hold. Use `Write-TestNote` for behaviour
that is recorded deliberately but is *not* a gate — for example, grounded
duplicates passing the kernel, which is correct because the review screen is the
dedup consent point.

## Things these tests deliberately do NOT claim

Being honest about the boundaries is part of the contract:

- **Drivers are not sandboxed.** They are trusted, in-process PowerShell. A
  driver *can* write files — `kernel-routing.tests.ps1` records exactly that. The
  kernel's guarantee is about **output**: a hostile driver cannot get a lie
  accepted, cannot poison anyone else's view of the request, and cannot stop the
  floor from answering. It is not a containment boundary.
- **`maxMs` is plumbing only.** It rides on every request so a future driver can
  honour it, but the kernel does **not** enforce it. `kernel-routing.tests.ps1`
  asserts this out loud so nobody mistakes the field for a deadline. Enforcement
  belongs with the first real driver.
- **Grounded duplicates pass.** Under the size cap, duplicate-but-grounded items
  are accepted by the kernel. Dedup is the review screen's job.
- **A single shared anchor word is enough** to satisfy the token-overlap rule.
  The gate rejects text that shares *nothing* with its citation; it is not a
  paraphrase-quality judge. Tightening this to a token-fraction threshold is
  driver-sprint work.
