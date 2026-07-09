# 02 — Core Principles

These are the permanent principles of GIOK — engineering *and* product. They are not
suggestions. A feature that violates one of these is wrong by definition and must be reworked,
not shipped with an exception. When two principles tension, the human principles (People First)
win over the mechanical ones.

---

## Engineering principles

### 1. Single Source of Truth
Every fact lives in exactly one authoritative place. Views, screens, exports, and agents *read*
from it — they never become a second home for the same data. The registry and the structured
data files are the truth; the UI is a renderer of that truth.
*Already proven:* the desktop app reads `agents_registry.json` and `action_items.json` live;
nothing is copied into the UI.

### 2. Registry First
New entities register themselves before they are used. Agents, modules, departments,
integrations, memory, skills, workflows — each gets a stable ID and a registry entry. If it
isn't in the registry, it doesn't exist to the system. Build the registry entry first, the
feature second.

### 3. Load Only What Is Needed
Read the minimum required to answer the question at hand. Don't load the whole world to render a
card. This keeps GIOK fast, cheap, and scalable as data grows, and it's the discipline that lets
GIOK later run on a phone.

### 4. Never Duplicate Data
No copy-paste of state between files, screens, or windows. Popouts and Mission Control render
*snapshots* of the same source, never a second editable copy. Duplication is how systems start
lying; GIOK refuses it.

### 5. Capture Before Organize
The capture path must be frictionless and always available. Structure, tags, and routing come
*after* the thought is safely in the system. A capture that requires a decision to save will not
happen — and an unrecorded thought is a failure of the product, not the user.

---

## Product principles

### 6. AI Assists Humans
Tony augments Jake's judgment; he never replaces it. AI drafts, suggests, prepares, routes, and
reminds. Irreversible or outward-facing actions — sending money, contacting a client, deleting
records — always wait for a human decision. Autonomy is earned narrowly and revocably.

### 7. People First
Every feature is measured by its effect on relationships and wellbeing, not just output. "People
Matter More Than Money" is an engineering constraint: when a metric and a human need conflict on
screen, the human need is surfaced first.

### 8. Business Must Still Grow
GIOK is not a journaling toy. It must move the agency forward — more Checkups completed, fewer
leads dropped, more referrals asked for, more policies rightly placed. Calm is the feel; growth
is the result. A feature that soothes but doesn't help the business earn its keep is incomplete.

### 9. Every Feature Must Save Time
If a feature doesn't give Jake back time or attention, it doesn't ship. "Cool" is not a reason.
The test for any addition: *does this reduce the mental tax of running a life and a business?*
If the honest answer is no, cut it.

### 11. Every Workspace Is Self-Contained
Each workspace owns its own data, sections, and logic, and can evolve without redesigning the
rest of GIOK. A workspace **owns** its source-of-truth files; other workspaces may **reference**
that data but never **duplicate** it (this is Single Source of Truth applied at the workspace
level). Concretely: **Identity** owns `identity/*.json` (vision, goals, values, mission, legacy,
theme, journal, timeline); the Home dashboard and Life Score read it but keep no copy. Building a
new workspace should never require touching another. Self-contained workspaces are how GIOK grows
wide without becoming tangled.

### 10. Improve Continuously (Better, Not Busy)
Every meaningful area of life runs the same loop — **Plan → Execute → Audit → Improve** — and
GIOK exists to guide Jake around it, repeatedly. *GIOK is not designed to help people become
busy; it is designed to help people become better.* This principle shapes every workspace: each
should support planning, execution, honest audit, and improvement (see
[Continuous_Improvement.md](Continuous_Improvement.md)). The daily anchors are the **Morning
Briefing** and the **End of Day Audit** — which **never shames, always coaches.** A feature that
adds motion without adding progress fails this principle.

---

## How to apply these

- **Design review:** every proposal states which principles it upholds and which it risks.
- **Conflicts:** People First and AI Assists Humans override efficiency and cleverness, always.
- **Silence:** if the principles don't cover a case, extend this document deliberately — never
  let code establish a rule the constitution hasn't ratified.
- **Honesty clause:** unknown is labeled unknown; placeholder is labeled placeholder; a failure
  is reported, not hidden. This is non-negotiable and underpins every other principle.
