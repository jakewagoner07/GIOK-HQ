# Tony Alpha — Roadmap

Tony Alpha is being built in phases. The rule across all phases: **the command center's data and logic stay independent of any UI**, so later phases *wrap* the core rather than rewrite it.

---

## Phase 1 — Command center + registry ✅ (current)
Plain files in `tony-alpha/`. No integrations, no UI, no agent rebuilds.
- `agents_registry.json` — source of truth (data)
- `daily_status.md`, `weekly_status.md`, `issues_log.md`, `action_items.md` — views/reports
- `tony_summary.md` — overview

## Phase 2 — Automation (deferred)
Scripts that read `agents_registry.json` and regenerate the markdown views; live ingestion of `last_run`/`status` from the real scheduled tasks. Still no UI. (See `action_items.md` AI-101–103.)

## Phase 3 — Desktop launch (STARTED — Sprint Alpha)
Easy launch from a **Windows desktop icon**. First working desktop app delivered in
`dashboard/` (PowerShell + WPF; launched via `launch-tony.bat`). It reads
`agents_registry.json` live and renders the command center — proving Tony launches as a
real desktop application. Remaining for this phase: a real desktop-icon shortcut and
wiring the placeholder panels (issues/actions/sprint) to live data.

> Note: Sprint Alpha jumped ahead to this desktop proof before Phase 2 automation, at the
> owner's direction. Phase 2 (auto-regenerating views, live status ingestion) is still open.

## Phase 4 — Mobile / web access (deferred)
A **web dashboard** and/or **Android app** for on-the-go access. Reads the same core data over a small local API or synced store.

---

## Design principles that keep the core wrappable

These are already true of Phase 1 and must stay true:

1. **Data ≠ presentation.** `agents_registry.json` holds all state. Markdown files are *rendered views* of it. A desktop/web UI is just another renderer of the same JSON — no business logic lives in the views.
2. **One source of truth.** Never let a UI become a second place where agent state lives. Everything reads and writes `agents_registry.json`.
3. **Stable, documented schema.** The registry schema (`meta.status_values`, agent fields) is the contract any future wrapper depends on. Version it (`meta.version`) and avoid breaking changes.
4. **UI-agnostic core.** No file in the core assumes a terminal, a desktop, or a browser. This keeps the same core valid whether launched from a desktop icon or served to a phone.
5. **Local-first, portable.** Keep it as files in the repo so it works offline and can be packaged, synced, or served later without a migration.

---

## Not doing now (explicit)
- ❌ Desktop app / Windows launcher
- ❌ Web dashboard
- ❌ Android app
- ❌ Any integration or external service wiring

These are captured here so intent isn't lost — build order is Phase 1 → 2 → 3 → 4.
