# GIOK — Known Issues & Limitations (v0.8 Alpha)

Honest list of what's not done, not perfect, or intentionally deferred. Nothing here is hidden —
that's the point. Severity: 🔴 blocks daily use · 🟠 friction · 🟡 cosmetic/expected.

## Intentional (by design, for now)
- 🟡 **Placeholder data is labeled, not live.** Life/Business Score, Weather, Agency Overview
  metrics, Upcoming Appointments, and Tony's Audit summary are samples (marked SAMPLE / "(sample)").
  They'll go live when integrations are approved.
- 🟡 **Tony's responses are generated, not AI.** The command bar, recommendations, and First
  Conversation acknowledgments use local logic, not an external model. The response generator is a
  clean swap point for AI later.
- 🟡 **No cloud / no sync.** GIOK is a single-machine, local-first app by design. Data lives in
  JSON files under `tony-alpha/`.
- 🟡 **Coming-soon workspaces.** Non-Negotiables, Family, Health, Financial, Agency, Home Projects,
  and Learning are dimmed in the sidebar and show a "coming soon" page.

## Friction / rough edges
- 🟠 **Data files show as git-modified after use.** `action_items.json`, `capture.json`,
  `end_of_day_audit.json`, `first_conversation.json`, and `identity/*.json` are written as you use
  the app (each stamps an `updated` time). This is normal for a personal app; commit them when you
  want to save your state, or ignore the churn.
- 🟠 **Emoji sidebar icons render monochrome in some setups.** They're built at runtime for
  portability; on the live app they should appear in color, but rendering can vary by Windows font
  configuration. Icons remain legible either way.
- 🟠 **Some older views aren't in the sidebar** (Issues, Weekly Review, Roadmap). They're reachable
  from Home quick links and the command bar (`open issues`, etc.).
- 🟠 **Window size/position aren't remembered** between launches (opens centered at a default size).
- 🟠 **First Conversation is single-pass.** Editing individual answers after completion isn't a
  dedicated flow yet — use **Settings → Restart First Conversation** to redo it.

## Cosmetic
- 🟡 **Two Home-ish icons.** "Home" (dashboard) and "Home Projects" are distinct items with
  different icons; labels are now clarified.
- 🟡 **Long free-text values** from the First Conversation become wide chips on the Identity
  Overview (they're trimmed for display; full text is kept).
- 🟡 **Fonts:** the theme prefers **Inter**; if Inter isn't installed, GIOK falls back to Segoe UI.

## AI provider (Claude) — connection notes
- 🟡 **Claude is connected but gated on a key.** Set `ANTHROPIC_API_KEY` (env var) or copy
  `dashboard/providers/claude.config.example.json` to `claude.config.json` (git-ignored) and add
  your key. With no key, Tony makes **no network call** and says he isn't fully connected yet.
- 🟠 **The "Ask Tony" call is synchronous.** When a key is configured, typing a free-text question
  in the command bar calls the provider on the UI thread, which will briefly block the window while
  it responds. Making this asynchronous is a planned follow-up.
- 🟡 **The live Claude round-trip was not exercised here** (no key in the build environment). The
  provider, contract mapping, fallback, and scope/model-hiding prompt were verified without any
  network call; the live call should be confirmed on the real machine once a key is set.

## Not yet verified end-to-end (environment limits)
- 🟠 Live click/keyboard interactions (checkboxes, steppers, typing, window pop-outs, Ctrl+K) were
  validated by driving the underlying functions and by inspection; they should be exercised by hand
  using `TESTING_CHECKLIST.md` on the real machine.

## Explicitly out of scope for v0.8
Cloud, mobile, Gmail, Calendar, GHL, and voice — all deferred by direction. Not bugs; not built.
