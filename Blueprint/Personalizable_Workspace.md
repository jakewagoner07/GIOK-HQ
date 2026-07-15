# Personalizable Workspace - Epic 11

*Two changes, one principle: the user's own data comes first, and the layout is theirs. No data
architecture changes, no second stores, no new providers or agents, no new dashboard tab.*

## Part 1 - Goals workspace: goals first, form on demand

### What is wrong today
`New-GoalsView` (`ui/life-workspaces.ps1:572`) builds the page in this order:

| Line | Today |
|---|---|
| :604 | **"Add a goal" card** - five inputs, dominates the fold |
| :610-616 | Active / Done toggle |
| :624 | the user's actual goals |

So the first thing you see on your Goals page is a blank form, not your goals. Two more defects found
while reading it:
- **Delete has no confirmation** (`:672`) - one mis-click calls `Remove-Goal` and the goal is gone.
- **Filtering is one binary toggle** (active vs done/archived). There is no domain filter, and status is
  collapsed into two buckets even though the store has four (`active/paused/done/archived`).

### What changes
- **Goals render first.** A small **`+ Add Goal`** button sits on the header row next to the title.
- The add form appears **only** after that button is clicked (`$script:GoalAdding`), and **Cancel**
  closes it without touching data.
- Each goal row keeps showing: title, domain, target date, next step, status, progress.
- Actions: **Edit / Pause / Resume / Complete / Archive / Restore / Delete**, with Delete now behind a
  **confirm step** (`$script:GoalDeleteId` -> "Delete this goal? [Yes, delete] [Cancel]").
- **Filters: domain and status**, as two chip rows (`All` + each `Get-GoalDomains` / `Get-GoalStatuses`
  value), held in `$script:GoalFilterDomain` / `$script:GoalFilterStatus`.

### What does NOT change
The goal store and its owner functions are untouched: `Get-GoalsList`, `Get-ActiveGoals`, `Add-Goal`,
`Update-Goal`, `Set-GoalStatus`, `Set-GoalProgress`, `Complete-Goal`, `Archive-Goal`, `Restore-Goal`,
`Remove-Goal`, `Get-GoalDomains`, `Get-GoalStatuses` (all `core/identity.ps1`). **One store**:
`identity/goals.json`. This is a view-layer change only - the Priority Engine and Executive Context keep
reading the same goals.

## Part 2 - Customizable Home

### Preference model (the ONLY thing we store)
```json
{ "meta": { "version": "1.0.0" },
  "cards": [ { "id": "briefing", "visible": true, "order": 1, "size": "large" }, ... ] }
```
Exactly **id / visible / order / size** per card - nothing else. No goals, no family items, no
appointments, no CRM data, no briefing text. `meta.version` is the house convention for every store here
and carries no business data.

**File:** `tony-alpha/home_layout.json` - **gitignored, user-specific, local**. It holds preferences,
not business data, so it is not a "second store" of anything. If it is missing or corrupt, the default
layout is used and nothing else is affected.

### Card catalog - every card reads from its EXISTING owner
No card owns data. Each one calls the owner and navigates to that owner's workspace.

| id | Card | Owner call (read-only) | Cost | Default |
|---|---|---|---|---|
| `briefing` | Tony's Executive Briefing | existing deferred/async build | deferred | **on**, large, always |
| `capture` | Capture Something | `Get-CaptureStats` | cheap | **on**, large |
| `inbox` | Executive Inbox | `Get-InboxSummary` | cheap | **on**, small |
| `goals` | Goals | `Get-ActiveGoals` | cheap | **on**, small |
| `agentHealth` | Agent Health | `$Model.agentHealth` | cheap | **on**, small |
| `agency` | Agency Overview | `$Model.agencyMetrics` *(SAMPLE)* | cheap | **on**, small |
| `appointments` | Upcoming Appointments | `$Model.appointments` *(SAMPLE)* | cheap | **on**, small |
| `family` | Family | `Get-LifeItems -Domain family -ActiveOnly` | cheap | off, small |
| `nonNegotiables` | Non-Negotiables | `Get-LifeItems -Domain nonNegotiables` | cheap | off, small |
| `health` | Health | `Get-LifeItems -Domain health` | cheap | off, small |
| `financial` | Financial | `Get-LifeItems -Domain financial` | cheap | off, small |
| `learning` | Learning | `Get-LifeItems -Domain learning` | cheap | off, small |
| `projects` | Projects | `Get-LifeItems -Domain projects` | cheap | off, small |
| `communications` | Communications | `Peek-CachedSignal -Key communications` | cheap | off, small |
| `crm` | CRM | `Peek-CachedSignal -Key crm` (+ `Get-CRMSummary` on the cached value) | cheap | off, small |
| `priorities` | Weekly Priorities | `Get-TonyExecutiveContext` + `Get-ExecutivePriorities` | **~0.7s** | off, medium |

