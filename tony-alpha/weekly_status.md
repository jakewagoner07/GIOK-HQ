# Weekly Status — Tony Alpha

> Refresh weekly. Candidate trigger: the existing *Weekly Command Center Reminder* task.

---

## 🗓️ Weekly Review — Week of 2026-07-06 → 2026-07-12

**Fleet health**
- Agents tracked: **22**
- healthy 0 · warning 0 · broken 0 · **unknown 22** · paused 0
- No runs observed yet (Phase 1 — command center stood up this week).

**What happened this week**
- Tony Alpha command center created (registry + tracking + reporting files).
- All 22 known scheduled tasks catalogued into `agents_registry.json`.
- 6 overlap candidates identified and logged.

**What needs attention**
1. Move agents off `unknown` by confirming schedules + last-run times.
2. Resolve the 6 overlap flags (`issues_log.md`).
3. Confirm no agent is silently broken (esp. connection guards: Buffer Connection Check, Agent Health Check).

**Category rollup**
| Category | # Agents | Notes |
|----------|----------|-------|
| comms | 2 | GHL SMS, Upwork |
| email | 3 | Yahoo, Triage, Junk Labeler |
| leads | 3 | Research/Referral, Engagement, GHL Text Batch |
| social | 3 | Scan, Weekly Plans, Content Batch |
| reporting | 3 | Morning Digest, Weekly Status Draft, Sunday Recap |
| planning | 1 | Sunday Weekly Planning |
| admin | 1 | Log Hours Reminder |
| system | 6 | Training Scanner, Health Check, Buffer Check, Command Center Reminder, Malwarebytes, Perf Review |

**Overlap watch (weekly clusters worth de-conflicting)**
- **Weekly cluster:** Weekly Status Draft · Sunday Weekly Planning · Sunday Evening Recap · Weekly Command Center Reminder — four weekly agents; confirm each has a distinct job.
- **Social cluster:** Social Media Scan · Weekly Social Plans · Content Batch — scan vs. plan vs. create.
- **Agent-oversight cluster:** Agent Health Check · Performance Review on Agents · (Tony Alpha itself).

---

## Template for future weeks

```
## 🗓️ Weekly Review — Week of YYYY-MM-DD → YYYY-MM-DD
- Fleet: X | healthy A · warning B · broken C · unknown D
- Ran as expected: <list>
- Missed / broken: <list>
- Flags opened / closed this week: <n / n>
- Focus for next week: <top 3>
```
