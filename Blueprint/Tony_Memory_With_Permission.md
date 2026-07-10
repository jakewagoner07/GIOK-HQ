# Tony Memory, With Permission

## Trust is earned by asking

*Project Diamond, Sprint D12. Tony becomes more helpful without ever becoming intrusive.*

Implementation: `tony-alpha/dashboard/core/memory-manager.ps1` (the only write path), the Memory
Review in the "Tony" workspace, and the permission prompt inside Talk with Tony.

## Purpose

Tony should get better at helping Jake over time - but **never by quietly building a dossier**. The
rule is absolute: *Tony never creates a permanent memory without the user's explicit permission.*
When Tony notices something that could improve future recommendations, he does not save it. He
**asks**:

> "This seems like something that could help me make better recommendations in the future. Would
> you like me to remember it?"

The user answers with one of four choices: **Remember · Edit · Not Now · Never Ask Again**. Only
"Remember" (or "Edit" then save) writes anything.

## Memory categories

Identity · Goals · Preferences · Work Style · Communication Style · Business · Health · Family ·
Learning · Relationships · Projects.

## Architecture

```
memory-manager.ps1   (core)  <-- the ONLY write path for permanent memory
  detection:   Find-MemoryCandidates (surfaces candidates; NEVER saves)
  permission:  New-MemoryPermissionPrompt, Test-MemoryShouldAsk, Set-MemoryNeverAsk
  write path:  Approve-Memory (Remember), Update-Memory (Edit), Remove-Memory (Delete),
               Set-MemoryStatus (Disable/Enable), Export-Memories
  reads:       Get-Memories, Get-MemoryContextLines

Talk with Tony (ui)  -> after a reply, offers the permission prompt with the four choices
Memory Review  (ui)  -> the "Tony" workspace: every memory, with full user control
Executive Context Engine -> READS approved memories (Get-Memories); never writes them

Source of truth: tony_memory.json (local, gitignored - private). One store. No duplicate storage.
```

**The Memory Manager is the single write path. Nothing else writes memory.** The Executive Context
Engine reads it; the UI calls into it; no other module touches the store.

## Data flow

1. In a conversation, the user says something durable ("I prefer morning calls before 10am").
2. `Find-MemoryCandidates` surfaces a **candidate** - category, value, and *why it would help*. It
   **saves nothing**.
3. If the candidate isn't already known and isn't on the "never ask again" list, Tony shows the
   permission prompt with four choices.
4. On **Remember**, `Approve-Memory` writes it (status active, timestamped, with its source). On
   **Edit**, the user adjusts the value first. **Not Now** does nothing. **Never Ask Again** records
   the signature so Tony stays quiet about it - still saving nothing.
5. The **Executive Context Engine** then reads approved memories on future turns, so Tony's
   recommendations reflect what he was *allowed* to remember.

## Trust model

- **The user owns their data and their memories.** Tony earns trust by asking, never by assuming.
- **No hidden memories.** Every memory is visible in Memory Review with its value, category, when
  it was created, why Tony kept it, and the source. Detection that surfaces a candidate writes
  nothing until the user says yes (verified: booting the app makes no write).
- **Private by default.** The store is local and gitignored - memories never leave the machine, no
  cloud.
- **Tony must never**: create hidden memories, modify memories without permission, delete memories
  automatically, or guess permanent preferences.

## User control

The Memory Review (the "Tony" workspace) shows every memory and lets the user:

- **Edit** - change the value inline.
- **Disable / Enable** - keep a memory but stop Tony using it (disabled memories are excluded from
  the Executive Context).
- **Delete** - remove it permanently.
- **Export** - write a JSON copy the user keeps.

Nothing here is destructive without an explicit click, and nothing happens automatically.

## Why this is Single Source of Truth

There is exactly one memory store (`tony_memory.json`) and exactly one writer (the Memory Manager).
The Executive Context Engine and the UI only ever *read* through `Get-Memories`, so there is no
second copy to drift. Disabled memories stay in the one store with a status flag rather than being
duplicated elsewhere.

## Future expansion

- **Smarter, still-permissioned detection** - a future model can propose better candidates, but the
  ask-first gate never moves.
- **Confidence and decay** - memories could carry confidence and a "still true?" check-in, always
  user-confirmed.
- **Categorized review** - filter and group the review by category as memories grow.
- **Memory-aware briefings** - the Executive Briefing can gently reflect approved preferences
  (e.g. protecting the morning block Jake told Tony he prefers).

## Constraints honored

No cloud, no new integrations, no registry changes, no duplicate storage, no automatic writes, no
hidden memories. The only writes happen when the user explicitly approves.

## Related
- [Tony_Memory.md](Tony_Memory.md) - the earlier structured-memory framework this supersedes for storage.
- [Executive_Context_Engine.md](Executive_Context_Engine.md) - reads approved memories.
- [Tony_Conversation.md](Tony_Conversation.md) - where Tony asks permission.
- [13_Project_Diamond.md](13_Project_Diamond.md) - trust is the experience; ask, never assume.
