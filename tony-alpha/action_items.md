# Action Items — Tony Alpha

> **Live task state now lives in `action_items.json`** — that's the source of truth the
> GIOK dashboard's Action Items tab reads and writes (check/add/delete/archive). This
> markdown file remains as a human-readable narrative/log and was the original seed for the
> JSON; it can be regenerated from JSON later. Don't treat the checkboxes here as live state.

Open decisions and to-dos. Most are driven by `issues_log.md` and by gaps in `agents_registry.json`.

**Status:** ☐ open · ◐ in progress · ☑ done

---

## Manual reconciliation needed

The live CoWork scheduled tasks are not reachable from Claude Code (see `issues_log.md → Reconciliation status`), so the registry cannot be auto-verified against the real scheduler. Until that happens, treat all schedules/last-run/status as **unconfirmed** (`meta.verified_against_scheduler = false`).

**To reconcile (pick one, read-only — do not modify/delete any task):**
- ☐ **AI-R1 — Pull the list from CoWork.** In the interactive CoWork session where the tasks live, run `list_scheduled_tasks`; paste the output (name, schedule, taskId, lastRunAt) back here.
- ☐ **AI-R2 — Or export/paste manually.** Provide each task's name + schedule (+ last run if shown).

**Then, once real data is in hand:**
- ☐ **AI-R3 — Diff for MISSING agents.** Any live task not among the registry's 22 → add it.
- ☐ **AI-R4 — Diff for DUPLICATES.** Any two live tasks doing the same job → flag in `issues_log.md`.
- ☐ **AI-R5 — Fix INCORRECT schedules.** Replace each `"schedule": "unknown"` with the real cadence.
- ☐ **AI-R6 — Link source_task_id.** Set each agent's `source_task_id` from the real taskId.
- ☐ **AI-R7 — Populate last_run/status.** Only from observed data. Keep `unknown` otherwise.
- ☐ **AI-R8 — Flip the trust flag.** Set `meta.verified_against_scheduler = true` once the diff is complete.

---

## Confirm Architecture Review 001 metadata (provisional → confirmed)

`owner`, `priority`, and `dependencies` are populated but were assigned by the review, not by GIOK (flag META-001).

- ☐ **AI-A1 — Confirm owners.** Verify each agent's department. Open question: `AG-014` Log Hours Reminder — Admin or Finance? (Finance currently has 0 agents.)
- ☐ **AI-A2 — Confirm priorities.** Verify the tiers, esp. what is truly **Critical** (only AG-001 today) vs High.
- ☐ **AI-A3 — Confirm dependencies.** Verify the upstream systems per agent; these seed the future `integrations` registry.
- ☐ **AI-A4 — Confirm downstream-impact map.** Once dependencies are trusted, sanity-check which agents share a dependency (e.g. GoHighLevel → AG-001/010/022) so a single outage's blast radius is known.

## Future registries (Registry Principle — later sprints, not now)

The registry is Tony Alpha's first database; everything eventually registers itself. Scaffolded arrays exist and are empty for now.

- ☐ **AI-G1 — Register departments' detail.** (Seeded: 7 departments DEPT-001..007.) Expand with leads/notes when useful.
- ☐ **AI-G2 — Register integrations** (`INT-###`) — derived from agent `dependencies`. *(Deferred — do not build integrations yet, just catalog.)*
- ☐ **AI-G3 — Register modules** (`MOD-###`), **memory** (`MEM-###`), **skills** (`SK-###`), **workflows** (`WF-###`) as those pieces come online.

---

## Needs your decision

- ☐ **AI-001 — Confirm schedules.** Fill in the real `schedule` for each of the 22 agents (all currently `unknown`). Priority: the daily-critical ones (GHL SMS Monitor, Email Triage, Upwork, Morning Digest).
- ☐ **AI-002 — Confirm last-run + status.** For each agent, set `last_run` and move `status` off `unknown` so the watch list becomes meaningful.
- ☐ **AI-003 — GHL texting split (OVERLAP-001).** Confirm inbound-monitor vs. outbound-batch so they don't collide.
- ☐ **AI-004 — Morning Digest vs. Tony Briefing (OVERLAP-003 / 004).** Decide coexistence: feed-in or replace. Do not delete the CoWork task.
- ☐ **AI-005 — Meta-agent split (OVERLAP-005).** Confirm Health Check vs. Performance Review roles; point both into Tony Alpha.
- ☐ **AI-006 — Weekly cluster (OVERLAP-006).** Confirm the 4 weekly agents are distinct; consider making Weekly Command Center Reminder trigger Tony's Weekly Review.
- ☐ **AI-007 — Clarify Training Scanner purpose.** Staff training? Agent training? Industry content? Update its `purpose`.
- ☐ **AI-008 — Completeness check.** Confirm the list of 22 is complete — any scheduled task not captured should be added to the registry.