**Paint safety is the rule that shapes this table.** Provider cards use **`Peek-CachedSignal`**
(`core/executive-cache.ps1:99`), which returns `{value, present, stale}` and **never fetches**. The
fetch-through getters (`Get-CommunicationsSignal` / `Get-CalendarSignal` / `Get-CrmSignal`) block on a
cache miss - Communications alone is Gmail ~10s + Yahoo IMAP ~20s - and are **never** called from a
card. A provider card with `present=$false` says so honestly ("not loaded yet") instead of fetching.
`priorities` is the one non-trivial card (~0.7s to assemble context) and is therefore **off by
default**; it is the user's choice to pay for it.

**Honest note on two existing cards:** `Agency Overview` and `Upcoming Appointments` render *placeholder*
data from `Get-HomeModel` (`core/tony-core.ps1:205-209`, `source='placeholder'`), already tagged
`SAMPLE` on screen. Epic 11 does not change what they show - replacing fiction with the real calendar is
a separate concern and would be a data change, which this epic forbids. They are listed here as-is.

**Communications and CRM have no registered view**, so their cards carry no `NavTo` (a bad `NavTo`
silently falls through to Home). Every other card navigates to its real workspace.

### Default layout
The default is **today's Home** (briefing, capture, agency, appointments, agent health) **plus Goals and
Executive Inbox** - both cheap, both core to the product, both named in the epic. A brand-new user with
no preferences file sees exactly that. Everything else is available but off, so Home stays calm.

### Layout rules
- `size`: `small` (1/3), `medium` (1/2), `large` (full width) - rendered by column span in a 6-column
  flow grid, packed left-to-right and wrapping when a row fills.
- `briefing` and `capture` are **fixed large** (a letter and a banner do not read as a third-width tile);
  every other card is sizeable. This is the "where practical" in the brief.
- **Never a blank Home:** if the user hides everything, `Get-HomeLayout` forces `briefing` visible. This
  is enforced in the model, not the UI, so it cannot be bypassed.
- Unknown ids in the file are dropped; newly shipped cards appear with their catalog defaults. So an old
  preferences file never breaks a new build.

### Not interrupting the background briefing (the subtle one)
Home kicks the Executive Briefing onto a background runspace on paint (`tony-ui.ps1:1055-1068`). If a
customization toggle re-rendered the whole Home view, **every toggle would re-kick that async work** -
exactly what "card customization should not break background briefing or async inbox scanning"
prohibits. So:
- the card flow lives in ONE container (`$script:HomeCardHost`) and the briefing host
  (`$script:HomeBriefHost`) is created **once per Home paint**;
- a customization change rebuilds **only the flow container** (`Children.Clear()` then re-add, which
  releases and re-establishes parentage) and **re-adds the same briefing host element**, so an in-flight
  async briefing still completes into the same Border and is never restarted;
- Home is not in `$script:ViewCacheable`, so leaving and returning rebuilds normally.

### Customize UX
A single **`Customize Home`** mini-button on the Home header row (no new tab, per the brief). Clicking it
toggles an inline panel listing every catalog card with: a **Show/Hide** toggle, **^ / v** reorder, a
**size** chip (small/medium/large, omitted for fixed-large cards), and **Reset to default**. Closing the
panel returns to the normal Home. Customization is entirely optional - a user who never opens it sees the
default layout forever.

## Architecture guarantees
- **SSOT intact.** Preferences store layout only; every card reads its owner live on each paint.
- No duplicate business data, no new providers/agents, no new dashboard tab, no automatic actions, no
  provider writes (cards are strictly read-only, and provider cards only *peek* a cache someone else
  warmed).
- Goals keeps its single store and owner functions.

## Files
- `core/home-layout.ps1` - **new**: preference model (load/save/normalize/reset/reorder/resize) + the
  card catalog metadata. Pure data, no UI, no WPF.
- `ui/tony-ui.ps1` - Home renders the card flow from the layout; the new card builders; the customize
  panel.
- `ui/life-workspaces.ps1` - Goals redesign.
- `dashboard.ps1` - dot-source the new core module.
- `.gitignore` - ignore `tony-alpha/home_layout.json`.
- Docs: this file; Project Status; Product Roadmap.

## Verification plan
Goals before form; `+ Add Goal` opens it; Cancel changes nothing; Edit/Pause/Resume/Complete/Delete
(with confirm) work; domain + status filters work; no goal duplication (store count stable). Home:
default layout; show/hide; reorder; sizing; reset; persistence across restart; all-hidden keeps the
briefing; no business data in the prefs file; Home paint stays fast; async briefing not restarted by a
toggle; Life OS / Executive Context / Inbox / Calendar / Communications / CRM / Workforce / Tony
conversation all still work. Plus full launch, parse, secret scan, git integrity.