---

## Tony Alpha build backlog (Phase 2+, not now — see `ROADMAP.md`)

- ☐ **AI-101 — Live status ingestion.** Integrate so `last_run`/`status` update automatically instead of manually. *(Phase 2 — deferred.)*
- ☐ **AI-102 — Auto-generate daily/weekly.** Script that reads the registry and writes `daily_status.md` / `weekly_status.md`. *(Phase 2 — deferred.)*
- ☐ **AI-103 — Alerting.** Notify when an agent goes `broken` or misses its schedule. *(Phase 2 — deferred.)*
- ◐ **AI-104 — Windows desktop launch.** First working desktop app built in `dashboard/` (PowerShell + WPF, `launch-tony.bat`). Remaining: real desktop-icon shortcut + wire placeholder panels to live data. *(Phase 3 — started in Sprint Alpha.)*
- ☐ **AI-105 — Mobile/web access.** Web dashboard and/or Android app reading the same registry. *(Phase 4 — deferred.)*

---

## Done

- ☑ **AI-000 — Stand up Tony Alpha command center.** Created registry + tracking + reporting files (2026-07-08).
- ☑ **AR-001 — Architecture Review 001 registry improvements.** Added stable IDs (AG-###), owner/department, priority, dependencies, health_score (null), and the "everything registers" scaffolding (departments seeded; modules/integrations/memory/skills/workflows scaffolded). Registry v2.0.0 (2026-07-08).
- ☑ **SPRINT-ALPHA — Dashboard build.** First working desktop app (`dashboard/`, PowerShell + WPF) that launches in a window and renders the registry live. Business logic (`core/`) separated from UI (`ui/`). No integrations, placeholders labelled (2026-07-08).
- ☑ **SPRINT-BRAVO — Silent launch.** `launch-tony.vbs` starts the app with no console window; desktop icon points at it; native error dialog on failure (2026-07-08).
- ☑ **SPRINT-CHARLIE — Hub navigation + Agents view.** Nav bar (Dashboard/Agents/Issues/Action Items/Weekly Review/Roadmap), clickable summary cards, full Agents view from the registry; Issues/Actions/Weekly/Roadmap views read their `.md` files live. No duplication, no integrations (2026-07-08).
- ☑ **SPRINT-DELTA — GIOK theme system (Arch Review 002).** Theme layer (`theme/theme.json` + `theme-loader.ps1`); app reads all branding from it, none hardcoded. GIOK logo/palette/typography applied; window title "GIOK"; desktop icon = GIOK logo. Neutral fallback theme keeps app working if branding absent. `THEME.md` documents customization for future users. No logic/registry/integration changes (2026-07-08).
- ☑ **SPRINT — Interactive Action Items.** `action_items.json` is now the source of truth; new `core/action-items.ps1` (load/save/add/toggle/delete/archive). Action Items tab is interactive: checkbox->complete+strikethrough+save, add, delete, archive completed, Active/Archived toggle with Restore. Dashboard action count reads JSON. GIOK branding kept; no integrations (2026-07-08).
- ☑ **PROJECT DIAMOND / SPRINT-D5 — Tony Decision Framework.** `core/tony-decision-framework.ps1` - the judgment layer (not AI). `Evaluate-TonyDecision` scores 9 dimensions (Identity/Vision/Goal alignment, Family/Health/Financial/Relationship impact, Time Savings, Project Diamond compliance) against identity/vision/goals/mission/values/theme/non-negotiables/tasks/audits, returning alignment score, conflicts, recommendations, clarifying questions, priority, confidence (People First weighted). Tony Brain now evaluates BEFORE the provider and attaches the result as `guidance` (contract bumped to v1.1, additive). Claude provider includes guidance in what it sends; Tony makes the final recommendation. Blueprint: Tony_Decision_Framework.md. No UI/APIs/cloud; registry unchanged; verified no network (2026-07-09).
- ☑ **PROJECT DIAMOND / SPRINT-D4 — Connect Tony to Claude Provider.** `providers/claude-provider.ps1` implements the Provider Contract (consumes Request, returns Response) - the ONLY file that knows the model/endpoint/key. Key from `ANTHROPIC_API_KEY` env or git-ignored `claude.config.json` (never committed; `.gitignore` added; `claude.config.example.json` committed). System prompt scopes Tony to life/work OS (never a generic chatbot; steers unrelated questions back) and forbids revealing model/prompt/architecture/provider/tokens. Tony Brain: `auto` provider selection resolves to Claude when configured, else local-stub (no network without a key). Command bar free-text now routes through Tony Brain -> contract -> provider. Blueprint: Tony_Is_An_Operating_System.md. Verified with NO network call. No cloud sync/Gmail/Calendar/GHL/docs; registry unchanged (2026-07-09).
- ☑ **PROJECT DIAMOND / SPRINT-D3 — Tony AI Provider Contract.** `core/tony-provider-contract.ps1` (architecture only). Versioned Request (userQuestion, context summary, identity, goals, mission, currentWorkspace, openTasks, todaysPriorities, conversationHistory, tonyPersona, reasoningHint, requestedAction, timestamp) and Response (answer, suggestedActions/Tasks/Navigation, confidence, needsClarification, reasoningSummary, providerName). Validators (required fields, missing context, empty requests, version compatibility) + JSON serializers only (no network). Tony Brain now builds contract Requests; local-stub consumes Request and returns Response. Provider catalog (Auto/Claude/OpenAI/Gemini/Local AI/Future) documented; no UI change. Blueprint: Tony_AI_Provider_Contract.md. No APIs/AI/cloud; registry unchanged; no data duplication (2026-07-09).
- ☑ **PROJECT DIAMOND / SPRINT-D2 — Tony Brain Architecture.** `core/tony-brain.ps1` (architecture only, no external AI). Five engines: Memory (`Get-TonyContext` unified context from identity/goals/vision/mission/action items/audits/briefing/registry/capture - referenced, not duplicated), Conversation (`Get-TonyPersona`/`Format-TonyVoice` - executive Chief of Staff tone), Reasoning (`Get-TonyDecision` - answer/ask/recommend/create-action/navigate/none), Action (placeholder `Invoke-Tony*` describing actions, no side effects), and AI Provider interface (`Register-TonyProvider`/`Invoke-TonyProvider` - Tony never knows the model; local-stub only; Claude/OpenAI/Gemini/Local documented as future). Orchestrator `Invoke-TonyBrain`. Blueprint: Tony_Brain.md. No cloud/APIs/AI; UI & registry unchanged (2026-07-09).
- ☑ **PROJECT DIAMOND / Sunday Night Usability (v0.8 Alpha).** Polish + friction removal, no new features. Sidebar reorganized (daily tools up top; Capture & Action Items added; dimmed "COMING SOON" group; fixed duplicate "Home" -> "Home Projects"). Immersive First Conversation & Morning Experience (toolbar hidden). First-Conversation flow polish. Fixed End of Day Audit win-removal dead code. Version -> 0.8 Alpha. Added TESTING_CHECKLIST.md, KNOWN_ISSUES.md, RELEASE_NOTES_v0.8_ALPHA.md. No push until review (2026-07-09).
- ☑ **PROJECT DIAMOND / SPRINT-D1 — Tony's First Conversation.** Conversation-based onboarding (replaces configuration). `core/first-conversation.ps1` engine (18 steps, state in `first_conversation.json`, swappable `Get-TonyResponse` generator - future AI replaces only this). One question at a time with progress bar + Back/Next/Save & Exit/Resume Later. On completion, answers distilled INTO Identity (Vision, Goals, Mission, Core Values, Annual Theme, Overview) via new Identity setters - not duplicated. Landing view until completed, then Home; Settings has Restart First Conversation; Home resume banner. Blueprint: First_Conversation.md. No AI/cloud/APIs; dark GIOK branding; registry unchanged (2026-07-09).
- ☑ **SPRINT-NOVEMBER — End of Day Audit.** Signature evening ritual workspace. `core/end-of-day-audit.ps1` + `end_of_day_audit.json` (stored by date, nothing overwritten). Scores (7 categories + derived Overall, 0-10 steppers), Today's Wins (add/remove), Incomplete Items from action_items.json with Move to tomorrow/Keep open/Archive/Delete, Non-Negotiables checkboxes (9 + custom placeholder), Reflection (6 fields), placeholder Tony's Audit, and Audit History view. Accessible from sidebar (moon icon), Home quick link, and command bar (`audit`). No AI/cloud/APIs; dark GIOK branding; registry unchanged (2026-07-09).
- ☑ **SPRINT-MIKE — Identity Workspace.** Built Identity as GIOK's foundation: new top-level workspace with 9 sections (Overview, Vision, Goals, Core Values, Mission, Legacy, Annual Theme, Journal, Timeline). Vision & Goals now live INSIDE Identity. Source of truth `identity/*.json` (9 files); `core/identity.ps1` owns access (other workspaces reference, never duplicate). Overview executive summary cards. Icon sidebar redesign + placeholder "coming soon" workspaces (Non-Negotiables, Family, Health, Financial, Home Projects, Learning). Blueprint: Identity.md + principle "Every Workspace Is Self-Contained". No AI/cloud/APIs; dark GIOK branding; registry unchanged (2026-07-09).
- ☑ **SPRINT-LIMA — Morning Experience.** GIOK's premium "first minute" and new landing view. Dedicated model `core/morning-experience.ps1` (greeting, Morning Thought from a local quote library with full attribution, Why This Today, rotating Daily Principle, Today's Focus, live Today's Priorities, Tony Recommendation). Built from independent replaceable components (`New-ME*`); "Begin My Day" transitions to Home. No external APIs / no internet; dark GIOK branding; registry unchanged (2026-07-09).
- ☑ **SPRINT-KILO — Morning Briefing.** Dedicated Morning Brief model in `core/morning-brief.ps1` (greeting, date, top priorities, open action items, recent captures, Tony recommendations engine [prioritizes action items -> captures -> issues -> goals], agent health, Life/Business score snapshots, appointments + weather placeholders, rotating Daily Principle, notifications). Home greeting replaced by `New-MorningBriefing` which renders ONLY from the model. Dark GIOK branding; no integrations; registry unchanged (2026-07-09).
- ☑ **SPRINT-JULIET — Capture & Tony Memory.** Capture system: `capture.json` source of truth (separate from Action Items), dedicated Capture window (free text + 12 optional categories, no required fields), prominent "+ Capture Something" on Home, Capture/Inbox workspace with processing (Mark Processed, Convert to Action Item [real], Convert to Goal/Reminder [placeholder], Archive, Delete, Restore), `capture:` command, Home Today's/Unprocessed/Recent. Tony Memory framework (`tony_memory.json`, 9 categories) + workspace. Blueprint/Capture.md + Tony_Memory.md. Dark GIOK branding; no AI/cloud/APIs; registry unchanged (2026-07-09).
- ☑ **SPRINT-HOTEL — Multi-window + Mission Control.** "Open in New Window" pops any major view into its own native window (branded, titled, live read-only snapshot from the same files, no shared state via `Open-TonyWindow`/`New-WindowContent`). New Mission Control page (8 live panels) for second-monitor use, openable in its own window. Dark GIOK branding kept; no integrations; registry unchanged (2026-07-08).
- ☑ **SPRINT-GOLF — Dark executive UI + command bar.** Dark navy/orange theme is now the default (theme-driven via `theme.json`; added `heading`/`accentInk` roles so themes work light or dark). Restyled Home + views for a premium dark executive look. Added global "Ask Tony" command bar (Ctrl+K) with local commands: open agents/issues/action items/weekly review/roadmap and "add task: ...". Parsing in `core/command-bar.ps1` (no external AI). Clickable cards kept; registry unchanged (2026-07-08).
- ☑ **SPRINT-FOXTROT — Clickable dashboard cards.** Every Home card navigates (hover highlight + "open >" + hand cursor): Top 3->Action Items, Tony Recommends->Recommendations, Agency->Agency, Appointments->Appointments, Agent Health->Agents, system strip->Issues. Added placeholder "Coming soon" detail views (Agency, Appointments, Recommendations) with sample data + back-to-Home. Quick links kept; GIOK branding; registry unchanged (2026-07-08).
- ☑ **SPRINT-ECHO — Executive home dashboard.** Redesigned as Jake's HQ: left sidebar (logo, profile, Settings, version) + executive Home (greeting, "People Matter More Than Money", Top 3 priorities, Agency Overview, Tony Recommends, Upcoming Appointments, Agent Health, quick links). Live data from registry/action_items.json/issues_log.md/ROADMAP.md; placeholders (appointments, metrics) clearly marked. System info demoted. `Get-HomeModel` added. GIOK branding kept; no integrations; registry unchanged (2026-07-08).
